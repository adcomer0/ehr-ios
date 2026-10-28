from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from auth_retry_hook_inputs import FACTS, TARGET, SYMBOL, SOURCE_SHA, METADATA_SHA, UUID, merge_auth_retry_inputs, binding_header

class GuardInputTests(unittest.TestCase):
    def setUp(self):
        self.base={'metadata_version':31,'framework_uuid':UUID,'preferred_image_base':'0x0',
            'input_pins':{'framework':{'size':100,'sha256':SOURCE_SHA},'metadata':{'size':10,'sha256':METADATA_SHA}},'methods':[]}
        self.report=deepcopy(self.base);self.report.update(schema='ehr.harmony-native-target-map.v1',selectors=[])
        for owner,name,rva,token in FACTS:
            self.report['selectors'].append({'status':'exact_metadata_native_candidate','candidate':{'declaring_type':owner,'name':name,
                'native_rva':rva,'metadata_token':token,'owning_image':'Assembly-CSharp.dll','return_type':'System.Void','parameter_types':[],
                'static':False,'generic':False,'abstract':False,'shared_entry':False,'registered_module_entry_count':1,'registered_generic_entry_count':0}})
        self.contracts={'schema':'ehr.native-hook-contracts.v1','methods':{}}

    def test_only_one_separate_entry_no_source_targets_or_failure_hook(self):
        before=deepcopy((self.base,self.report,self.contracts));merged,contracts,names=merge_auth_retry_inputs(self.base,self.report,self.contracts)
        self.assertEqual((self.base,self.report,self.contracts),before);self.assertEqual(names,[TARGET]);self.assertEqual(len(merged['methods']),1)
        self.assertEqual(contracts['methods'][TARGET]['symbol'],SYMBOL);self.assertNotIn('targetId',json.dumps(merged))
        with self.assertRaises(ValueError):merge_auth_retry_inputs(merged,self.report,contracts)

    def test_wrong_failure_or_retry_evidence_rejects_before_patch(self):
        for index,key,bad in ((0,'native_rva','0x400'),(1,'metadata_token','0x6000001'),(1,'static',True),(0,'shared_entry',True),(1,'return_type','System.Boolean')):
            report=deepcopy(self.report);report['selectors'][index]['candidate'][key]=bad
            with self.subTest(index=index,key=key),self.assertRaises(ValueError):merge_auth_retry_inputs(self.base,report,self.contracts)
        report=deepcopy(self.report);report['input_pins']['framework']['sha256']='foreign'
        with self.assertRaises(ValueError):merge_auth_retry_inputs(self.base,report,self.contracts)

    def test_generated_binding_matches_exact_installed_native_contract(self):
        site={'method':TARGET,'original_rva':FACTS[0][2],'metadata_token':FACTS[0][3],'symbol':SYMBOL,
            'signature':{'return':'System.Void','parameters':[],'static':False},'trampoline_rva':'0x4000'}
        manifest={'framework_uuid':UUID,'source_sha256':SOURCE_SHA,'hooks':[site]}
        self.assertIn('EHRAuthRetryTrampolineRVA=0x4000',binding_header(manifest))
        site['signature']['static']=True
        with self.assertRaises(ValueError):binding_header(manifest)

@unittest.skipUnless(sys.platform=='darwin','Requires Apple clang/Foundation')
class GuardTests(unittest.TestCase):
    def test_own_exact_metadata_gate_nested_context_failures_and_root_cleanup(self):
        with tempfile.TemporaryDirectory(prefix='ehr-own-auth-retry-') as temp:
            folder=Path(temp);exe=folder/'Fixture'
            (folder/'EHRAuthRetryBinding.generated.h').write_text('#pragma once\n#include <stdint.h>\nextern uintptr_t EHRAuthRetryTrampolineRVA;\n')
            compile=subprocess.run(['xcrun','clang++','-std=c++17','-fobjc-arc','-fobjc-arc-exceptions','-fblocks',
                '-Wall','-Wextra','-Werror','-framework','Foundation','-I',str(ROOT/'native'),'-I',str(folder),
                str(ROOT/'tests/AuthRetryGuardFixture.mm'),'-o',str(exe)],capture_output=True,text=True,timeout=60)
            self.assertEqual(compile.returncode,0,compile.stderr)
            result=subprocess.run([str(exe)],capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            proof=json.loads(result.stdout);self.assertTrue(proof['pass']);self.assertGreaterEqual(proof['checks'],65)
            self.assertEqual(proof['failureEntries'],2);self.assertEqual(proof['originalForwards'],13)
            self.assertEqual(proof['liveRoots'],0);self.assertEqual(proof['gameAccountCalls'],0);self.assertEqual(proof['authRequests'],0)

    def test_observer_forwards_exact_native_frame_and_scopes_only_known_normal_7000(self):
        with tempfile.TemporaryDirectory(prefix='ehr-own-auth-observer-') as temp:
            folder=Path(temp);exe=folder/'Fixture'
            (folder/'EHREOSLoginBinding.generated.h').write_text('#pragma once\n#include <stdint.h>\nextern uintptr_t EHREOSPlatformLoginTrampolineRVA,EHREOSPlatformSilentLoginTrampolineRVA;\n')
            compile=subprocess.run(['xcrun','clang++','-std=c++17','-fobjc-arc','-fobjc-arc-exceptions','-fblocks',
                '-Wall','-Wextra','-Werror','-framework','Foundation','-I',str(ROOT/'native'),'-I',str(folder),
                str(ROOT/'tests/AuthRetryObserverFixture.mm'),'-o',str(exe)],capture_output=True,text=True,timeout=60)
            self.assertEqual(compile.returncode,0,compile.stderr)
            result=subprocess.run([str(exe)],capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            proof=json.loads(result.stdout);self.assertTrue(proof['pass']);self.assertGreaterEqual(proof['checks'],40)
            self.assertEqual(proof['normalForwards'],5);self.assertEqual(proof['silentForwards'],1)
            self.assertEqual(proof['authRequests'],0);self.assertEqual(proof['gameAccountCalls'],0)

if __name__=='__main__':unittest.main()
