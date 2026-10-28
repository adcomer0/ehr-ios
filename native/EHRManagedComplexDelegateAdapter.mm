#import <Foundation/Foundation.h>
#include "EHRManagedComplexDelegateAdapter.h"
#include "EHRActionRuntimeAPI.hpp"
#include "EHRActionRegistry.hpp"
#include "EHRRuntimeActionPrivate.h"
#include "EHRRuntimeIteratorPrivate.h"
#include "EHRRuntimeReflection.h"
#include "EHRRuntimePinnedAssociation.h"
#include <array>
namespace {
struct API:ehr_action::API {
 void *(*class_from_system_type)(void *);void *(*class_from_type)(const void *);const void *(*class_get_type)(void *);
 bool (*class_is_valuetype)(void *);bool (*class_is_enum)(void *);bool (*class_is_blittable)(void *);
 const void *(*class_enum_basetype)(void *);void *(*class_get_fields)(void *,void **);const char *(*field_get_name)(void *);
 bool (*class_is_assignable_from)(void *,void *);void *(*object_get_class)(void *);
 uint32_t (*method_get_token)(const void *);bool (*type_is_byref)(const void *);int (*type_get_type)(const void *);
 bool loadAll(){if(!load())return false;
#define CAPI(name) name=reinterpret_cast<decltype(name)>(ehr_action::actionSymbol("il2cpp_" #name));if(!name)return false
 CAPI(class_from_system_type);CAPI(class_from_type);CAPI(class_get_type);CAPI(class_is_valuetype);CAPI(class_is_enum);CAPI(class_is_blittable);
 CAPI(class_enum_basetype);CAPI(class_get_fields);CAPI(field_get_name);CAPI(class_is_assignable_from);CAPI(object_get_class);CAPI(method_get_token);CAPI(type_is_byref);CAPI(type_get_type);
#undef CAPI
 return true;}
};
struct Owned {EHRRuntimeToken token=0;~Owned(){if(token)ehr_runtime_object_release(token);}};
struct Pin {API *api;uint32_t handle;~Pin(){if(handle)api->gchandle_free(handle);}};
struct Context {uint64_t source=0,registration=0;uint32_t family=0;size_t count=0;std::array<EHRRuntimeToken,3> types{};std::array<void *,3> raw{};};
struct State {
 API api{};ehr_action::Registry entries;EHRComplexDelegateCallbacksV1 callbacks{};
 std::array<Context,256> contexts{};std::array<ehr_action::PinnedMethodInfo2022,3> metadata{};
 std::array<void *,6> fields{};bool ready=false,bound=false,timer=false;uint32_t step=0;
 EHRRuntimeToken objectClass=0,pointerClass=0;std::array<EHRRuntimeToken,3> templates{};
};
State &state(){static State s;return s;}
Context *context(uint64_t source){for(auto &c:state().contexts)if(c.source==source)return &c;return nullptr;}
int32_t forget(uint64_t source){if(auto *c=context(source))*c={};return state().callbacks.forget(source);}
EHRRuntimeStatus rawClass(EHRRuntimeToken token,void **result){
 *result=nullptr;Owned type;void *object=nullptr;auto status=ehr_runtime_class_type_object(token,&type.token);
 if(status==EHR_RUNTIME_OK)status=EHRRuntimeIteratorBorrow(type.token,&object);
 if(status==EHR_RUNTIME_OK){*result=state().api.class_from_system_type(object);if(!*result)status=EHR_RUNTIME_TYPE_MISMATCH;}return status;
}
bool callbackReady(uint32_t family,const void *method){auto &s=state();return NSThread.isMainThread&&s.ready&&s.bound&&family>=1&&family<=3&&method==&s.metadata[family-1]&&ehr_runtime_initialize()==EHR_RUNTIME_OK;}
template<class F>void dispatch(uint32_t family,void *self,const void *method,F callback) noexcept {
 if(!callbackReady(family,method))return;auto &s=state();
 s.entries.dispatch(self,[&](uint32_t weak){return s.api.gchandle_get_target(weak);},[&](uint64_t source)->int32_t{auto *c=context(source);return c&&c->family==family?callback(*c):EHR_RUNTIME_TYPE_MISMATCH;});
}
EHRRuntimeStatus rootReference(const Context &c,void *value,Owned &root){
 if(value&&!state().api.class_is_assignable_from(c.raw[0],state().api.object_get_class(value)))return EHR_RUNTIME_TYPE_MISMATCH;
 return EHRRuntimeActionRootBorrowed(value,&root.token);
}
void action3(void *self,void *reference,int32_t value,int32_t kind,const void *method) noexcept {
 dispatch(1,self,method,[&](const Context &c)->int32_t{Owned first,last;auto status=rootReference(c,reference,first);
  if(status==EHR_RUNTIME_OK)status=ehr_runtime_box(c.types[2],&kind,sizeof(kind),&last.token);
  return status==EHR_RUNTIME_OK?state().callbacks.action3(c.source,first.token,value,last.token):status;});
}
bool function(void *self,void *reference,const void *method) noexcept {
 uint8_t value=0;dispatch(2,self,method,[&](const Context &c)->int32_t{Owned first;auto status=rootReference(c,reference,first);uint8_t result=0;
  if(status==EHR_RUNTIME_OK)status=static_cast<EHRRuntimeStatus>(state().callbacks.function(c.source,first.token,&result));
  if(status==EHR_RUNTIME_OK&&result>1)return EHR_RUNTIME_TYPE_MISMATCH;
  if(status==EHR_RUNTIME_OK)value=result;return status;});return value==1;
}
struct ScenePayload {int32_t handle;};static_assert(sizeof(ScenePayload)==4);
void scene2(void *self,ScenePayload scene,int32_t mode,const void *method) noexcept {
 dispatch(3,self,method,[&](const Context &c)->int32_t{Owned first,last;auto status=ehr_runtime_box(c.types[0],&scene,sizeof(scene),&first.token);
  if(status==EHR_RUNTIME_OK)status=ehr_runtime_box(c.types[1],&mode,sizeof(mode),&last.token);
  return status==EHR_RUNTIME_OK?state().callbacks.scene2(c.source,first.token,last.token):status;});
}
EHRRuntimeStatus prepare(){
 if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;auto status=ehr_runtime_initialize();if(status!=EHR_RUNTIME_OK)return status;
 auto &s=state();if(s.ready)return EHR_RUNTIME_OK;EHRRuntimeToken constants=0,version=0;uint64_t observed=0;
 status=ehr_runtime_find_class("Assembly-CSharp.dll","","Constants",&constants);
 if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(constants,"GetBroadcastVersion",nullptr,0,"System.Int32",1,&version);
 if(status==EHR_RUNTIME_OK)status=ehr_runtime_validate_native_method(version,30734292,&observed);
 if(status!=EHR_RUNTIME_OK)return status;if(!s.api.loadAll())return EHR_RUNTIME_UNSUPPORTED;
 status=ehr_runtime_find_class("mscorlib.dll","System","Object",&s.objectClass);
 if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_class("mscorlib.dll","System","IntPtr",&s.pointerClass);
 const char *images[]={"mscorlib.dll","mscorlib.dll","UnityEngine.CoreModule.dll"};const char *spaces[]={"System","System","UnityEngine.Events"};const char *names[]={"Action`3","Func`2","UnityAction`2"};
 for(size_t i=0;i<3&&status==EHR_RUNTIME_OK;++i)status=ehr_runtime_find_class(images[i],spaces[i],names[i],&s.templates[i]);
 EHRRuntimeToken delegateClass=0;void *owner=nullptr;if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_class("mscorlib.dll","System","Delegate",&delegateClass);
 if(status==EHR_RUNTIME_OK)status=rawClass(delegateClass,&owner);if(status!=EHR_RUNTIME_OK)return status;
 const char *fields[]={"method_ptr","invoke_impl","method","method_code","m_target","method_info"};const char *types[]={"System.IntPtr","System.IntPtr","System.IntPtr","System.IntPtr","System.Object","System.Reflection.MethodInfo"};
 for(size_t i=0;i<6;++i){s.fields[i]=s.api.field(owner,fields[i],types[i]);if(!s.fields[i])return EHR_RUNTIME_TYPE_MISMATCH;}
 const std::array<void *,3> entries{{reinterpret_cast<void *>(&action3),reinterpret_cast<void *>(&function),reinterpret_cast<void *>(&scene2)}};
 for(size_t i=0;i<3;++i){auto &m=s.metadata[i];m.methodPointer=m.virtualMethodPointer=entries[i];m.parameterCount=i==0?3:i==1?1:2;m.slot=UINT16_MAX;}
 s.ready=true;return EHR_RUNTIME_OK;
}
bool isReference(void *klass){auto &a=state().api;const void *type=a.class_get_type(klass);if(!type||a.type_is_byref(type)||a.class_is_valuetype(klass))return false;
 int k=a.type_get_type(type);return k==0x0e||k==0x12||k==0x14||k==0x15||k==0x1c||k==0x1d;}
bool isEnum32(void *klass,EHRRuntimeToken token){size_t width=0;auto &a=state().api;return a.class_is_enum(klass)&&a.typeEquals(a.class_enum_basetype(klass),"System.Int32")&&ehr_runtime_value_size(token,&width)==EHR_RUNTIME_OK&&width==4;}
EHRRuntimeStatus classify(const Context &c){auto &a=state().api;
 if(c.family==1)return isReference(c.raw[0])&&a.typeEquals(a.class_get_type(c.raw[1]),"System.Int32")&&isEnum32(c.raw[2],c.types[2])?EHR_RUNTIME_OK:EHR_RUNTIME_UNSUPPORTED;
 if(c.family==2)return isReference(c.raw[0])&&a.typeEquals(a.class_get_type(c.raw[1]),"System.Boolean")?EHR_RUNTIME_OK:EHR_RUNTIME_UNSUPPORTED;
 if(!a.typeEquals(a.class_get_type(c.raw[0]),"UnityEngine.SceneManagement.Scene")||!a.class_is_valuetype(c.raw[0])||!a.class_is_blittable(c.raw[0])||!isEnum32(c.raw[1],c.types[1]))return EHR_RUNTIME_UNSUPPORTED;
 size_t width=0;auto status=ehr_runtime_value_size(c.types[0],&width);if(status!=EHR_RUNTIME_OK||width!=sizeof(ScenePayload))return EHR_RUNTIME_UNSUPPORTED;
 void *iterator=nullptr;size_t instance=0;for(size_t n=0;n<4096;++n){void *f=a.class_get_fields(c.raw[0],&iterator);if(!f)break;if(a.field_get_flags(f)&0x10)continue;
  const char *name=a.field_get_name(f);if(!name||strcmp(name,"m_Handle")||!a.typeEquals(a.field_get_type(f),"System.Int32"))return EHR_RUNTIME_UNSUPPORTED;++instance;}
 return instance==1?EHR_RUNTIME_OK:EHR_RUNTIME_UNSUPPORTED;
}
EHRRuntimeStatus methods(void *owner,const Context &c,const void **invoke){
 auto &s=state();auto &a=s.api;void *iterator=nullptr;const void *ctor=nullptr;*invoke=nullptr;size_t arguments=c.family==1?3:c.family==2?1:2;
 for(size_t n=0;n<4096;++n){const void *m=a.class_get_methods(owner,&iterator);if(!m)break;const char *name=a.method_get_name(m);uint32_t impl=0;
  if(!name||a.method_get_class(m)!=owner||(a.method_get_flags(m,&impl)&0x10))continue;
  size_t count=a.method_get_param_count(m);
  if(!strcmp(name,".ctor")&&count==2&&a.typeEquals(a.method_get_return_type(m),"System.Void")&&a.typeEquals(a.method_get_param(m,0),"System.Object")&&a.typeEquals(a.method_get_param(m,1),"System.IntPtr")){if(ctor)return EHR_RUNTIME_AMBIGUOUS;ctor=m;}
  if(strcmp(name,"Invoke")||count!=arguments||!a.typeEquals(a.method_get_return_type(m),c.family==2?"System.Boolean":"System.Void"))continue;
  bool exact=true;for(size_t i=0;i<count;++i){const void *t=a.method_get_param(m,static_cast<uint32_t>(i));exact=exact&&t&&!a.type_is_byref(t)&&a.class_from_type(t)==c.raw[i];}
  if(exact){if(*invoke)return EHR_RUNTIME_AMBIGUOUS;*invoke=m;}
 }
 if(!ctor||!*invoke)return EHR_RUNTIME_UNSUPPORTED;
 constexpr uint64_t ctorRvas[]={0x2f3fa58,0x2e82b40,0x26bb480},invokeRvas[]={0x2f3fb6c,0x2e82c64,0x26bb524};
 auto validate=[&](const void *m,uint64_t expected){uint64_t observed=0;return ehr_pinned::validate({m,owner,a.method_get_class(m),a.method_get_name(m),a.method_get_token(m)},expected,&observed);};
 s.step=6;auto status=validate(ctor,ctorRvas[c.family-1]);if(status==EHR_RUNTIME_OK){s.step=7;status=validate(*invoke,invokeRvas[c.family-1]);}return status;
}
void schedule();
int32_t createImpl(uint64_t source,uint32_t family,const EHRRuntimeToken *types,size_t count,EHRRuntimeToken *result,uint64_t *registration,EHRRuntimeToken *exception){
 if(!result||!registration||!exception)return EHR_RUNTIME_BAD_ARGUMENT;*result=0;*registration=0;*exception=0;
 if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;auto &s=state();if(!s.bound||!source||family<1||family>3||!types||count!=(family==1?3u:2u))return EHR_RUNTIME_BAD_ARGUMENT;
 s.step=1;auto status=prepare();if(status!=EHR_RUNTIME_OK)return status;size_t removed=0;status=EHRComplexDelegateSweep(&removed);if(status!=EHR_RUNTIME_OK)return status;
 auto *existing=s.entries.findSource(source);Context *slot=context(source);if((existing==nullptr)!=(slot==nullptr))return EHR_RUNTIME_BAD_ARGUMENT;
 if(!existing&&!s.entries.hasCapacity())return EHR_RUNTIME_LIMIT;if(!slot)for(auto &c:s.contexts)if(!c.source){slot=&c;break;}if(!slot)return EHR_RUNTIME_LIMIT;
 Context wanted{};wanted.source=source;wanted.family=family;wanted.count=count;
 s.step=2;for(size_t i=0;i<count;++i){wanted.types[i]=types[i];status=rawClass(types[i],&wanted.raw[i]);if(status!=EHR_RUNTIME_OK)return status;
  if(existing&&(slot->family!=family||slot->count!=count||slot->raw[i]!=wanted.raw[i]))return EHR_RUNTIME_TYPE_MISMATCH;}
 status=classify(wanted);if(status!=EHR_RUNTIME_OK)return status;EHRRuntimeToken closed=0;void *owner=nullptr;const void *invoke=nullptr;
 s.step=3;status=ehr_runtime_make_generic_class(s.templates[family-1],types,count,&closed,exception);
 if(status==EHR_RUNTIME_OK){s.step=4;status=rawClass(closed,&owner);}if(status==EHR_RUNTIME_OK){s.step=5;status=methods(owner,wanted,&invoke);}if(status!=EHR_RUNTIME_OK)return status;
 Owned carrier,carrierPin,pointer,action,actionPin;void *self=nullptr,*native=nullptr;s.step=8;
 if(existing){void *target=s.api.gchandle_get_target(existing->weak);if(!target)return EHR_RUNTIME_INVALID_TOKEN;status=EHRRuntimeActionRootBorrowed(target,&carrier.token);}
 else status=ehr_runtime_construct(s.objectClass,nullptr,0,&carrier.token,exception);
 if(status==EHR_RUNTIME_OK)status=EHRRuntimeIteratorPin(carrier.token,&carrierPin.token,&self);
 void *metadata=&s.metadata[family-1];if(status==EHR_RUNTIME_OK)status=ehr_runtime_box(s.pointerClass,&metadata,sizeof(metadata),&pointer.token);
 const EHRRuntimeToken arguments[]={carrier.token,pointer.token};if(status==EHR_RUNTIME_OK){s.step=9;status=ehr_runtime_construct(closed,arguments,2,&action.token,exception);}
 if(status==EHR_RUNTIME_OK)status=EHRRuntimeIteratorPin(action.token,&actionPin.token,&native);if(status!=EHR_RUNTIME_OK)return status;
 s.step=10;void *reflection=s.api.method_get_object(invoke,owner);Pin pin{&s.api,reflection?s.api.gchandle_new(reflection,true):0};if(!pin.handle)return EHR_RUNTIME_NOT_READY;
 reflection=s.api.gchandle_get_target(pin.handle);if(!reflection)return EHR_RUNTIME_NOT_READY;void *entry=s.metadata[family-1].methodPointer;
 s.api.field_set_value(native,s.fields[0],&entry);s.api.field_set_value(native,s.fields[1],&entry);s.api.field_set_value(native,s.fields[2],&metadata);s.api.field_set_value(native,s.fields[3],&self);
 s.api.field_set_value_object(native,s.fields[4],self);s.api.field_set_value_object(native,s.fields[5],reflection);
 uint64_t id=existing?existing->registration:0;if(!existing){uint32_t weak=s.api.gchandle_new_weakref(self,false);if(!weak)return EHR_RUNTIME_NOT_READY;id=s.entries.add(source,weak);if(!id){s.api.gchandle_free(weak);return EHR_RUNTIME_LIMIT;}}
 wanted.registration=id;*slot=wanted;*result=action.token;action.token=0;*registration=id;s.step=11;schedule();return EHR_RUNTIME_OK;
}
int32_t create(uint64_t source,uint32_t family,const EHRRuntimeToken *types,size_t count,EHRRuntimeToken *result,uint64_t *reg,EHRRuntimeToken *exception) noexcept {
 try{return createImpl(source,family,types,count,result,reg,exception);}catch(...){if(result&&*result){ehr_runtime_object_release(*result);*result=0;}if(reg&&*reg){state().entries.close(*reg,forget);*reg=0;}return EHR_RUNTIME_LIMIT;}
}
int32_t close(uint64_t id){if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;return state().bound?state().entries.close(id,forget):EHR_RUNTIME_NOT_READY;}
int32_t status(uint64_t id,int32_t *result){if(!result)return EHR_RUNTIME_BAD_ARGUMENT;*result=0;if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;auto *e=state().entries.find(id);if(!e)return EHR_RUNTIME_INVALID_TOKEN;*result=e->status;return EHR_RUNTIME_OK;}
void schedule(){auto &s=state();if(s.timer||!s.entries.count())return;s.timer=true;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{state().timer=false;size_t n=0;EHRComplexDelegateSweep(&n);schedule();});}
}
void EHRComplexDelegateMakeTable(EHRComplexDelegateHostV1 *table){if(table)*table={1,sizeof(*table),create,close,status,[]()->int32_t{return NSThread.isMainThread?1:0;}};}
EHRRuntimeStatus EHRComplexDelegateSetCallbacks(const EHRComplexDelegateCallbacksV1 *table){
 if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;if(!table||table->abi_version!=1||table->byte_size!=sizeof(*table)||!table->action3||!table->function||!table->scene2||!table->forget)return EHR_RUNTIME_BAD_ARGUMENT;
 auto &s=state();if(s.bound&&(s.callbacks.action3!=table->action3||s.callbacks.function!=table->function||s.callbacks.scene2!=table->scene2||s.callbacks.forget!=table->forget))return EHR_RUNTIME_BAD_ARGUMENT;s.callbacks=*table;s.bound=true;return EHR_RUNTIME_OK;
}
EHRRuntimeStatus EHRComplexDelegateSweep(size_t *removed){if(!removed)return EHR_RUNTIME_BAD_ARGUMENT;*removed=0;if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;auto &s=state();if(!s.bound||!s.ready)return EHR_RUNTIME_OK;auto status=ehr_runtime_initialize();if(status!=EHR_RUNTIME_OK)return status;*removed=s.entries.sweep([&](uint32_t h){return s.api.gchandle_get_target(h);},[&](uint32_t h){s.api.gchandle_free(h);},forget);return EHR_RUNTIME_OK;}
uint64_t EHRComplexDelegateActiveCount(){return NSThread.isMainThread?state().entries.active():UINT64_MAX;}
uint64_t EHRComplexDelegateWeakCount(){return NSThread.isMainThread?state().entries.count():UINT64_MAX;}
uint32_t EHRComplexDelegateLastStep(){return NSThread.isMainThread?state().step:UINT32_MAX;}
