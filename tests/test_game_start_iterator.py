"""Owned synthetic fixtures only; no game, device, signing or account access."""
from copy import deepcopy
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import game_start_iterator_hook_inputs as rules
from test_patch_native_entries import synthetic_image
from patch_native_entries import transform
spec=importlib.util.spec_from_file_location('own_game_start_builder',ROOT/'tools/build_game_probe.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)

class GameStartIteratorTests(unittest.TestCase):
    def setUp(self):
        self.base={'metadata_version':31,'framework_uuid':rules.UUID,'preferred_image_base':'0x0','input_pins':{
            'framework':{'sha256':rules.SOURCE_SHA,'size':100},'metadata':{'sha256':rules.METADATA_SHA,'size':10}},'methods':[]}
        self.report=deepcopy(self.base);self.report.update(schema='ehr.harmony-native-target-map.v1',selectors=[],inline_factory_proof=deepcopy(rules.INLINE_PROOF))
        for owner,name,returns,rva,token in rules.FACTS:
            self.report['selectors'].append({'status':'exact_metadata_native_candidate','candidate':{
                'declaring_type':owner,'name':name,'owning_image':'Assembly-CSharp.dll','return_type':returns,'parameter_types':[],
                'native_rva':rva,'metadata_token':token,'static':False,'generic':False,'abstract':False,'shared_entry':False,
                'registered_module_entry_count':1,'registered_generic_entry_count':0}})
        self.contracts={'schema':'ehr.native-hook-contracts.v1','methods':{'own.existing':{'static':True}}}
    def test_exact_merge_retains_inputs_and_existing_contracts(self):
        before=deepcopy((self.base,self.report,self.contracts));merged,contracts,names=rules.merge_game_start_inputs(*before)
        self.assertEqual(before,(self.base,self.report,self.contracts));self.assertEqual(names,[rules.TARGET]);self.assertEqual(len(merged['methods']),1)
        self.assertEqual(contracts['methods']['own.existing'],{'static':True});self.assertEqual(contracts['methods'][rules.TARGET]['symbol'],rules.SYMBOL)
    def test_wrong_game_shared_signature_token_and_inlining_evidence_reject(self):
        for field,value in [('static',True),('shared_entry',True),('generic',True),('abstract',True),('native_rva','0x100'),('metadata_token','0x6000001'),('registered_module_entry_count',2),('return_type','System.Int32')]:
            bad=deepcopy(self.report);bad['selectors'][0]['candidate'][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):rules.merge_game_start_inputs(self.base,bad,self.contracts)
        bad=deepcopy(self.report);bad['inline_factory_proof']['parentYieldStates']=[5]
        with self.assertRaises(ValueError):rules.merge_game_start_inputs(self.base,bad,self.contracts)
        bad=deepcopy(self.base);bad['input_pins']['framework']['sha256']='0'*64
        with self.assertRaises(ValueError):rules.merge_game_start_inputs(bad,self.report,self.contracts)
    def test_duplicate_or_entry_alias_reject(self):
        for row in ({'declaring_type':rules.OWNER,'name':'MoveNext'},{'native_rva':rules.FACTS[0][3]}):
            bad=deepcopy(self.base);bad['methods']=[row]
            with self.assertRaises(ValueError):rules.merge_game_start_inputs(bad,self.report,self.contracts)
    def test_exact_installed_header_and_corruption_reject(self):
        original,report=synthetic_image();owner,name=rules.TARGET.rsplit('.',1)
        report['methods']=[{'declaring_type':owner,'name':name,'return_type':'System.Boolean','parameters':[],'static':False,'native_rva':'0x1000','token':'0x6000001','mapping':'codegen_module_token_rid'}]
        contract={rules.TARGET:{'declaring_type':owner,'name':name,'return':'System.Boolean','parameters':[],'static':False,'symbol':rules.SYMBOL}}
        data,manifest=transform(original,report,[rules.TARGET],'@executable_path/Frameworks/Own.dylib',contract)
        manifest.update(source_sha256=hashlib.sha256(original).hexdigest(),output_sha256=hashlib.sha256(data).hexdigest())
        ownfacts=((rules.OWNER,'MoveNext','System.Boolean','0x1000','0x6000001'),rules.FACTS[1])
        with patch.object(rules,'UUID',report['framework_uuid']),patch.object(rules,'SOURCE_SHA',manifest['source_sha256']),patch.object(rules,'FACTS',ownfacts):
            text=rules.binding_header(manifest,data);self.assertIn('EHRGameStartInstall',text);self.assertIn('EHRGameStartSite',text)
            for field,value in [('method_rva','0x1020'),('metadata_token','0x6000002'),('symbol','_foreign'),('entry_branch','0x14000000')]:
                bad=deepcopy(manifest);bad['hooks'][0][field]=value
                with self.subTest(field=field),self.assertRaises(ValueError):rules.binding_header(bad,data)
            bad=bytearray(data);bad[0x1000]^=1
            with self.assertRaises(ValueError):rules.binding_header(manifest,bytes(bad))
    def test_optional_builder_rejects_nonfull_before_reading_inputs(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp);args=SimpleNamespace(team_id='ABCDEFGHIJ',bundle_id='org.example.ehrfixture',team_name=None,game_app=p,output=p/'new',full_native_catalog=None,game_start_iterator_map=p/'map.json')
            with patch.object(builder,'inspect_path') as inspect,self.assertRaisesRegex(ValueError,'requires the full source profile'):builder.build(args)
            inspect.assert_not_called();self.assertFalse((p/'new').exists())
    @unittest.skipUnless(sys.platform=='darwin','Apple clang/Foundation required')
    def test_actual_adapter_source_against_owned_metadata_and_roots(self):
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp);exe=folder/'Fixture'
            (folder/'EHRGameStartBinding.generated.h').write_text('#pragma once\n#include "EHRNativePatchThunks.h"\nstatic const EHRNativePatchSiteV1 EHRGameStartSite={};\nstatic const uint64_t EHRGameStartParentRVA=0x1bd31e0;\nstatic const uint64_t EHRGameStartFactoryRVA=0x1bcd480;\n')
            args=['xcrun','clang++','-std=c++17','-Wall','-Wextra','-Werror','-fobjc-arc','-fobjc-arc-exceptions','-fblocks','-framework','Foundation','-I',str(ROOT/'native'),'-I',str(ROOT/'native/include'),'-I',str(folder),str(ROOT/'tests/GameStartIteratorFixture.mm'),'-o',str(exe)]
            result=subprocess.run(args,capture_output=True,text=True,timeout=60);self.assertEqual(result.returncode,0,result.stderr)
            proof=json.loads(subprocess.check_output([str(exe)],text=True,timeout=10))
            self.assertTrue(proof['pass']);self.assertGreaterEqual(proof['checks'],48);self.assertEqual(proof['rootCount'],0)
            nested=proof['fabricatedIteratorSelfTest'];self.assertTrue(nested['success']);self.assertEqual(nested['checks'],46)
            self.assertTrue(nested['fixtureNullOwner']);self.assertFalse(nested['realHostFactoryInvoked']);self.assertFalse(nested['originalMoveNextInvoked'])
if __name__=='__main__':unittest.main()
