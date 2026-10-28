#!/usr/bin/env python3
"""Read-only, hash/UUID-pinned Harmony selector -> IL2CPP AOT candidate mapper.

Inputs use the existing metadata-v31/ordinary ARM64 Mach-O parser. No native
execution, game bytes, patching, signing, constructor or lobby action occurs.
Nested identities use the metadata nested_types graph, independently checked
against each child's declaring TypeIndex. Coroutine factory addresses NEVER
become MoveNext hook addresses. Naming-derived iterator bodies remain unbound
candidates until a separate runtime association proves the factory/body pair.

Layout references:
https://github.com/Perfare/Il2CppDumper/blob/master/Il2CppDumper/Il2Cpp/MetadataClass.cs
https://github.com/Perfare/Il2CppDumper/blob/master/Il2CppDumper/Il2Cpp/Il2CppClass.cs
"""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import json
import mmap
from pathlib import Path
import re
import sys

from map_native_methods import (MachO, Metadata, ParseError, PRIMITIVES, TypeNames,
                                bounds, digest, find_module, find_registrations, unpack)
from patch_native_entries import PatchError, branch, relocate_first_instruction


class TypeResolutionError(ParseError):
    """An unsupported/ambiguous signature cannot become a guessed match."""


class NestedMetadata(Metadata):
    def __init__(self, data):
        super().__init__(data)
        if self.tables['nested_types'][1] % 4:
            raise ParseError('Misaligned nested type table')
        self.parents, self.children, self._names = {}, defaultdict(list), {}
        for owner, row in enumerate(self.types):
            start, count = row[12], row[20]
            if not count:
                continue
            bounds(start, count, self.count('nested_types', 4))
            for position in range(start, start + count):
                child = self.record('nested_types', 4, position, '<i')[0]
                bounds(child, 1, len(self.types))
                if child == owner or child in self.parents:
                    raise ParseError('Nested type has self/multiple ownership')
                if self.image_for_type(owner) != self.image_for_type(child):
                    raise ParseError('Nested type crosses owning images')
                self.parents[child] = owner
                self.children[owner].append(child)
        for index, row in enumerate(self.types):
            if (row[3] != 0xffffffff) != (index in self.parents):
                raise ParseError('Nested table and declaring TypeIndex disagree')
            self.type_name(index)  # validates acyclic bounded ownership

    def type_name(self, index, seen=()):
        bounds(index, 1, len(self.types))
        if index in self._names:
            return self._names[index]
        if len(seen) > 32 or index in seen:
            raise ParseError('Nested type ownership cycle/depth limit')
        row = self.types[index]
        local = self.string(row[0])
        if index in self.parents:
            result = self.type_name(self.parents[index], seen + (index,)) + '+' + local
        else:
            result = '.'.join(p for p in (self.string(row[1]), local) if p)
        self._names[index] = result
        return result


def erase_arity(name):
    return re.sub(r'`[1-9][0-9]*(?=\+|$)', '', name)


class TypeCatalog:
    def __init__(self, metadata):
        self.metadata = metadata
        self.named, self.generic = defaultdict(list), defaultdict(list)
        for i, row in enumerate(metadata.types):
            name = metadata.type_name(i)
            self.named[name].append(i)
            if row[6] != 0xffffffff:
                container = metadata.record('generic_containers', 16, row[6], '<4i')
                if container[0] != i or container[1] <= 0 or container[1] > 128 or container[2] != 0:
                    raise ParseError('Generic class container ownership/arity mismatch')
                self.generic[(erase_arity(name), container[1])].append(i)

    def unique_name(self, name):
        matches = self.named.get(name, [])
        if len(matches) != 1:
            raise TypeResolutionError('Named type absent/ambiguous: ' + name)
        return name

    def generic_name(self, name, args):
        explicit_name, name = name, erase_arity(name)
        matches = self.generic.get((name, len(args)), [])
        if '`' in explicit_name:
            matches = [i for i in matches if self.metadata.type_name(i) == explicit_name]
        if len(matches) != 1:
            raise TypeResolutionError('Generic definition absent/ambiguous or wrong arity: ' + name)
        return name + '<' + ','.join(args) + '>'

    def selector(self, value):
        if not isinstance(value, str) or not value or len(value) > 4096:
            raise TypeResolutionError('Invalid selector type text')
        text, position = value, 0

        def whitespace():
            nonlocal position
            while position < len(text) and text[position].isspace():
                position += 1

        def parse(depth=0):
            nonlocal position
            if depth > 32:
                raise TypeResolutionError('Selector type recursion limit')
            whitespace()
            start = position
            while position < len(text) and text[position] not in '<>,&*[]':
                position += 1
            name = text[start:position].strip().replace('/', '+')
            if not name or any(c.isspace() for c in name):
                raise TypeResolutionError('Malformed selector named type')
            if position < len(text) and text[position] == '<':
                position += 1
                arguments = []
                while True:
                    arguments.append(parse(depth + 1))
                    whitespace()
                    if position < len(text) and text[position] == ',':
                        position += 1
                        continue
                    if position >= len(text) or text[position] != '>':
                        raise TypeResolutionError('Unterminated generic selector')
                    position += 1
                    break
                result = self.generic_name(name, arguments)
            else:
                result = self.unique_name(name)
            whitespace()
            while position < len(text):
                suffix = text[position]
                if suffix == '[':
                    end = text.find(']', position)
                    if end < 0:
                        raise TypeResolutionError('Unterminated array selector')
                    rank = text[position + 1:end]
                    if rank != '*' and any(c != ',' for c in rank):
                        raise TypeResolutionError('Unsupported array bounds selector')
                    result += '[' + rank + ']'
                    position = end + 1
                elif suffix == '*':
                    result += '*'
                    position += 1
                elif suffix == '&':
                    result += '&'
                    position += 1
                    whitespace()
                    if position < len(text) and text[position] not in ',>':
                        raise TypeResolutionError('Byref must be the final type suffix')
                    break
                else:
                    break
                whitespace()
            return result

        result = parse()
        whitespace()
        if position != len(text):
            raise TypeResolutionError('Trailing selector type syntax')
        return result


class ExactTypeNames(TypeNames):
    def __init__(self, native, metadata, registration, catalog):
        super().__init__(native, metadata, registration)
        self.catalog = catalog

    def at_index(self, index):
        bounds(index, 1, self.registration['types_count'])
        return self.at_pointer(self.native.words(self.registration['types'] + index * 8, 1)[0])

    def definition_index(self, pointer, depth=0):
        if depth > 32:
            raise ParseError('Declaring type recursion limit')
        value, bits = unpack(self.native.data, '<QI', self.native.va_to_offset(pointer, 12))
        kind = (bits >> 16) & 255
        if bits & (1 << 29):
            raise ParseError('Declaring type is unexpectedly byref')
        if kind in (17, 18):
            bounds(value, 1, len(self.metadata.types))
            return value
        if kind in PRIMITIVES:
            name = self.catalog.unique_name(PRIMITIVES[kind])
            return self.catalog.named[name][0]
        if kind == 21:
            return self.definition_index(self.native.words(value, 1)[0], depth + 1)
        raise ParseError('Unsupported declaring type representation')

    def validate_nested(self):
        for child, owner in self.metadata.parents.items():
            index = self.metadata.types[child][3]
            bounds(index, 1, self.registration['types_count'])
            pointer = self.native.words(self.registration['types'] + index * 8, 1)[0]
            if self.definition_index(pointer) != owner:
                raise ParseError('Nested parent and registered declaring TypeIndex disagree')

    def at_pointer(self, pointer, depth=0):
        if depth > 32:
            raise TypeResolutionError('Native type recursion limit')
        value, bits = unpack(self.native.data, '<QI', self.native.va_to_offset(pointer, 12))
        kind = (bits >> 16) & 255
        if (bits >> 24) & 31:
            raise TypeResolutionError('Custom modified type is unsupported')
        if kind in PRIMITIVES:
            name = self.catalog.unique_name(PRIMITIVES[kind])
        elif kind in (17, 18):
            name = self.catalog.unique_name(self.metadata.type_name(value))
        elif kind in (15, 16, 29):
            if kind == 16 and bits & (1 << 29):
                raise TypeResolutionError('Duplicate byref representation')
            name = self.at_pointer(value, depth + 1) + {15: '*', 16: '&', 29: '[]'}[kind]
        elif kind == 20:
            offset = self.native.va_to_offset(value, 32)
            element, rank, sizes, lowers, _, _ = unpack(self.native.data, '<QBBB5xQQ', offset)
            if not 1 <= rank <= 32 or sizes or lowers:
                raise TypeResolutionError('Unsupported rectangular array rank/bounds')
            name = self.at_pointer(element, depth + 1) + ('[*]' if rank == 1 else '[' + ',' * (rank - 1) + ']')
        elif kind == 21:
            base, inst = self.native.words(value, 2)
            argc, argv = self.native.words(inst, 2)
            if not 1 <= argc <= 128:
                raise TypeResolutionError('Unsupported generic argument count')
            args = [self.at_pointer(v, depth + 1) for v in self.native.words(argv, argc)]
            name = self.catalog.generic_name(self.at_pointer(base, depth + 1), args)
        elif kind in (19, 30):
            raise TypeResolutionError('Open type/method generic parameter is unsupported')
        else:
            raise TypeResolutionError('Unsupported IL2CPP type kind: %d' % kind)
        return name + ('&' if bits & (1 << 29) else '')


def module_pointer_array(native, pointer, count):
    if not count:
        return (), 'empty'
    try:
        return native.words(pointer, count), 'file_backed'
    except ParseError:
        # Mach-O explicitly zero-fills the non-file-backed tail of a segment.
        # Some modules containing only external declarations put their all-null
        # initial method table there. Do not infer later runtime writes.
        segments = [s for s in native.segments if pointer % 8 == 0 and
            s['va'] + s['filesize'] <= pointer and pointer <= s['va'] + s['vsize'] and
            count * 8 <= s['va'] + s['vsize'] - pointer]
        if len(segments) != 1 or not segments[0]['protection'] & 2:
            raise
        return (0,) * count, 'zero_filled_initial_image_only'


def registered_modules(native, metadata, anchor):
    metas, codes, arrays = find_registrations(native, metadata, anchor)
    if len(metas) != 1 or len(codes) != 1 or arrays != [codes[0]['modules']]:
        raise ParseError('Metadata/code registration is not uniquely cross-validated')
    code = codes[0]
    modules, entries = {}, Counter()
    for pointer in native.words(code['modules'], code['modules_count']):
        name_pointer, count, pointers = native.words(pointer, 3)
        name = native.cstring(name_pointer)
        images = [image for image in metadata.images if image['name'] == name]
        if len(images) != 1 or name in modules:
            raise ParseError('Codegen module image ownership is ambiguous')
        expected = metadata.image_method_count(images[0])
        if count != expected or count > 1000000:
            raise ParseError('Codegen module method token count mismatch')
        values, storage = module_pointer_array(native, pointers, count)
        if any(value and not native.is_code(value) for value in values):
            raise ParseError('Codegen module has a nonexecutable/unaligned method entry')
        entries.update(value for value in values if value)
        modules[name] = {'va': pointer, 'count': count, 'pointers': pointers, 'image': images[0], 'storage': storage}
    if set(modules) != {image['name'] for image in metadata.images}:
        raise ParseError('Registered module set differs from metadata images')
    row = native.words(code['va'], 17)
    generics = native.words(row[3], row[2]) if row[2] else ()
    if any(value and not native.is_code(value) for value in generics):
        raise ParseError('Generic method table has invalid executable entries')
    generic_entries = Counter(value for value in generics if value)
    return metas[0], code, modules, entries, generic_entries


def method_declaration(metadata, types, owner, method_index, method):
    parameters = []
    for index in range(method[4], method[4] + method[10]):
        row = metadata.record('parameters', 12, index, '<IIi')
        parameters.append(types.at_index(row[2]))
    return {'declaring_type': metadata.type_name(owner),
            'owning_image': metadata.image_for_type(owner)['name'],
            'name': metadata.string(method[0]), 'parameter_types': parameters,
            'return_type': types.at_index(method[2]), 'static': bool(method[7] & 0x10),
            'metadata_type_index': owner, 'metadata_method_index': method_index,
            'metadata_token': hex(method[6]), 'token_rid': method[6] & 0xffffff,
            'generic': method[5] != -1, 'abstract': bool(method[7] & 0x400)}


def signature(method):
    return ('static ' if method['static'] else 'instance ') + method['return_type'] + ' ' + method['declaring_type'] + '::' + method['name'] + '(' + ','.join(method['parameter_types']) + ')'


def native_candidate(native, declaration, module, slot, entry_counts, generic_counts, linkedit):
    result = dict(declaration)
    result['signature'] = signature(declaration)
    rid = declaration['token_rid']
    if not 1 <= rid <= module['count']:
        raise ParseError('Method RID does not fit its owning module')
    pointer = 0 if module['storage'] == 'zero_filled_initial_image_only' else native.words(module['pointers'] + (rid - 1) * 8, 1)[0]
    result.update({'association': 'offline_codegen_module_token_rid_candidate',
                   'runtime_association_verified': False, 'native_rva': None,
                   'shared_entry': False, 'first_instruction_relocation': {'status': 'no_native_entry'}})
    if not pointer:
        return result
    result['native_rva'] = hex(pointer - native.preferred_base)
    result['registered_module_entry_count'] = entry_counts[pointer]
    result['registered_generic_entry_count'] = generic_counts[pointer]
    result['shared_entry'] = entry_counts[pointer] + generic_counts[pointer] > 1
    trampoline = linkedit + slot * 64 + 16
    try:
        word = unpack(native.data, '<I', native.va_to_offset(pointer, 4))[0]
        branch(pointer, trampoline - 16)
        _, details = relocate_first_instruction(word, pointer, trampoline)
        result['first_instruction_relocation'] = {'status': 'supported_at_report_probe_slot', **details,
            'probe_trampoline_rva': hex(trampoline - native.preferred_base)}
    except PatchError as error:
        result['first_instruction_relocation'] = {'status': 'unsupported', 'reason': str(error)}
    return result


def build_report(native, metadata, document):
    selectors = document.get('selectors')
    if document.get('schema') != 'ehr.native-target-selectors.v1' or not isinstance(selectors, list) or not 1 <= len(selectors) <= 4096:
        raise ParseError('Unsupported/oversized selector document')
    if any(not isinstance(row, dict) for row in selectors):
        raise ParseError('Every selector must be an object')
    for row in selectors:
        for key in ('selectorId', 'image', 'declaringType', 'methodName', 'methodKind', 'returnType'):
            if not isinstance(row.get(key), str) or not row[key] or len(row[key]) > 4096:
                raise ParseError('Invalid selector text field: ' + key)
        if not isinstance(row.get('isStatic'), bool) or not isinstance(row.get('parameterTypes'), list) or len(row['parameterTypes']) > 128:
            raise ParseError('Invalid selector static/parameter fields')
    ids = [row['selectorId'] for row in selectors]
    if any(not isinstance(value, str) or not value for value in ids) or len(set(ids)) != len(ids):
        raise ParseError('Selector IDs must be nonempty and unique')
    anchor = find_module(native, metadata, 'Assembly-CSharp.dll')
    registration, code, modules, entries, generic_entries = registered_modules(native, metadata, anchor)
    catalog = TypeCatalog(metadata)
    types = ExactTypeNames(native, metadata, registration, catalog)
    types.validate_nested()
    linkedit = [segment['va'] for segment in native.segments if segment['name'] == '__LINKEDIT']
    if len(linkedit) != 1:
        raise ParseError('Unique LINKEDIT is required for a patcher-compatible relocation probe')
    owners = defaultdict(list)
    for i in range(len(metadata.types)):
        owners[(metadata.image_for_type(i)['name'], metadata.type_name(i))].append(i)
    rows, selected_entries = [], defaultdict(list)
    for slot, selector in enumerate(selectors):
        row = {'selector_id': selector['selectorId'], 'selector': selector,
               'status': 'unresolved', 'native_rva': None, 'native_hooks_installed': False}
        rows.append(row)
        try:
            image = selector['image']
            if not isinstance(image, str) or not image:
                raise TypeResolutionError('Missing selector owning image')
            image = image if image.endswith('.dll') else image + '.dll'
            owner_name = selector['declaringType'].replace('/', '+')
            candidates = owners.get((image, owner_name), [])
            if not candidates:
                row['status'] = 'declaring_type_not_found'
                continue
            if len(candidates) != 1:
                row['status'] = 'ambiguous_declaring_type'
                continue
            owner = candidates[0]
            if not isinstance(selector['isStatic'], bool) or not isinstance(selector['parameterTypes'], list):
                raise TypeResolutionError('Invalid selector static/parameter fields')
            expected_parameters = [catalog.selector(value) for value in selector['parameterTypes']]
            expected_return = catalog.selector(selector['returnType'])
            exact, family, unsupported = [], [], []
            for method_index, method in metadata.methods_for_type(owner):
                if metadata.string(method[0]) != selector['methodName']:
                    continue
                try:
                    declaration = method_declaration(metadata, types, owner, method_index, method)
                except TypeResolutionError as error:
                    unsupported.append({'metadata_method_index': method_index, 'reason': str(error)})
                    continue
                family.append(declaration)
                if (declaration['parameter_types'] == expected_parameters and
                    declaration['return_type'] == expected_return and declaration['static'] == selector['isStatic']):
                    exact.append(declaration)
            row['normalized_selector_signature'] = {'declaring_type': owner_name, 'owning_image': image,
                'parameter_types': expected_parameters, 'return_type': expected_return, 'static': selector['isStatic']}
            if len(exact) != 1:
                row['status'] = 'ambiguous_exact_signature' if exact else 'exact_signature_not_found'
                row['same_name_metadata_declarations'] = family
                row['unsupported_same_name_declarations'] = unsupported
                continue
            mapped = native_candidate(native, exact[0], modules[image], slot, entries, generic_entries, linkedit[0])
            if selector.get('methodKind') == 'CoroutineMoveNext':
                row['status'] = 'coroutine_MoveNext_unbound'
                row['factory_candidate_only'] = mapped
                row['body_candidates_unbound'] = []
                generated = re.compile(r'^<' + re.escape(selector['methodName']) + r'>d__[0-9]+$')
                for child in metadata.children.get(owner, []):
                    if not generated.fullmatch(metadata.string(metadata.types[child][0])):
                        continue
                    for method_index, method in metadata.methods_for_type(child):
                        if metadata.string(method[0]) != 'MoveNext':
                            continue
                        declaration = method_declaration(metadata, types, child, method_index, method)
                        if declaration['parameter_types'] or declaration['return_type'] != 'System.Boolean' or declaration['static']:
                            continue
                        candidate = native_candidate(native, declaration, modules[image], slot, entries, generic_entries, linkedit[0])
                        candidate['association'] = 'compiler_generated_name_and_nested_owner_candidate_only'
                        row['body_candidates_unbound'].append(candidate)
                row['association_required'] = 'Observe the real iterator returned by this exact factory; name/nested-owner evidence does not prove the pair.'
                continue
            if selector.get('methodKind') not in ('Normal', 'Getter', 'Setter'):
                row['status'] = 'unsupported_method_kind'
                continue
            row['candidate'] = mapped
            row['native_rva'] = mapped['native_rva']
            row['status'] = 'exact_metadata_native_candidate' if mapped['native_rva'] else 'exact_metadata_no_native_entry'
            if mapped['native_rva']:
                selected_entries[mapped['native_rva']].append(row['selector_id'])
        except TypeResolutionError as error:
            row['status'] = 'selector_type_unsupported_or_ambiguous'
            row['reason'] = str(error)
    for row in rows:
        if row.get('native_rva'):
            row['selected_entry_selector_ids'] = selected_entries[row['native_rva']]
    return {'schema': 'ehr.harmony-native-target-map.v1', 'metadata_version': metadata.version,
        'framework_uuid': native.uuid, 'preferred_image_base': hex(native.preferred_base),
        'runtime_execution_performed': False, 'native_hooks_installed': False,
        'upstream_commit': document.get('upstreamCommit'),
        'registration_validation': {'status': 'unique_structurally_cross_validated_candidates',
            'metadata_registration_preferred_va': hex(registration['va']),
            'code_registration_preferred_va': hex(code['va']), 'module_count': len(modules),
            'nested_type_parent_relations_validated': len(metadata.parents),
            'zero_filled_module_tables_initial_image_only': [name for name in sorted(modules)
                if modules[name]['storage'] == 'zero_filled_initial_image_only'],
            'owning_modules': [{'image': name, 'method_pointer_count': modules[name]['count'],
                'module_preferred_va': hex(modules[name]['va'])} for name in sorted({r['selector']['image'] if r['selector']['image'].endswith('.dll') else r['selector']['image'] + '.dll' for r in rows}) if name in modules]},
        'relocation_probe': {'layout': 'existing patcher: 64-byte slot per selector input ordinal, trampoline at slot+16, inserted at original LINKEDIT VA',
            'entry_batch_is_not_generated': True, 'shared_entries_must_be_rejected_or_have_explicit_combined_dispatch': True,
            'final_hook_subset_order_and_layout_require_revalidation': True},
        'shared_entry_validation_scope': 'All initial codegen-module method-pointer entries and registered generic-method pointers; runtime writes and unrelated native/adjustor/invoker aliases are not inferred.',
        'summary': {'selector_count': len(rows), 'status_counts': dict(sorted(Counter(r['status'] for r in rows).items())),
            'unique_selected_native_entries': len(selected_entries),
            'selected_candidates_with_shared_registered_entries': sum(bool(r.get('candidate', {}).get('shared_entry')) for r in rows),
            'relocation_status_counts': dict(sorted(Counter(r['candidate']['first_instruction_relocation']['status'] for r in rows if 'candidate' in r).items()))},
        'selectors': rows,
        'limits': ['Metadata/name/codegen token-RID correspondence is an offline candidate; no runtime method association or callback ABI is proven.',
            'No method body bytes, instruction words, runtime pointers, game assets, or game code are emitted.',
            'Unsupported, absent or ambiguous overloads are reported, never chosen by name/arity fallback.',
            'Coroutine factory pointers are diagnostic-only and never populate the selector native_rva.']}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('framework', 'metadata', 'selectors', 'pins', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args(argv)
    inputs = [args.framework.resolve(), args.metadata.resolve(), args.selectors.resolve(), args.pins.resolve()]
    if args.output.resolve() in inputs:
        parser.error('Output must not overwrite any input')
    try:
        before = [path.stat() for path in inputs]
        if before[0].st_size > 1024**3 or before[1].st_size > 256 * 1024**2 or any(s.st_size > 16 * 1024**2 for s in before[2:]):
            raise ParseError('Input size limit exceeded')
        hashes = [digest(path) for path in inputs]
        pins = json.loads(inputs[3].read_text())
        for i, key in enumerate(('framework', 'metadata')):
            expected = pins['input_pins'][key]
            if hashes[i] != expected['sha256'] or before[i].st_size != expected['size']:
                raise ParseError('Pinned ' + key + ' SHA256/size does not match input')
        document = json.loads(inputs[2].read_text())
        with inputs[0].open('rb') as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as image:
            native = MachO(image)
            if native.uuid != pins['framework_uuid']:
                raise ParseError('Pinned framework UUID does not match input')
            with inputs[1].open('rb') as m, mmap.mmap(m.fileno(), 0, access=mmap.ACCESS_READ) as meta:
                report = build_report(native, NestedMetadata(meta), document)
        after = [path.stat() for path in inputs]
        if any((a.st_size, a.st_mtime_ns, a.st_ino) != (b.st_size, b.st_mtime_ns, b.st_ino) for a, b in zip(before, after)):
            raise ParseError('An input changed during inspection')
        report['input_pins'] = {key: {'filename': path.name, 'size': stat.st_size, 'sha256': sha}
            for key, path, stat, sha in zip(('framework', 'metadata', 'selectors', 'pin_report'), inputs, before, hashes)}
        report['tool_pins'] = {name: digest(Path(__file__).with_name(name)) for name in
            ('map_harmony_native_targets.py', 'map_native_methods.py', 'patch_native_entries.py')}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open('x', encoding='utf-8') as output:
            json.dump(report, output, indent=2, ensure_ascii=True)
            output.write('\n')
        print(json.dumps({'summary': report['summary'], 'report': str(args.output)}, sort_keys=True))
        return 0
    except (ParseError, PatchError, OSError, UnicodeError, KeyError, TypeError, json.JSONDecodeError) as error:
        parser.exit(2, type(error).__name__ + ': ' + str(error) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
