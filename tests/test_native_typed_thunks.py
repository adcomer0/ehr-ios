"""Original-source metadata/ABI fixtures. Never loads a game or enables hooks."""
import json
import hashlib
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
sys.path.insert(1,str(ROOT/'tools'))
from generate_native_thunk_plans import ABIModel,plan_one
from generate_native_typed_thunks import emit_thunks,emit_sites,ident,runtime_names,ParseError
from map_native_methods import MachO
from patch_native_entries import transform


def fixture_documents():
 names=['System.Void','System.Boolean','Own.Object','System.Int32','Own.Colour','Own.Byte','Own.Mixed','Own.Guid']
 shapes=[{'id':i,'kind':'named','canonical':n}for i,n in enumerate(names)]+[{'id':8,'kind':'byref','canonical':'Own.Guid&','element':7},{'id':9,'kind':'byref','canonical':'System.Boolean&','element':1}]
 def layout(size,align,fields,refs=False):return {'evidence_kind':'observed_public_api','value_size':size,'alignment':align,'contains_references':refs,'blittable':not refs,'fields':[{'name':'m'+str(i),'type':t,'runtime_type_name':t,'value_offset':o,'is_static':False,'is_value_type':t!='Own.Object','field_size':s,'field_alignment':a}for i,(t,o,s,a)in enumerate(fields)]}
 layouts={'Own.Colour':layout(16,4,[('System.Single',i*4,4,4)for i in range(4)]),'Own.Byte':layout(1,1,[('System.Byte',0,1,1)]),'Own.Mixed':layout(144,8,[('Own.Object',0,8,8)]+[('System.Int64',i*8,8,8)for i in range(1,18)],True),'Own.Guid':layout(16,4,[('System.Int32',i*4,4,4)for i in range(4)])}
 definitions={n:{'is_value_type':n!='Own.Object'}for n in names if n.startswith('Own.')};model=ABIModel(shapes,definitions,layouts)
 signatures=[(4,[4,3],3),(6,[6,2,3],3),(5,[5],5),(7,[8],1),(1,[9],0)]
 plans=[];candidates=[]
 for target,(label,params,result)in enumerate(signatures,1):
  selector=f'{target:020x}';source={'instanceType':'Own.Object','returnType':names[result],'parameterTypes':[shapes[i]['canonical']for i in params],'parameterRefKinds':['Out'if i==8 else'Ref'if i==9 else'None'for i in params]}
  method={'declaring_type':2,'parameter_types':params,'return_type':result,'is_static':False,'canonical_signature':'Own fixture '+str(target),'expected_rva':hex(0x1000+target*0x100),'offline_metadata_token':hex(0x06000000+target)}
  plans.append(plan_one({'selectorId':selector,'methodKind':'Normal'},source,method,model,[]));candidates.append({'selectorId':selector,'targetId':target,'nativeRva':method['expected_rva'],'nativeNamespace':'Own','nativeType':'Object','nativeMethod':'M'+str(target),'nativeReturn':names[result],'nativeParameters':[shapes[i]['canonical']for i in params],'isStatic':False})
 report={'schema':'ehr.native-thunk-abi-plans.v1','missing':[],'input_pins':{'framework_uuid':'00000000-0000-0000-0000-000000000001'},'plans':plans,'observed_type_layouts':layouts}
 catalog={'schema':'ehr.native-source-patch-candidates.v1','candidates':candidates}
 return report,catalog,{n:n for n in names}


class GeneratorTests(unittest.TestCase):
 def test_exact_struct_assertions_typed_refs_and_hidden_context(self):
  report,catalog,names=fixture_documents();files=emit_thunks(report,catalog,names)
  self.assertIn('alignas(4)',files['EHRNativeThunkTypes.generated.h']);self.assertIn('==144',files['EHRNativeThunkTypes.generated.h'])
  source=files['EHRNativeTypedThunks.generated.inc'];self.assertIn('bool * a0,const void *methodInfo',source);self.assertIn('EHRNativePatchFinish(outcome)',source)
  self.assertIn('if(!outcome.dispatcher_entered)',source);self.assertNotIn('if(outcome.status)',source)
  self.assertIn('nullptr',files['EHRNativeThunkSites.generated.h']);self.assertEqual(len(json.loads(files['native-thunk-contracts.local.json'])['methods']),5)
 def test_runtime_spelling_must_be_observed_and_unambiguous(self):
  with self.assertRaises(ParseError):runtime_names([{'success':False}])
  first={'success':True,'types':[{'canonical':'Own.Nested','runtimeName':'Own.Nested','success':True}]}
  second={'success':True,'types':[{'canonical':'Own.Nested','runtimeName':'Own+Nested','success':True}]}
  with self.assertRaises(ParseError):runtime_names([first,second])
  report,catalog,names=fixture_documents();names.pop('Own.Mixed')
  with self.assertRaisesRegex(ParseError,'No actual runtime spelling'):emit_thunks(report,catalog,names)
 def test_catalog_mismatch_rejected(self):
  report,catalog,names=fixture_documents();catalog['candidates'][0]['nativeRva']='0x9999'
  with self.assertRaisesRegex(ParseError,'RVA differs'):emit_thunks(report,catalog,names)
 def test_duplicate_target_rejected(self):
  report,catalog,names=fixture_documents();catalog['candidates'][1]['targetId']=1
  with self.assertRaisesRegex(ParseError,'Repeated'):emit_thunks(report,catalog,names)

 @unittest.skipUnless(sys.platform=='darwin'and platform.machine()=='arm64','Requires original-source Mach-O assembly fixture')
 def test_installed_evidence_exact_branch_stub_relocation_and_tamper_rejection(self):
  with tempfile.TemporaryDirectory(prefix='ehr-own-site-')as temporary:
   output=Path(temporary);assembly=output/'own.S';library=output/'own.dylib'
   assembly.write_text('.text\n.globl _own_entry\n.p2align 2\n_own_entry:\nsub sp,sp,#16\nadd w0,w0,#7\nadd sp,sp,#16\nret\n')
   subprocess.run(['xcrun','clang','-target','arm64-apple-macos13.0','-dynamiclib','-Wl,-no_fixup_chains','-Wl,-no_adhoc_codesign','-Wl,-headerpad,0x4000',str(assembly),'-o',str(library)],check=True,capture_output=True,text=True,timeout=60)
   data=library.read_bytes();native=MachO(data);rva=next(s['va']for s in native.symbols()if s['name']=='_own_entry')-native.preferred_base
   selector='00000000000000000001';key='ehr.full.'+selector;symbol='_ehr_full_hook_'+selector
   catalog={'schema':'ehr.native-source-patch-candidates.v1','candidates':[{'selectorId':selector,'targetId':1,'nativeRva':hex(rva)}]}
   method={'declaring_type':'Own.Object','name':'Entry','return_type':'System.Int32','parameters':[{'type':'System.Int32'}],'static':True,'token':'0x6000001','mapping':'codegen_module_token_rid','native_rva':hex(rva)}
   report={'framework_uuid':native.uuid,'methods':[method]};contracts={key:{'declaring_type':'Own.Object','name':'Entry','return':'System.Int32','parameters':['System.Int32'],'static':True,'symbol':symbol}}
   patched,manifest=transform(data,report,[key],'@executable_path/Frameworks/OwnHooks.dylib',contracts)
   header,installed=emit_sites(catalog,manifest,patched);self.assertEqual(len(installed),1);self.assertIn('(&install_'+selector+')',header)
   altered=bytearray(patched);altered[-1]^=1
   with self.assertRaisesRegex(ParseError,'exact unsigned manifest'):emit_sites(catalog,manifest,altered)
   bad=json.loads(json.dumps(manifest));bad['hooks'][0]['handler_symbol']='_wrong'
   with self.assertRaisesRegex(ParseError,'identity differs'):emit_sites(catalog,bad,patched)
   image=__import__('patch_native_entries').Image(patched,allow_instrumented=True);offset=image.va_to_file(image.preferred_base+int(manifest['hooks'][0]['trampoline_rva'],16));altered=bytearray(patched);altered[offset]^=1
   bad=json.loads(json.dumps(manifest));bad['output_sha256']=hashlib.sha256(altered).hexdigest()
   with self.assertRaisesRegex(ParseError,'strict reconstruction'):emit_sites(catalog,bad,altered)

 @unittest.skipUnless(sys.platform=='darwin'and platform.machine()=='arm64','Requires original-source native Apple Silicon fixture')
 def test_production_mapping_bounds_and_missing_evidence_stay_inactive(self):
  with tempfile.TemporaryDirectory(prefix='ehr-own-registry-')as temporary:
   canonical=ROOT
   executable=Path(temporary)/'fixture'
   command=['xcrun','clang++','-target','arm64-apple-macos13.0','-std=c++17','-fobjc-arc','-fobjc-arc-exceptions','-Wall','-Wextra','-Werror','-I',str(ROOT/'native'),'-I',str(canonical/'native'),'-I',str(canonical/'native/include'),'-framework','Foundation','-Wl,-undefined,dynamic_lookup',str(ROOT/'tests/native_thunk_registry_fixture.mm'),'-o',str(executable)]
   subprocess.run(command,check=True,capture_output=True,text=True,timeout=60)
   proof=json.loads(subprocess.run([str(executable)],check=True,capture_output=True,text=True,timeout=15).stdout)
   self.assertTrue(proof['pass']);self.assertEqual(proof['gameApiCalls'],0)

 @unittest.skipUnless(sys.platform=='darwin'and platform.machine()=='arm64','Requires original-source native Apple Silicon fixture')
 def test_emitted_hfa_large_indirect_tiny_value_ref_out_and_failure_policy(self):
  report,catalog,names=fixture_documents();files=emit_thunks(report,catalog,names)
  with tempfile.TemporaryDirectory(prefix='ehr-own-thunk-')as temporary:
   output=Path(temporary)
   for name,text in files.items():(output/name).write_text(text)
   aliases='\n'.join('using '+short+'=ehr_value_'+ident(full)+';'for short,full in(('Colour','Own.Colour'),('Tiny','Own.Byte'),('Mixed','Own.Mixed'),('Guid','Own.Guid')))
   source=r'''
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include "EHRNativeTypedThunks.generated.inc"
ALIASES
static int originalCalls=0,sourceCalls=0,mode=0,permits=0;static bool enabled=false;
static void *self=reinterpret_cast<void *>(0x12340);static const void *context=reinterpret_cast<void *>(0x45670);
static int32_t colour(void *owner,Colour value,int32_t integer,const void *method){++originalCalls;return owner==self&&method==context&&value.f_0==1.5f&&value.f_3==4.5f&&integer==19?71:-1;}
static int32_t mixed(void *owner,Mixed value,void *argument,int32_t integer,const void *method){++originalCalls;return owner==self&&method==context&&value.f_0==self&&value.f_17==317&&argument==self&&integer==23?73:-1;}
static Tiny tiny(void *owner,Tiny value,const void *method){++originalCalls;if(owner!=self||method!=context)throw 1;return Tiny{uint8_t(value.f_0+1)};}
static bool guid(void *owner,Guid *value,const void *method){++originalCalls;if(owner!=self||method!=context)throw 1;*value=Guid{3,5,7,11};return true;}
static void boolean(void *owner,bool *value,const void *method){++originalCalls;if(owner!=self||method!=context)throw 1;*value=!*value;}
uintptr_t EHRNativePatchOriginal(const EHRNativePatchSiteV1 &site){switch(site.target_id){case1:return reinterpret_cast<uintptr_t>(&colour);case2:return reinterpret_cast<uintptr_t>(&mixed);case3:return reinterpret_cast<uintptr_t>(&tiny);case4:return reinterpret_cast<uintptr_t>(&guid);case5:return reinterpret_cast<uintptr_t>(&boolean);}throw 1;}
bool EHRNativePatchShouldDispatch(const EHRNativePatchSiteV1 &){return enabled;}
bool EHRTryConsumeOriginalInvocation(uint64_t,const void *method)noexcept {if(method!=context)return false;if(permits){--permits;return true;}return false;}
EHRRuntimeStatus EHRNativePatchRegisterCompiled(const EHRNativePatchSiteV1 *const *,size_t count){return count==5?EHR_RUNTIME_OK:EHR_RUNTIME_BAD_ARGUMENT;}
EHRNativePatchOutcomeV1 EHRNativePatchInvokePrepared(const EHRNativePatchSiteV1 &site,void *owner,const EHRNativePatchArgumentV1 *args,size_t count,void *result,size_t){
 if(mode==1)return {4,false,0,{}};++sourceCalls;if(owner!=self)throw 1;
 if(site.target_id==1){if(count!=2||reinterpret_cast<Colour *>(args[0].input)->f_2!=3.5f)throw 1;*static_cast<int32_t *>(result)=79;}
 if(site.target_id==2){if(count!=3||reinterpret_cast<Mixed *>(args[0].input)->f_17!=317)throw 1;*static_cast<int32_t *>(result)=83;}
 if(site.target_id==3)*static_cast<Tiny *>(result)=Tiny{211};
 if(site.target_id==4){*static_cast<Guid *>(args[0].output)=Guid{13,17,19,23};*static_cast<bool *>(result)=true;}
 if(site.target_id==5)*static_cast<bool *>(args[0].output)=true;
 return {mode==2?6:0,true,0,{2,32,1,1,0,0,0,0}};
}
void EHRNativePatchFinish(EHRNativePatchOutcomeV1 value){if(value.status)throw std::runtime_error("contained own callback failure");}
int main(){
 if(EHRNativeGeneratedRegisterCompiled()!=EHR_RUNTIME_OK)return 1;Colour c{1.5f,2.5f,3.5f,4.5f};Mixed m{};m.f_0=self;m.f_17=317;Guid g{};bool b=false;Tiny t{9};
 if(ehr_full_hook_00000000000000000001(self,c,19,context)!=71||ehr_full_hook_00000000000000000002(self,m,self,23,context)!=73||ehr_full_hook_00000000000000000003(self,t,context).f_0!=10||!ehr_full_hook_00000000000000000004(self,&g,context)||g.f_3!=11)return 2;
 ehr_full_hook_00000000000000000005(self,&b,context);if(!b||originalCalls!=5)return 3;enabled=true;
 if(ehr_full_hook_00000000000000000001(self,c,19,context)!=79||ehr_full_hook_00000000000000000002(self,m,self,23,context)!=83||ehr_full_hook_00000000000000000003(self,t,context).f_0!=211||!ehr_full_hook_00000000000000000004(self,&g,context)||g.f_3!=23)return 4;
 b=false;ehr_full_hook_00000000000000000005(self,&b,context);if(!b||sourceCalls!=5||originalCalls!=5)return 5;
 mode=1;if(ehr_full_hook_00000000000000000001(self,c,19,context)!=71||originalCalls!=6)return 6;mode=0;permits=1;if(ehr_full_hook_00000000000000000001(self,c,19,context)!=71||originalCalls!=7||permits)return 7;
 mode=2;b=false;try{ehr_full_hook_00000000000000000005(self,&b,context);return 8;}catch(const std::runtime_error &){}if(!b||originalCalls!=7)return 9;
 printf("{\"pass\":true,\"sourceCalls\":%d,\"originalCalls\":%d,\"functionAddress\":\"%p\",\"scope\":\"own native emitted thunk ABI only\"}\n",sourceCalls,originalCalls,reinterpret_cast<void *>(&colour));
}
'''.replace('ALIASES',aliases)
   for i in range(1,6):source=source.replace('case'+str(i)+':','case '+str(i)+':')
   (output/'fixture.cpp').write_text(source)
   canonical=ROOT
   command=['xcrun','clang++','-target','arm64-apple-macos13.0','-std=c++17','-Wall','-Wextra','-Werror','-I',str(ROOT/'native'),'-I',str(canonical/'native'),'-I',str(canonical/'native/include'),'-I',str(output),str(output/'fixture.cpp'),'-o',str(output/'fixture')]
   subprocess.run(command,check=True,capture_output=True,text=True,timeout=60)
   runs=[json.loads(subprocess.run([str(output/'fixture')],check=True,capture_output=True,text=True,timeout=15).stdout)for _ in range(2)]
   self.assertTrue(all(r['pass']for r in runs));self.assertNotEqual(runs[0]['functionAddress'],runs[1]['functionAddress'])


if __name__=='__main__':unittest.main()
