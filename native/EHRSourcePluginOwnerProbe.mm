#import "EHRSourcePluginOwnerProbe.h"
#import "EHRSourceComponents.h"
#include "EHRRuntimeGateway.h"
extern "C" EHRRuntimeStatus ehr_source_component_add(uint32_t,EHRRuntimeToken,uint64_t*,EHRRuntimeToken*,EHRRuntimeToken*);
namespace ehr_source_owner_probe {
struct State{NSMutableDictionary *report=nil;NSTimer *timer=nil;EHRRuntimeToken component=0,boolMethod=0;CFAbsoluteTime deadline=0;bool running=false;};
State&state(){static State*s=new State;return *s;}
void finish(NSString *message,bool success,EHRRuntimeStatus status){auto&s=state();[s.timer invalidate];s.timer=nil;if(!success)EHRSourceComponentsCloseAll();
 bool released=!s.component||ehr_runtime_object_release(s.component)==EHR_RUNTIME_OK;if(released)s.component=0;
 auto end=EHRSourceComponentsCopyStatus();s.report[@"bridgeAfter"]=end;s.report[@"state"]=message;s.report[@"status"]=@(status);s.report[@"complete"]=@YES;s.report[@"ownedComponentRootReleased"]=@(released);
 s.report[@"success"]=@(success&&released&&![end[@"pluginOwnerRooted"] boolValue]&&[end[@"managedStateCount"] intValue]==0&&[end[@"activeNativeRegistrations"] intValue]==0);s.running=false;
}
void tick(){auto&s=state();if(!s.running)return;if(CFAbsoluteTimeGetCurrent()>s.deadline){finish(@"plugin_owner_destroy_timed_out",false,EHR_RUNTIME_LIMIT);return;}
 EHRRuntimeToken result=0,exception=0;const EHRRuntimeArgument arg{EHR_RUNTIME_REFERENCE,0,s.component,nullptr,0};auto status=ehr_runtime_invoke(s.boolMethod,0,&arg,1,&result,&exception);uint8_t alive=1;size_t bytes=0;
 if(status==EHR_RUNTIME_OK)status=ehr_runtime_copy_value(result,&alive,sizeof(alive),&bytes);if(result)ehr_runtime_object_release(result);if(exception)ehr_runtime_object_release(exception);
 if(status!=EHR_RUNTIME_OK||bytes!=1){finish(@"native_destroyed_state_query_failed",false,status);return;}
 if(!alive){s.report[@"actualUnityComponentDestroyed"]=@YES;finish(@"persistent_owner_and_explicit_teardown_verified",true,EHR_RUNTIME_OK);}
}
}
NSDictionary *EHRSourcePluginOwnerProbeBegin(void){using namespace ehr_source_owner_probe;if(!NSThread.isMainThread)return @{@"success":@NO,@"complete":@YES,@"status":@2};auto&s=state();if(s.report)return EHRSourcePluginOwnerProbeCopyStatus();
 s.report=[@{@"success":@NO,@"complete":@NO,@"state":@"starting",@"fullMainLoadInvoked":@NO} mutableCopy];auto before=EHRSourceComponentsCopyStatus();s.report[@"bridgeBefore"]=before;
 // Never tear down an actual running plugin or any foreign source owner.
 if(![before[@"bound"] boolValue]||[before[@"managedStateCount"] intValue]||[before[@"activeNativeRegistrations"] intValue]||[before[@"pluginOwnerRooted"] boolValue]){s.report[@"complete"]=@YES;s.report[@"state"]=@"requires_fresh_empty_probe_only_component_host";return s.report;}
 @try{try{uint64_t source=0;EHRRuntimeToken exception=0;auto status=ehr_source_component_add(1,0,&source,&s.component,&exception);if(exception)ehr_runtime_object_release(exception);
 auto created=EHRSourceComponentsCopyStatus();s.report[@"bridgeCreated"]=created;
 bool expected=status==EHR_RUNTIME_OK&&source&&s.component&&[created[@"pluginOwnerRooted"] boolValue]&&[created[@"pluginOwnerPersistenceVerified"] boolValue]&&[created[@"managedStateCount"] intValue]==1&&[created[@"activeNativeRegistrations"] intValue]==1;
 EHRRuntimeToken unity=0;if(expected)status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","Object",&unity);const char *types[]={"UnityEngine.Object"};if(expected&&status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(unity,"op_Implicit",types,1,"System.Boolean",1,&s.boolMethod);
 if(!expected||status!=EHR_RUNTIME_OK){finish(@"persistent_source_owner_create_failed",false,status);return s.report;}
 auto closed=EHRSourceComponentsCloseAll();s.report[@"bridgeExplicitTeardown"]=closed;
 if([closed[@"managedStateCount"] intValue]||[closed[@"activeNativeRegistrations"] intValue]||[closed[@"pluginOwnerRooted"] boolValue]){finish(@"explicit_teardown_retained_state",false,EHR_RUNTIME_TYPE_MISMATCH);return s.report;}
 s.running=true;s.deadline=CFAbsoluteTimeGetCurrent()+8;s.report[@"state"]=@"waiting_for_real_unity_owner_destruction";s.timer=[NSTimer scheduledTimerWithTimeInterval:0.025 repeats:YES block:^(__unused NSTimer*t){tick();}];return EHRSourcePluginOwnerProbeCopyStatus();
 }catch(...){finish(@"contained_cpp_exception",false,EHR_RUNTIME_LIMIT);return s.report;}}@catch(__unused NSException*e){finish(@"contained_objc_exception",false,EHR_RUNTIME_UNSUPPORTED);return s.report;}
}
NSDictionary *EHRSourcePluginOwnerProbeCopyStatus(void){if(!NSThread.isMainThread)return @{@"success":@NO,@"complete":@YES,@"status":@2};return ehr_source_owner_probe::state().report?[ehr_source_owner_probe::state().report copy]:@{@"success":@NO,@"complete":@NO,@"state":@"not_started"};}
NSDictionary *EHRSourcePluginOwnerProbeCancel(void){if(!NSThread.isMainThread)return @{@"success":@NO,@"complete":@YES,@"status":@2};if(ehr_source_owner_probe::state().running)ehr_source_owner_probe::finish(@"cancelled",false,EHR_RUNTIME_BAD_ARGUMENT);return EHRSourcePluginOwnerProbeCopyStatus();}
