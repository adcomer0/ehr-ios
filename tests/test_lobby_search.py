from pathlib import Path
import importlib.util
import copy
import json
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import lobby_search_hook_inputs as M


def report():
 r={'metadata_version':31,'framework_uuid':M.UUID,'preferred_image_base':'0x0','input_pins':{key:{'sha256':sha,'size':123} for key,sha in [('framework',M.SOURCE_SHA),('metadata',M.METADATA_SHA)]},'selectors':[], 'search_callsite':{'caller':'HttpMatchmakerManager+<CoRequestGameListFiltered>d__20.MoveNext','callsite_rva':hex(M.CALLSITE),'return_rva':hex(M.RETURN),'target_rva':M.HELPER[6],'direct_call_verified':True}}
 for s,f in zip(M.selectors()['selectors'],M.METHODS):
  c={'declaring_type':f[0],'name':f[1],'owning_image':f[2],'return_type':f[3],'parameter_types':list(f[4]),'static':f[5],'native_rva':f[6],'metadata_token':f[7],'association':'offline_codegen_module_token_rid_candidate','runtime_association_verified':False,'generic':False,'abstract':False,'shared_entry':False,'registered_module_entry_count':1,'registered_generic_entry_count':0,'first_instruction_relocation':{'status':'supported_at_report_probe_slot'}}
  r['selectors'].append({'selector_id':s['selectorId'],'selector':s,'status':'exact_metadata_native_candidate','candidate':c})
 return r


def manifest():
 return {'framework_uuid':M.UUID,'source_sha256':M.SOURCE_SHA,'hooks':[{'method':M.TARGET,'method_rva':M.HELPER[6],'original_rva':M.HELPER[6],'metadata_token':M.HELPER[7],'symbol':M.SYMBOL,'signature':{'return':M.HELPER[3],'parameters':list(M.HELPER[4]),'static':True},'trampoline_rva':'0x7000000'}]}


class LobbySearchInputTests(unittest.TestCase):
 def test_exact_static_hook_and_header_keep_hosting_and_other_entries(self):
  r=report();base=copy.deepcopy(r);base['methods']=[{'declaring_type':'Owned','name':'Other','native_rva':'0x1000'}];contracts={'schema':'ehr.native-hook-contracts.v1','methods':{}}
  merged,c,names=M.merge_lobby_search_inputs(base,r,contracts)
  self.assertEqual(merged['methods'][0],base['methods'][0]);self.assertEqual(len(merged['methods']),2);self.assertTrue(merged['methods'][-1]['static']);self.assertEqual(names,[M.TARGET]);self.assertEqual(c['methods'][M.TARGET]['symbol'],M.SYMBOL)
  h=M.binding_header(manifest(),r);self.assertIn('EHRLobbySearchCallerReturnRVA = 0x1bfdcd8',h);self.assertNotIn('HostGame',h);self.assertNotIn('ModRegistrationGuidString =',h)
 def test_changed_identity_callsite_signatures_or_aliases_rejected(self):
  r=report()
  for key,value in [('framework_uuid','other'),('metadata_version',30),('metadata_version',31.0),('input_pins',None),('search_callsite',None),('search_callsite',{}),('search_callsite',{**r['search_callsite'],'direct_call_verified':1})]:
   bad=copy.deepcopy(r);bad[key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):M.validate_report(r,bad)
  for key,value in [('static',False),('native_rva','0x100'),('metadata_token','0x6000001'),('shared_entry',True),('parameter_types',[]),('return_type','System.Int32'),('registered_module_entry_count',True)]:
   bad=copy.deepcopy(r);bad['selectors'][0]['candidate'][key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):M.validate_report(r,bad)
  for key,value in [('isStatic',1),('parameterTypes',None)]:
   bad=copy.deepcopy(r);bad['selectors'][0]['selector'][key]=value
   with self.subTest(selector=key),self.assertRaises(ValueError):M.validate_report(r,bad)
  bad=copy.deepcopy(r);bad['selectors'][0]['candidate']['first_instruction_relocation']=None
  with self.assertRaises(ValueError):M.validate_report(r,bad)
  for variant in ('missing','signature','null_signature','numeric_static','alias','nontext_trampoline','wide_trampoline'):
   bad=manifest()
   if variant=='missing':bad['hooks']=[]
   elif variant=='signature':bad['hooks'][0]['signature']['static']=False
   elif variant=='null_signature':bad['hooks'][0]['signature']=None
   elif variant=='numeric_static':bad['hooks'][0]['signature']['static']=1
   elif variant=='nontext_trampoline':bad['hooks'][0]['trampoline_rva']=0x7000000
   elif variant=='wide_trampoline':bad['hooks'][0]['trampoline_rva']='0x10000000000000000'
   else:bad['hooks'].append({'method':'Other','symbol':'other','method_rva':M.HELPER[6]})
   with self.subTest(variant=variant),self.assertRaises(ValueError):M.binding_header(bad,r)


@unittest.skipUnless(sys.platform=='darwin','Requires Apple Foundation/clang')
class LobbySearchNativeTests(unittest.TestCase):
 def test_exact_native_module_with_owned_runtime_objects(self):
  with tempfile.TemporaryDirectory(prefix='ehr-own-search-') as d:
   root=Path(d);header=M.binding_header(manifest(),report()).replace('EHRLobbySearchTrampolineRVA = 0x7000000','EHRLobbySearchTrampolineRVA = reinterpret_cast<uintptr_t>(&OwnedOriginalHelper)');(root/'EHRLobbySearchBinding.generated.h').write_text(header)
   binary=root/'fixture';built=subprocess.run(['xcrun','clang++','-fobjc-arc','-fblocks','-std=c++20','-Wall','-Wextra','-Werror','-framework','Foundation','-I',str(root),'-I',str(ROOT/'native'),str(ROOT/'tests/LobbySearchFixture.mm'),'-o',str(binary)],capture_output=True,text=True,timeout=60)
   self.assertEqual(built.returncode,0,built.stderr)
   ran=subprocess.run([str(binary)],capture_output=True,text=True,timeout=20);self.assertEqual(ran.returncode,0,ran.stdout+ran.stderr);proof=json.loads(ran.stdout);self.assertTrue(proof['success']);self.assertGreaterEqual(proof['checks'],70)
   for key in ('actualGameRequests','accountActions','realCredentialReads','globalRegistrationWrites'):self.assertEqual(proof[key],0)
 def test_production_module_compiles_against_ios_sdk(self):
  with tempfile.TemporaryDirectory(prefix='ehr-own-search-syntax-') as d:
   root=Path(d);(root/'EHRLobbySearchBinding.generated.h').write_text(M.binding_header(manifest(),report()))
   sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip();ran=subprocess.run(['xcrun','clang++','-fsyntax-only','-fobjc-arc','-fblocks','-std=c++20','-Wall','-Wextra','-Werror','-target','arm64-apple-ios17.0','-isysroot',sdk,'-I',str(root),'-I',str(ROOT/'native'),str(ROOT/'native/EHRLobbySearch.mm')],capture_output=True,text=True,timeout=60);self.assertEqual(ran.returncode,0,ran.stderr)
