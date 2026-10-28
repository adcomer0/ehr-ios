#!/usr/bin/env python3
"""Generate a PRIVATE standalone XCTest overlay for read-only native binding audit.

Only own generic audit code belongs in Git. Exact game API facts stay in the
explicitly selected output directory outside every Git checkout. No game bytes
are emitted and no audited method is invoked by the generated test.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import mmap
from pathlib import Path
import re
import subprocess

from map_native_methods import MachO, ParseError, digest
from map_harmony_native_targets import NestedMetadata, TypeCatalog, erase_arity


class Shapes:
    def __init__(self, metadata):
        self.metadata = metadata
        self.catalog = TypeCatalog(metadata)
        self.rows, self.ids = [], {}

    def store(self, key, fields):
        if key not in self.ids:
            self.ids[key] = len(self.rows)
            self.rows.append({'id': len(self.rows), **fields})
        return self.ids[key]

    def named(self, index):
        name = self.metadata.type_name(index)
        self.catalog.unique_name(name)
        chain, outer = [], index
        while True:
            chain.append(self.metadata.string(self.metadata.types[outer][0]))
            if outer not in self.metadata.parents:
                break
            outer = self.metadata.parents[outer]
        return self.store(('named', index), {'kind': 'named', 'canonical': name,
            'image': self.metadata.image_for_type(index)['name'],
            'namespace': self.metadata.string(self.metadata.types[outer][1]),
            'name': '+'.join(reversed(chain)), 'metadata_type_index': index})

    def expression(self, text):
        canonical = self.catalog.selector(text)
        position = 0

        def parse(depth=0):
            nonlocal position
            if depth > 32:
                raise ParseError('Audit type shape depth limit')
            start = position
            while position < len(canonical) and canonical[position] not in '<>,&*[]':
                position += 1
            name = canonical[start:position]
            if not name:
                raise ParseError('Empty audit type atom')
            if position < len(canonical) and canonical[position] == '<':
                position += 1
                args = []
                while True:
                    args.append(parse(depth+1))
                    if position < len(canonical) and canonical[position] == ',':
                        position += 1
                        continue
                    if position >= len(canonical) or canonical[position] != '>':
                        raise ParseError('Malformed generic audit shape')
                    position += 1
                    break
                matches = self.catalog.generic.get((erase_arity(name),len(args)), [])
                if len(matches) != 1:
                    raise ParseError('Generic audit definition not unique')
                definition = self.named(matches[0])
                rendered = erase_arity(name)+'<'+','.join(self.rows[i]['canonical'] for i in args)+'>'
                result = self.store(('generic', definition, tuple(args)), {'kind': 'generic',
                    'definition': definition, 'arguments': args, 'canonical': rendered})
            else:
                matches = self.catalog.named.get(name, [])
                if len(matches) != 1:
                    raise ParseError('Audit named type not unique: '+name)
                result = self.named(matches[0])
            while position < len(canonical) and canonical[position] in '[&*':
                if canonical[position:position+2] == '[]':
                    position += 2
                    result = self.store(('vector', result), {'kind': 'vector', 'element': result,
                        'canonical': self.rows[result]['canonical']+'[]'})
                elif canonical[position] == '&':
                    position += 1
                    result = self.store(('byref', result), {'kind': 'byref', 'element': result,
                        'canonical': self.rows[result]['canonical']+'&'})
                else:
                    raise ParseError('Pointer/rectangular audit shapes are not yet supported')
            return result

        result = parse()
        if position != len(canonical):
            raise ParseError('Trailing audit type shape text')
        return result


def facts_for_report(metadata, report):
    if report.get('schema') != 'ehr.harmony-native-target-map.v1':
        raise ParseError('Expected exact pinned native candidate report')
    shapes, rows = Shapes(metadata), []
    skipped = []
    owners = {}
    for index in range(len(metadata.types)):
        owners.setdefault((metadata.image_for_type(index)['name'], metadata.type_name(index)), []).append(index)
    for row in report['selectors']:
        if row['status'] == 'coroutine_MoveNext_unbound':
            skipped.append({'selector_id': row['selector_id'], 'reason': row['status']})
            continue
        if row['status'] != 'exact_metadata_native_candidate':
            raise ParseError('Ordinary selector lacks an exact native candidate')
        candidate = row['candidate']
        matches = owners.get((candidate['owning_image'],candidate['declaring_type']), [])
        if len(matches) != 1 or matches[0] != candidate['metadata_type_index']:
            raise ParseError('Candidate owner identity differs from pinned metadata')
        owner = shapes.named(matches[0])
        parameters = [shapes.expression(value) for value in candidate['parameter_types']]
        returns = shapes.expression(candidate['return_type'])
        rva = int(candidate['native_rva'],16)
        if not rva or rva%4:
            raise ParseError('Candidate entry is not an aligned nonzero RVA')
        rows.append({'selector_id': row['selector_id'], 'declaring_type': owner,
            'method_name': candidate['name'], 'parameter_types': parameters, 'return_type': returns,
            'is_static': candidate['static'], 'expected_rva': candidate['native_rva'],
            'offline_metadata_token': candidate['metadata_token'], 'canonical_signature': candidate['signature']})
    if len({row['selector_id'] for row in rows}) != len(rows):
        raise ParseError('Repeated candidate selector IDs')
    return {'schema':'ehr.runtime-binding-audit-facts.v1', 'framework_uuid':report['framework_uuid'],
        'input_pins':report['input_pins'], 'types':shapes.rows, 'methods':rows,
        'expected_method_count':len(rows), 'excluded_unbound_selectors':skipped,
        'policy':'Resolve exact runtime class names, vector classes and real closed generic classes; no audited target invocation.'}


def outside_git(path):
    for parent in [path,*path.parents]:
        if (parent/'.git').exists():
            raise ParseError('Private output must be outside Git checkouts')


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    for option in ('source-root','base-test','map','framework','metadata','output'):
        parser.add_argument('--'+option,type=Path,required=True)
    args=parser.parse_args(argv)
    try:
        source=args.source_root.resolve(); output=args.output.resolve();outside_git(output)
        inputs=[args.base_test.resolve(),args.map.resolve(),args.framework.resolve(),args.metadata.resolve()]
        if any(output==path or output in path.parents for path in inputs) or output==source or source in output.parents:
            raise ParseError('Output must be a new independent directory outside source/inputs')
        report=json.loads(args.map.read_text())
        for key,path in [('framework',args.framework),('metadata',args.metadata)]:
            expected=report['input_pins'][key]
            if path.stat().st_size!=expected['size'] or digest(path)!=expected['sha256']:
                raise ParseError('Pinned '+key+' does not match read-only input')
        before=[path.stat() for path in inputs]
        with args.framework.open('rb') as f,mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as framework:
            if MachO(framework).uuid!=report['framework_uuid']:
                raise ParseError('Pinned framework UUID mismatch')
        with args.metadata.open('rb') as f,mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as data:
            facts=facts_for_report(NestedMetadata(data),report)
        template=(Path(__file__).resolve().parents[1]/'tests/runtime/RuntimeBindingAudit.inc').read_text()
        base=args.base_test.read_text()
        boundary='}\n\n@interface NativeRuntimeTests : XCTestCase'
        if base.count(boundary)!=1:
            raise ParseError('Unexpected XCTest namespace/interface boundary')
        if 'NSDictionary *allBindings = exerciseAllHarmonyRuntimeBindings' in base:
            raise ParseError('Base test already includes this audit')
        encoded=json.dumps(facts,separators=(',',':'),ensure_ascii=True)
        if ')EHRAUDIT"' in encoded:
            raise ParseError('Unsafe raw literal delimiter')
        payload='\nstatic const char EHRAuditFactsJSON[] = R"EHRAUDIT('+encoded+')EHRAUDIT";\n'+template+'\n'
        base='#include <string>\n#include <utility>\n'+base.replace(boundary,payload+boundary)
        anchor='    NSDictionary *gateway = exerciseGateway();'
        if base.count(anchor)!=1:
            raise ParseError('Missing ready-runtime audit insertion point')
        base=base.replace(anchor,anchor+'\n    NSDictionary *allBindings = exerciseAllHarmonyRuntimeBindings(EHRAuditFactsJSON);\n    XCTAssertTrue([allBindings[@"success"] boolValue], @"%@", allBindings);')
        anchor='        @"runtimeGateway": gateway,'
        if base.count(anchor)!=1:
            raise ParseError('Missing JSON proof insertion point')
        base=base.replace(anchor,anchor+'\n        @"allHarmonyRuntimeBindings": allBindings,')
        after=[path.stat() for path in inputs]
        if any((a.st_size,a.st_mtime_ns,a.st_ino)!=(b.st_size,b.st_mtime_ns,b.st_ino) for a,b in zip(before,after)):
            raise ParseError('An input changed during generation')
        output.mkdir(parents=True,exist_ok=False)
        (output/'binding-audit-facts.local.json').write_text(json.dumps(facts,indent=2)+'\n')
        (output/'NativeRuntimeBindingAudit.local.mm').write_text(base)
        manifest={'schema':'ehr.runtime-binding-audit-generation.v1','method_count':len(facts['methods']),
            'type_shape_count':len(facts['types']), 'excluded_unbound_count':len(facts['excluded_unbound_selectors']),
            'input_sha256':{path.name:digest(path) for path in inputs},
            'own_generator_sha256':digest(Path(__file__)),
            'own_audit_source_sha256':hashlib.sha256(template.encode()).hexdigest(),
            'overlay_sha256':digest(output/'NativeRuntimeBindingAudit.local.mm'),
            'audited_target_invocations':0, 'runtime_execution_performed':False}
        (output/'generation-manifest.local.json').write_text(json.dumps(manifest,indent=2)+'\n')
        print(json.dumps({'output':str(output),**manifest},sort_keys=True))
        return 0
    except (OSError,ParseError,UnicodeError,KeyError,TypeError,ValueError) as error:
        parser.exit(2,type(error).__name__+': '+str(error)+'\n')


if __name__=='__main__':raise SystemExit(main())
