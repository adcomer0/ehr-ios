#import "EHRManagedSourceComponentProbe.h"
#import "EHRSourceComponents.h"
#include "EHRRuntimeReflection.h"
#include <vector>
#if EHR_HAS_MANAGED_RULES
extern "C" int32_t ehr_generated_bind_source_components(const EHRSourceComponentNativeV1*,size_t,EHRSourceComponentCallbacksV1*,size_t);
struct SourceProof{uint32_t version,bytes;int32_t status,pass,active,constructors,awake,updates,destroyed,ping,initializers,same,collected,dynamic;};
static_assert(sizeof(SourceProof)==56);
extern "C" int32_t ehr_generated_source_component_proof(uint64_t,int32_t,SourceProof*,size_t);
extern "C" int32_t ehr_generated_source_component_facade_create(uint64_t,uint64_t*,uint64_t*,uint32_t*);
extern "C" int32_t ehr_generated_source_component_scope_proof(int32_t*,size_t);
extern "C" int32_t ehr_generated_source_tombstone_proof(int32_t*,size_t);
// Actual engine-only add, no source entry is fabricated or manually dispatched.
extern "C" EHRRuntimeStatus ehr_source_component_add(uint32_t,EHRRuntimeToken,uint64_t*,EHRRuntimeToken*,EHRRuntimeToken*);
namespace ehr_source_component_probe {
struct State{NSMutableDictionary *report=nil;NSTimer *timer=nil;std::vector<EHRRuntimeToken> roots;EHRRuntimeToken owner=0,destroy=0,probe=0;CFAbsoluteTime deadline=0;bool running=false,destroyRequested=false;};
State &state(){static State *s=new State;return *s;}
void keep(EHRRuntimeToken token){if(token)state().roots.push_back(token);}
EHRRuntimeStatus invoke(EHRRuntimeToken method,EHRRuntimeToken instance,const EHRRuntimeArgument *args,size_t count,EHRRuntimeToken *result){EHRRuntimeToken exception=0;auto status=ehr_runtime_invoke(method,instance,args,count,result,&exception);keep(*result);keep(exception);return status;}
NSDictionary *proof(const SourceProof &v){return @{@"status":@(v.status),@"pass":@(v.pass),@"activeSourceStates":@(v.active),@"constructors":@(v.constructors),@"awake":@(v.awake),@"updates":@(v.updates),@"destroyed":@(v.destroyed),@"ping":@(v.ping),@"originalFieldInitializer":@(v.initializers),@"sameSourceIdentity":@(v.same),@"sourceCollected":@(v.collected),@"dynamicCodeFlags":@(v.dynamic)};}
EHRRuntimeStatus destroy(){auto&s=state();if(!s.owner||s.destroyRequested)return EHR_RUNTIME_OK;EHRRuntimeToken result=0;const EHRRuntimeArgument arg{EHR_RUNTIME_REFERENCE,0,s.owner,nullptr,0};auto status=invoke(s.destroy,0,&arg,1,&result);if(status==EHR_RUNTIME_OK)s.destroyRequested=true;return status;}
void finish(NSString *message,bool success,EHRRuntimeStatus status){auto&s=state();[s.timer invalidate];s.timer=nil;
 const auto stopped=destroy();if(!success)EHRSourceComponentsCloseAll();bool released=stopped==EHR_RUNTIME_OK;
 if(released){for(auto token:s.roots)released=ehr_runtime_object_release(token)==EHR_RUNTIME_OK&&released;s.roots.clear();}
 NSDictionary *bindings=EHRSourceComponentsCopyStatus();s.report[@"complete"]=@YES;s.report[@"success"]=@(success&&released&&[bindings[@"activeNativeRegistrations"] unsignedIntValue]==0&&[bindings[@"managedStateCount"] unsignedIntValue]==0);
 s.report[@"state"]=message;s.report[@"status"]=@(status);s.report[@"rootCleanupSucceeded"]=@(released);s.report[@"remainingOwnedRoots"]=@(s.roots.size());s.report[@"bridge"]=bindings;s.running=false;
}
void tick(){auto&s=state();if(!s.running)return;
 if(CFAbsoluteTimeGetCurrent()>s.deadline){finish(@"unity_source_lifecycle_timed_out",false,EHR_RUNTIME_LIMIT);return;}
 SourceProof value{};
 if(!s.destroyRequested){auto status=ehr_generated_source_component_proof(s.probe,0,&value,sizeof(value));s.report[@"liveSource"]=proof(value);
  if(status!=0){finish(@"source_state_identity_or_initializer_failed",false,static_cast<EHRRuntimeStatus>(status));return;}
  if(value.updates>=2){auto stopped=destroy();s.report[@"actualUnityDestroyRequested"]=@(stopped==EHR_RUNTIME_OK);if(stopped!=EHR_RUNTIME_OK)finish(@"destroy_failed",false,stopped);}
 }else{NSDictionary *bindings=EHRSourceComponentsCopyStatus();if([bindings[@"activeNativeRegistrations"] unsignedIntValue])return;
  int32_t tombstone[3]{};const auto tombstoneStatus=ehr_generated_source_tombstone_proof(tombstone,3);
  s.report[@"destroyedSourceTokenNull"]=@(tombstone[0]);s.report[@"destroyedSourceUnityBoolFalse"]=@(tombstone[1]);s.report[@"destroyedSourceClrFieldsPreserved"]=@(tombstone[2]);
  auto status=ehr_generated_source_component_proof(0,1,&value,sizeof(value));s.report[@"destroyedSource"]=proof(value);if(status==0&&tombstoneStatus!=0)status=tombstoneStatus;
  int32_t scope[2]{};const auto scopeStatus=ehr_generated_source_component_scope_proof(scope,2);s.report[@"sourceScopeUnsubscribeCount"]=@(scope[0]);s.report[@"sourceScopeCloseCount"]=@(scope[1]);
  if(status==0&&scopeStatus!=0)status=scopeStatus;
  finish(@"actual_unity_source_lifecycle_complete",status==0,static_cast<EHRRuntimeStatus>(status));}
}
}
#endif
NSDictionary *EHRManagedSourceComponentProbeBegin(void){
#if EHR_HAS_MANAGED_RULES
 using namespace ehr_source_component_probe;if(!NSThread.isMainThread)return @{@"success":@NO,@"complete":@YES,@"status":@2};auto&s=state();if(s.report)return EHRManagedSourceComponentProbeCopyStatus();
 s.report=[@{@"success":@NO,@"complete":@NO,@"state":@"starting",@"fullMainLoadInvoked":@NO,@"allSevenSourceComponentsAvailable":@NO,@"actualSourceComponent":@"EHR.Coroutines",@"ownProbeComponent":@"EHR.NativeProbes.StaticLifecycleProbe",@"manualUnityMessageDispatchPerformed":@NO} mutableCopy];
 @try{try{s.roots.reserve(32);NSDictionary *bound=EHRSourceComponentsBind(reinterpret_cast<void *>(&ehr_generated_bind_source_components));s.report[@"binding"]=bound;
  if(![bound[@"success"] boolValue]){finish(@"source_component_binding_failed",false,EHR_RUNTIME_NOT_READY);return s.report;}
  EHRRuntimeToken game=0,unity=0,exception=0;auto status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","GameObject",&game);
  if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","Object",&unity);
  const char *params[]={"UnityEngine.Object"};if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(unity,"Destroy",params,1,"System.Void",1,&s.destroy);
  if(status==EHR_RUNTIME_OK)status=ehr_runtime_construct(game,nullptr,0,&s.owner,&exception);keep(s.owner);keep(exception);
  EHRRuntimeToken coroutines=0;uint32_t facadeFlags=0;
  if(status==EHR_RUNTIME_OK)status=static_cast<EHRRuntimeStatus>(ehr_generated_source_component_facade_create(s.owner,&coroutines,&s.probe,&facadeFlags));keep(coroutines);keep(s.probe);
  s.report[@"sourceFacadeCreateFlags"]=@(facadeFlags);s.report[@"sourceGenericAddAndGetAndTryCastIdentity"]=@(status==EHR_RUNTIME_OK&&facadeFlags==15);
  EHRRuntimeToken probeClass=0,ping=0,result=0;if(status==EHR_RUNTIME_OK)status=ehr_runtime_object_class(s.probe,&probeClass);
  EHRRuntimeToken type=0,getComponent=0;exception=0;
  if(status==EHR_RUNTIME_OK)status=ehr_runtime_class_type_object(probeClass,&type);keep(type);
  const char *getParams[]={"System.Type"};if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(game,"GetComponent",getParams,1,"UnityEngine.Component",0,&getComponent);
  const EHRRuntimeArgument getArg{EHR_RUNTIME_REFERENCE,0,type,nullptr,0};if(status==EHR_RUNTIME_OK)status=invoke(getComponent,s.owner,&getArg,1,&result);
  int32_t same=0;if(status==EHR_RUNTIME_OK)status=ehr_runtime_object_same(s.probe,result,&same);
  if(status==EHR_RUNTIME_OK&&same!=1)status=EHR_RUNTIME_TYPE_MISMATCH;
  if(status==EHR_RUNTIME_OK)s.probe=result;s.report[@"actualNativeGetComponentIdentity"]=@(status==EHR_RUNTIME_OK);
  if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(probeClass,"Ping",nullptr,0,"System.Void",0,&ping);
  if(status==EHR_RUNTIME_OK)status=invoke(ping,s.probe,nullptr,0,&result);
  if(status!=EHR_RUNTIME_OK){finish(@"actual_source_component_add_failed",false,status);return s.report;}
  SourceProof value{};const auto sampled=ehr_generated_source_component_proof(s.probe,0,&value,sizeof(value));s.report[@"initialSource"]=proof(value);
  if(sampled!=0){finish(@"source_constructor_or_awake_failed",false,static_cast<EHRRuntimeStatus>(sampled));return s.report;}
  s.running=true;s.deadline=CFAbsoluteTimeGetCurrent()+12;s.report[@"state"]=@"waiting_for_real_unity_updates";
  s.timer=[NSTimer scheduledTimerWithTimeInterval:0.025 repeats:YES block:^(__unused NSTimer*t){tick();}];return EHRManagedSourceComponentProbeCopyStatus();
 }catch(...){finish(@"contained_cpp_exception",false,EHR_RUNTIME_LIMIT);return s.report;}}@catch(__unused NSException*e){finish(@"contained_objc_exception",false,EHR_RUNTIME_UNSUPPORTED);return s.report;}
#else
 return @{@"success":@NO,@"complete":@YES,@"state":@"managed_rules_not_built"};
#endif
}
NSDictionary *EHRManagedSourceComponentProbeCopyStatus(void){
#if EHR_HAS_MANAGED_RULES
 if(!NSThread.isMainThread)return @{@"success":@NO,@"complete":@YES,@"status":@2};return ehr_source_component_probe::state().report?[ehr_source_component_probe::state().report copy]:@{@"success":@NO,@"complete":@NO,@"state":@"not_started"};
#else
 return @{@"success":@NO,@"complete":@YES,@"state":@"managed_rules_not_built"};
#endif
}
NSDictionary *EHRManagedSourceComponentProbeCancel(void){
#if EHR_HAS_MANAGED_RULES
 if(!NSThread.isMainThread)return @{@"success":@NO,@"complete":@YES,@"status":@2};if(ehr_source_component_probe::state().running)ehr_source_component_probe::finish(@"cancelled",false,EHR_RUNTIME_BAD_ARGUMENT);return EHRManagedSourceComponentProbeCopyStatus();
#else
 return @{@"success":@NO,@"complete":@YES,@"state":@"managed_rules_not_built"};
#endif
}
