"""Original synthetic metadata inputs for private runtime-audit generation."""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
sys.path.insert(0,str(Path(__file__).resolve().parent))
from generate_runtime_binding_audit import Shapes, facts_for_report
from map_harmony_native_targets import MachO, NestedMetadata, ParseError, build_report
from test_map_harmony_native_targets import own_metadata, own_native, selector, document


def synthetic_report():
    native,metadata=own_native(),own_metadata()
    report=build_report(MachO(native),NestedMetadata(metadata),document(
        selector(),selector('generic',name='Generic',params=['Fixture.Box<Fixture.Outer+Inner>[]']),
        selector('nested-owner',owner='Fixture.Outer+Inner',name='Pick',params=[],returns='System.Boolean'),
        selector('iterator',name='Run',params=[],returns='System.Collections.IEnumerator',kind='CoroutineMoveNext')))
    report['input_pins']={key:{'size':len(value),'sha256':hashlib.sha256(value).hexdigest()}
        for key,value in [('framework',native),('metadata',metadata)]}
    return report


class RuntimeBindingAuditTests(unittest.TestCase):
    def test_nested_namespace_and_generic_vector_dependencies_come_from_metadata(self):
        shapes=Shapes(NestedMetadata(own_metadata()))
        nested=shapes.expression('Fixture.Outer/Inner')
        self.assertEqual(shapes.rows[nested]['namespace'],'Fixture')
        self.assertEqual(shapes.rows[nested]['name'],'Outer+Inner')
        vector=shapes.expression('Fixture.Box< Fixture.Outer+Inner >[]')
        generic=shapes.rows[vector]['element']
        definition=shapes.rows[generic]['definition']
        self.assertEqual(shapes.rows[vector]['kind'],'vector')
        self.assertEqual(shapes.rows[generic]['arguments'],[nested])
        self.assertEqual(shapes.rows[definition]['name'],'Box`1')
        self.assertLess(definition,generic);self.assertLess(nested,generic);self.assertLess(generic,vector)
        self.assertEqual(shapes.expression('Fixture.Box`1<Fixture.Outer/Inner>[]'),vector)

    def test_explicit_byref_shape_has_real_named_dependency_and_no_dot_guess(self):
        shapes=Shapes(NestedMetadata(own_metadata()))
        byref=shapes.expression('System.Int32&')
        self.assertEqual(shapes.rows[byref]['kind'],'byref')
        dependency=shapes.rows[byref]['element']
        self.assertEqual(shapes.rows[dependency]['name'],'Int32')
        self.assertEqual(shapes.rows[dependency]['namespace'],'System')
        self.assertLess(dependency,byref)
        for name in ['Fixture.Outer.Inner','Fixture.Box`2<System.Int32>','System.Int32*','System.Int32[,]']:
            with self.assertRaises(ParseError,msg=name):shapes.expression(name)

    def test_only_exact_ordinary_candidates_are_audited_and_factory_is_excluded(self):
        facts=facts_for_report(NestedMetadata(own_metadata()),synthetic_report())
        self.assertEqual(facts['expected_method_count'],3)
        self.assertEqual(len(facts['excluded_unbound_selectors']),1)
        self.assertEqual(facts['excluded_unbound_selectors'][0]['selector_id'],'iterator')
        self.assertTrue(all(row['selector_id']!='iterator' for row in facts['methods']))
        self.assertEqual(facts['methods'][0]['expected_rva'],'0x1000')

    def test_owner_pin_and_nonexact_candidates_fail_closed(self):
        for mutate in ('owner','status','rva','schema'):
            report=synthetic_report()
            if mutate=='owner':report['selectors'][0]['candidate']['metadata_type_index']=1
            if mutate=='status':report['selectors'][0]['status']='exact_signature_not_found'
            if mutate=='rva':report['selectors'][0]['candidate']['native_rva']='0x1001'
            if mutate=='schema':report['schema']='unknown'
            with self.assertRaises(ParseError,msg=mutate):facts_for_report(NestedMetadata(own_metadata()),report)

    def test_cli_emits_private_overlay_without_mutating_inputs_or_replacing_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);source=root/'own-source';source.mkdir()
            framework=root/'Framework';metadata=root/'metadata.dat';candidate_map=root/'map.json';base=root/'OwnTests.mm';output=root/'private-audit'
            framework.write_bytes(own_native());metadata.write_bytes(own_metadata());candidate_map.write_text(json.dumps(synthetic_report()))
            base.write_text('namespace {\n}\n\n@interface NativeRuntimeTests : XCTestCase\n@end\nvoid test() {\n    NSDictionary *gateway = exerciseGateway();\n    NSDictionary *proof = @{\n        @"runtimeGateway": gateway,\n    };\n}\n')
            inputs=[framework,metadata,candidate_map,base];before=[p.read_bytes() for p in inputs]
            command=[sys.executable,str(Path(__file__).resolve().parents[1]/'tools/generate_runtime_binding_audit.py')]
            for key,path in [('source-root',source),('base-test',base),('map',candidate_map),('framework',framework),('metadata',metadata),('output',output)]:command+=['--'+key,str(path)]
            result=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            facts=json.loads((output/'binding-audit-facts.local.json').read_text())
            self.assertEqual(facts['expected_method_count'],3)
            overlay=(output/'NativeRuntimeBindingAudit.local.mm').read_text()
            self.assertIn('exerciseAllHarmonyRuntimeBindings(EHRAuditFactsJSON)',overlay)
            self.assertIn('validate_native_method(method,rva,&observed)',overlay)
            self.assertIn('vector_class(classes[dependency]',overlay)
            self.assertNotIn('.replace(\'+\',\'.\')',overlay)
            self.assertEqual([p.read_bytes() for p in inputs],before)
            evidence=(output/'NativeRuntimeBindingAudit.local.mm').read_bytes()
            self.assertEqual(subprocess.run(command,capture_output=True).returncode,2)
            self.assertEqual((output/'NativeRuntimeBindingAudit.local.mm').read_bytes(),evidence)
            bad=root/'bad-pins';command[-1]=str(bad)
            report=synthetic_report();report['input_pins']['framework']['sha256']='0'*64;candidate_map.write_text(json.dumps(report))
            self.assertEqual(subprocess.run(command,capture_output=True).returncode,2)
            self.assertFalse(bad.exists())

    def test_private_output_inside_git_is_rejected(self):
        from generate_runtime_binding_audit import outside_git
        with tempfile.TemporaryDirectory() as temporary:
            repo=Path(temporary);(repo/'.git').mkdir()
            with self.assertRaises(ParseError):outside_git(repo/'private'/'facts')


if __name__=='__main__':unittest.main()
