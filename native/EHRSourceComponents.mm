#import "EHRSourceComponents.h"
#include "EHRRuntimeWeak.h"
#include "EHRRuntimeActionPrivate.h"
#include "EHRRuntimeIteratorPrivate.h"
#include "EHRRuntimeReflection.h"
#include "EHRRuntimeDiagnostics.h"
#include <unordered_map>
#include <cstring>
namespace ehr_source_components {
struct Entry{uint32_t type=0;uint64_t state=0;EHRRuntimeToken weak=0;EHRRuntimeStatus callbackStatus=EHR_RUNTIME_OK;};
struct State{EHRSourceComponentCallbacksV1 callbacks{};bool bound=false,closed=false;std::unordered_map<void *,Entry> entries;
 uint64_t created=0,destroyed=0,events=0,failures=0,wrongThread=0,teardownReleased=0;int32_t lastStatus=0;EHRRuntimeToken pluginOwner=0;bool pluginOwnerVerified=false;};
State &state(){static State *s=new State;return *s;}
struct Root{EHRRuntimeToken token=0;~Root(){if(token)ehr_runtime_object_release(token);}};
void record(EHRRuntimeStatus status){state().lastStatus=status;if(status!=EHR_RUNTIME_OK)++state().failures;}
EHRRuntimeStatus ready(){if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;auto status=ehr_runtime_initialize();if(status!=EHR_RUNTIME_OK)return status;return state().bound&&!state().closed?EHR_RUNTIME_OK:EHR_RUNTIME_NOT_READY;}
// Metadata for all seven source components plus own probe. Managed profile
// remains authoritative: an uncompiled source factory rejects creation.
EHRRuntimeStatus typeClass(uint32_t type,EHRRuntimeToken *klass){
 if(!klass)return EHR_RUNTIME_BAD_ARGUMENT;*klass=0;auto status=ready();if(status!=EHR_RUNTIME_OK)return status;
 if(type<1||type>8)return EHR_RUNTIME_UNSUPPORTED;
 constexpr const char *spaces[]={"EHR","EHR","EHR.Patches","EHR.Patches","EHR.Patches","EHR.Patches","EHR","EHR.NativeProbes"};
 constexpr const char *names[]={"Coroutines","ErrorText","AbstractPagingBehaviour","MeetingHudPagingBehaviour","ShapeShifterPagingBehaviour","VitalsPagingBehaviour","ClientControlGUI","StaticLifecycleProbe"};
 return ehr_runtime_find_class("UnityEngine.CoreModule.dll",spaces[type-1],names[type-1],klass);
}
EHRRuntimeStatus registerType(uint32_t type){EHRRuntimeToken klass=0;return typeClass(type,&klass);}
EHRRuntimeStatus lookup(uint32_t type,EHRRuntimeToken object,uint64_t *source){
 if(!source)return EHR_RUNTIME_BAD_ARGUMENT;*source=0;auto status=ready();if(status!=EHR_RUNTIME_OK)return status;
 EHRRuntimeToken expected=0,actual=0;status=typeClass(type,&expected);if(status!=EHR_RUNTIME_OK)return status;
 status=ehr_runtime_object_class(object,&actual);if(status!=EHR_RUNTIME_OK)return status;
 void *native=nullptr;status=EHRRuntimeIteratorBorrow(object,&native);if(status!=EHR_RUNTIME_OK)return status;
 const auto found=state().entries.find(native);if(found==state().entries.end())return EHR_RUNTIME_NOT_FOUND;
 if(found->second.callbackStatus!=EHR_RUNTIME_OK)return found->second.callbackStatus;
 const uint32_t sourceType=found->second.type;
 if(sourceType!=type&&!(type==3&&sourceType>=4&&sourceType<=6))return EHR_RUNTIME_TYPE_MISMATCH;
 EHRRuntimeToken exact=0;status=typeClass(sourceType,&exact);if(status!=EHR_RUNTIME_OK)return status;
 if(actual!=exact)return EHR_RUNTIME_TYPE_MISMATCH;
 int32_t alive=0;status=ehr_runtime_object_weak_alive(found->second.weak,&alive);if(status!=EHR_RUNTIME_OK||!alive)return EHR_RUNTIME_INVALID_TOKEN;
 *source=found->second.state;return EHR_RUNTIME_OK;
}
EHRRuntimeStatus destroyObject(EHRRuntimeToken object);
EHRRuntimeStatus pluginOwner(EHRRuntimeToken *owner,EHRRuntimeToken *exception){
 *owner=0;*exception=0;auto&s=state();if(s.pluginOwner){if(!s.pluginOwnerVerified)return EHR_RUNTIME_NOT_READY;*owner=s.pluginOwner;return EHR_RUNTIME_OK;}
 EHRRuntimeToken game=0,unity=0,keepMethod=0;Root name,result;const char16_t text[]=u"EndlessHostRoles-iOS";
 auto status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","GameObject",&game);
 if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","Object",&unity);
 const char *params[]={"UnityEngine.Object"};if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(unity,"DontDestroyOnLoad",params,1,"System.Void",1,&keepMethod);
 if(status==EHR_RUNTIME_OK)status=ehr_runtime_string_create(reinterpret_cast<const uint16_t*>(text),sizeof(text)/sizeof(char16_t)-1,&name.token);
 Root candidate;if(status==EHR_RUNTIME_OK)status=ehr_runtime_construct(game,&name.token,1,&candidate.token,exception);
 const EHRRuntimeArgument arg{EHR_RUNTIME_REFERENCE,0,candidate.token,nullptr,0};
 if(status==EHR_RUNTIME_OK)status=ehr_runtime_invoke(keepMethod,0,&arg,1,&result.token,exception);
 if(status!=EHR_RUNTIME_OK){if(candidate.token&&destroyObject(candidate.token)!=EHR_RUNTIME_OK){s.pluginOwner=candidate.token;candidate.token=0;}return status;}s.pluginOwner=candidate.token;candidate.token=0;s.pluginOwnerVerified=true;*owner=s.pluginOwner;return EHR_RUNTIME_OK;
}
EHRRuntimeStatus destroyObject(EHRRuntimeToken object){
 if(!object)return EHR_RUNTIME_OK;EHRRuntimeToken unity=0,destroy=0;Root result,exception;
 auto status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","Object",&unity);
 const char *params[]={"UnityEngine.Object"};if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(unity,"Destroy",params,1,"System.Void",1,&destroy);
 const EHRRuntimeArgument arg{EHR_RUNTIME_REFERENCE,0,object,nullptr,0};if(status==EHR_RUNTIME_OK)status=ehr_runtime_invoke(destroy,0,&arg,1,&result.token,&exception.token);return status;
}
EHRRuntimeStatus add(uint32_t type,EHRRuntimeToken owner,uint64_t *source,EHRRuntimeToken *component,EHRRuntimeToken *exception){
 if(!source||!component||!exception||source==component||source==exception||component==exception)return EHR_RUNTIME_BAD_ARGUMENT;
 *source=0;*component=0;*exception=0;auto status=ready();if(status!=EHR_RUNTIME_OK)return status;
 EHRRuntimeToken klass=0,gameClass=0,method=0;Root typeObject;
 status=typeClass(type,&klass);if(status!=EHR_RUNTIME_OK)return status;
 if(!owner){status=pluginOwner(&owner,exception);if(status!=EHR_RUNTIME_OK)return status;}
 if(status==EHR_RUNTIME_OK)status=ehr_runtime_class_type_object(klass,&typeObject.token);
 if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","GameObject",&gameClass);
 const char *parameters[]={"System.Type"};if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(gameClass,"AddComponent",parameters,1,"UnityEngine.Component",0,&method);
 const EHRRuntimeArgument arg{EHR_RUNTIME_REFERENCE,0,typeObject.token,nullptr,0};
 if(status==EHR_RUNTIME_OK)status=ehr_runtime_invoke(method,owner,&arg,1,component,exception);
 if(status==EHR_RUNTIME_OK)status=lookup(type,*component,source);
 if(status!=EHR_RUNTIME_OK&&*component)destroyObject(*component);
 return status;
}
EHRRuntimeStatus safeRegister(uint32_t type){@try{try{return registerType(type);}catch(...){return EHR_RUNTIME_LIMIT;}}@catch(__unused NSException*e){return EHR_RUNTIME_UNSUPPORTED;}}
EHRRuntimeStatus safeClass(uint32_t type,EHRRuntimeToken *klass){@try{try{return typeClass(type,klass);}catch(...){return EHR_RUNTIME_LIMIT;}}@catch(__unused NSException*e){return EHR_RUNTIME_UNSUPPORTED;}}
EHRRuntimeStatus safeLookup(uint32_t type,EHRRuntimeToken object,uint64_t *source){@try{try{return lookup(type,object,source);}catch(...){return EHR_RUNTIME_LIMIT;}}@catch(__unused NSException*e){return EHR_RUNTIME_UNSUPPORTED;}}
EHRRuntimeStatus safeAdd(uint32_t type,EHRRuntimeToken owner,uint64_t *source,EHRRuntimeToken *component,EHRRuntimeToken *exception){@try{try{return add(type,owner,source,component,exception);}catch(...){return EHR_RUNTIME_LIMIT;}}@catch(__unused NSException*e){return EHR_RUNTIME_UNSUPPORTED;}}
bool validatedSelf(uint32_t type,void *self,Root &strong){
 if(!self||EHRRuntimeActionRootBorrowed(self,&strong.token)!=EHR_RUNTIME_OK)return false;
 EHRRuntimeToken expected=0,actual=0;return typeClass(type,&expected)==EHR_RUNTIME_OK&&ehr_runtime_object_class(strong.token,&actual)==EHR_RUNTIME_OK&&expected==actual;
}
}
void EHRSourceComponentConstruct(uint32_t type,void *self) noexcept {
 using namespace ehr_source_components;auto &s=state();if(!s.bound||s.closed)return;
 EHRDiagnosticComponentScope trace(type,0);
 auto record=[&](EHRRuntimeStatus status){trace.status=status;ehr_source_components::record(status);};
 if(!NSThread.isMainThread){++s.wrongThread;trace.status=EHR_RUNTIME_WRONG_THREAD;return;}
 @try{try{Root strong;if(!validatedSelf(type,self,strong)){record(EHR_RUNTIME_TYPE_MISMATCH);return;}
  if(s.entries.count(self)){record(EHR_RUNTIME_BAD_ARGUMENT);return;}
  Root nativeWeak,managedWeak;auto status=ehr_runtime_object_weak(strong.token,&nativeWeak.token);
  if(status==EHR_RUNTIME_OK)status=ehr_runtime_object_weak(strong.token,&managedWeak.token);
  if(status!=EHR_RUNTIME_OK){record(status);return;}
  // Create consumes the weak token on entry, including failure.
  const auto transferred=managedWeak.token;managedWeak.token=0;uint64_t source=0;
  const int32_t created=s.callbacks.create(type,transferred,&source);
  if(created!=0||!source){if(source)s.callbacks.release(source);record(created?static_cast<EHRRuntimeStatus>(created):EHR_RUNTIME_TYPE_MISMATCH);return;}
  try{s.entries.emplace(self,Entry{type,source,nativeWeak.token});nativeWeak.token=0;}
  catch(...){s.callbacks.release(source);record(EHR_RUNTIME_LIMIT);return;}
  ++s.created;record(EHR_RUNTIME_OK);
 }catch(...){record(EHR_RUNTIME_LIMIT);}}@catch(__unused NSException *e){record(EHR_RUNTIME_UNSUPPORTED);}
}
void EHRSourceComponentEvent(uint32_t type,uint32_t message,void *self) noexcept {
 using namespace ehr_source_components;auto&s=state();if(!s.bound||s.closed)return;
 EHRDiagnosticComponentScope trace(type,message);
 auto record=[&](EHRRuntimeStatus status){trace.status=status;ehr_source_components::record(status);};
 if(!NSThread.isMainThread){++s.wrongThread;trace.status=EHR_RUNTIME_WRONG_THREAD;return;}
 @try{try{Root strong;if(!validatedSelf(type,self,strong)){record(EHR_RUNTIME_TYPE_MISMATCH);return;}
  const auto found=s.entries.find(self);if(found==s.entries.end()||found->second.type!=type){record(EHR_RUNTIME_NOT_FOUND);return;}
  const auto entry=found->second;
  if(message==3)s.entries.erase(found); // Reentry cannot reacquire a dying state.
  const int32_t status=s.callbacks.dispatch(entry.state,message);++s.events;
  if(message!=3&&status!=0){const auto current=s.entries.find(self);if(current!=s.entries.end()&&current->second.state==entry.state)current->second.callbackStatus=static_cast<EHRRuntimeStatus>(status);}
  if(message==3){s.callbacks.release(entry.state);ehr_runtime_object_release(entry.weak);++s.destroyed;}
  record(static_cast<EHRRuntimeStatus>(status));
 }catch(...){record(EHR_RUNTIME_LIMIT);}}@catch(__unused NSException *e){record(EHR_RUNTIME_UNSUPPORTED);}
}
NSDictionary *EHRSourceComponentsBind(void *exported){using namespace ehr_source_components;auto&s=state();
 if(!NSThread.isMainThread)return @{@"success":@NO,@"status":@(EHR_RUNTIME_WRONG_THREAD)};
 if(s.bound)return EHRSourceComponentsCopyStatus();
 using Bind=int32_t(*)(const EHRSourceComponentNativeV1*,size_t,EHRSourceComponentCallbacksV1*,size_t);
 if(!exported)return @{@"success":@NO,@"status":@(EHR_RUNTIME_NOT_FOUND)};
 @try{try{const EHRSourceComponentNativeV1 native{1,sizeof(EHRSourceComponentNativeV1),safeRegister,safeClass,safeAdd,safeLookup,ehr_runtime_object_weak,ehr_runtime_object_weak_alive};
  EHRSourceComponentCallbacksV1 callbacks{};const auto status=reinterpret_cast<Bind>(exported)(&native,sizeof(native),&callbacks,sizeof(callbacks));
  if(status!=0||callbacks.abi_version!=1||callbacks.byte_size!=sizeof(callbacks)||!callbacks.create||!callbacks.dispatch||!callbacks.release||!callbacks.count)
   return @{@"success":@NO,@"status":@(status?status:EHR_RUNTIME_BAD_ARGUMENT)};
  s.callbacks=callbacks;s.bound=true;return EHRSourceComponentsCopyStatus();
 }catch(...){return @{@"success":@NO,@"status":@(EHR_RUNTIME_LIMIT)};}}@catch(__unused NSException*e){return @{@"success":@NO,@"status":@(EHR_RUNTIME_UNSUPPORTED)};}
}
NSDictionary *EHRSourceComponentsCopyStatus(void){using namespace ehr_source_components;auto&s=state();
 if(!NSThread.isMainThread)return @{@"success":@NO,@"status":@(EHR_RUNTIME_WRONG_THREAD)};
 uint32_t count=0;const int32_t status=s.bound?s.callbacks.count(&count):EHR_RUNTIME_NOT_READY;
 return @{@"success":@(s.bound&&status==0&&s.failures==0&&s.wrongThread==0),@"bound":@(s.bound),@"managedStateCount":@(count),@"activeNativeRegistrations":@(s.entries.size()),@"nativeWeakSelfTokens":@(s.entries.size()),@"pluginOwnerRooted":@(s.pluginOwner!=0),@"pluginOwnerPersistenceVerified":@(s.pluginOwnerVerified),@"explicitTeardownStatesReleased":@(s.teardownReleased),@"created":@(s.created),@"destroyed":@(s.destroyed),@"events":@(s.events),@"failures":@(s.failures),@"wrongThread":@(s.wrongThread),@"lastStatus":@(s.lastStatus),@"status":@(status),@"registeredNativeSourceTypeIds":@[@1,@2,@3,@4,@5,@6,@7],@"allSevenSourceClrFactoriesBound":@NO,@"compiledOwnProbeTypeId":@8,@"allSevenSourceComponentsAvailable":@NO};
}
NSDictionary *EHRSourceComponentsCloseAll(void){using namespace ehr_source_components;auto&s=state();
 if(!NSThread.isMainThread)return @{@"success":@NO,@"status":@(EHR_RUNTIME_WRONG_THREAD)};
 if(!s.bound||s.closed)return EHRSourceComponentsCopyStatus();s.closed=true;
 // Explicit plugin teardown, distinct from a scene transition. Native callbacks
 // on a remaining component then find no state and never call a released source.
 const auto destroyed=destroyObject(s.pluginOwner);if(destroyed!=EHR_RUNTIME_OK){s.closed=false;record(destroyed);return EHRSourceComponentsCopyStatus();}
 auto entries=std::move(s.entries);s.entries.clear();for(const auto &item:entries){const auto &entry=item.second;s.callbacks.release(entry.state);ehr_runtime_object_release(entry.weak);++s.teardownReleased;}
 if(s.pluginOwner){ehr_runtime_object_release(s.pluginOwner);s.pluginOwner=0;s.pluginOwnerVerified=false;}
 return EHRSourceComponentsCopyStatus();
}

extern "C" EHRRuntimeStatus ehr_source_component_add(uint32_t type,EHRRuntimeToken owner,uint64_t *state,EHRRuntimeToken *component,EHRRuntimeToken *exception){return ehr_source_components::safeAdd(type,owner,state,component,exception);}
