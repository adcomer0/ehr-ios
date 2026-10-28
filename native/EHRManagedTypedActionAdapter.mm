#import <Foundation/Foundation.h>
#include "EHRManagedTypedActionAdapter.h"
#include "EHRActionRuntimeAPI.hpp"
#include "EHRActionRegistry.hpp"
#include "EHRRuntimeReflection.h"
#include "EHRRuntimeIteratorPrivate.h"
#include "EHRRuntimeActionPrivate.h"
#include "EHRRuntimePinnedAssociation.h"
#include <array>
namespace {
struct API:ehr_action::API {
    void *(*class_from_system_type)(void *);
    const void *(*class_get_type)(void *);
    void *(*class_from_type)(const void *);
    bool (*class_is_valuetype)(void *);
    bool (*class_is_assignable_from)(void *,void *);
    void *(*object_get_class)(void *);
    uint32_t (*method_get_token)(const void *);
    int (*type_get_type)(const void *);
    bool (*type_is_byref)(const void *);
    bool loadTyped(){if(!load())return false;
#define TYPED_API(name) name=reinterpret_cast<decltype(name)>(ehr_action::actionSymbol("il2cpp_" #name));if(!name)return false
        TYPED_API(class_from_system_type);TYPED_API(class_get_type);TYPED_API(class_from_type);TYPED_API(class_is_valuetype);
        TYPED_API(class_is_assignable_from);TYPED_API(object_get_class);TYPED_API(method_get_token);TYPED_API(type_get_type);TYPED_API(type_is_byref);
#undef TYPED_API
        return true;}
};
struct Owned {EHRRuntimeToken value=0;~Owned(){if(value)ehr_runtime_object_release(value);}};
struct RawPin {API *api=nullptr;uint32_t handle=0;~RawPin(){if(handle)api->gchandle_free(handle);}};
struct Context {uint64_t source=0,registration=0;uint32_t abi=0;void *argumentClass=nullptr;};
struct State {
    ehr_action::Registry entries;API api{};
    EHRManagedTypedActionCallbacksV1 callbacks{};
    std::array<ehr_action::PinnedMethodInfo2022,4> metadata{};
    std::array<Context,256> contexts{};
    bool bound=false,ready=false,timer=false;
    uint32_t lastStep=0;
    EHRRuntimeToken objectClass=0,intPtrClass=0,openAction=0;
    std::array<void *,6> fields{};
};
State &state(){static State value;return value;}
Context *context(uint64_t source){for(auto &c:state().contexts)if(c.source==source)return &c;return nullptr;}
int32_t forget(uint64_t source){if(auto *c=context(source))*c={};return state().callbacks.forget(source);}
bool callbackReady(uint32_t abi,const void *method){auto &s=state();return NSThread.isMainThread&&s.ready&&s.bound&&abi>=1&&abi<=4&&method==&s.metadata[abi-1]&&ehr_runtime_initialize()==EHR_RUNTIME_OK;}
template<class Invoke> void dispatch(uint32_t abi,void *self,const void *method,Invoke invoke) noexcept {
    if(!callbackReady(abi,method))return;
    auto &s=state();s.entries.dispatch(self,[&](uint32_t weak){return s.api.gchandle_get_target(weak);},[&](uint64_t source)->int32_t{
        auto *c=context(source);if(!c||c->abi!=abi)return EHR_RUNTIME_TYPE_MISMATCH;return invoke(*c);
    });
}
void invokeI32(void *self,int32_t value,const void *method) noexcept {dispatch(1,self,method,[&](const Context &c){return state().callbacks.invoke_i32(c.source,value);});}
void invokeU8(void *self,uint8_t value,const void *method) noexcept {dispatch(2,self,method,[&](const Context &c){return state().callbacks.invoke_u8(c.source,value);});}
void invokeF32(void *self,float value,const void *method) noexcept {dispatch(3,self,method,[&](const Context &c){return state().callbacks.invoke_f32(c.source,value);});}
void invokeReference(void *self,void *value,const void *method) noexcept {
    dispatch(4,self,method,[&](const Context &c)->int32_t{
        auto &s=state();
        if(value&&!s.api.class_is_assignable_from(c.argumentClass,s.api.object_get_class(value)))return EHR_RUNTIME_TYPE_MISMATCH;
        Owned argument;auto status=EHRRuntimeActionRootBorrowed(value,&argument.value);
        return status==EHR_RUNTIME_OK ? s.callbacks.invoke_reference(c.source,argument.value) : status;
    });
}
EHRRuntimeStatus rawClass(EHRRuntimeToken token,void **raw){
    *raw=nullptr;Owned type;auto status=ehr_runtime_class_type_object(token,&type.value);void *object=nullptr;
    if(status==EHR_RUNTIME_OK)status=EHRRuntimeIteratorBorrow(type.value,&object);
    if(status==EHR_RUNTIME_OK){*raw=state().api.class_from_system_type(object);if(!*raw)status=EHR_RUNTIME_TYPE_MISMATCH;}
    return status;
}
EHRRuntimeStatus prepare(){
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    auto status=ehr_runtime_initialize();if(status!=EHR_RUNTIME_OK)return status;
    auto &s=state();if(s.ready)return EHR_RUNTIME_OK;
    EHRRuntimeToken constants=0,version=0;uint64_t observed=0;
    status=ehr_runtime_find_class("Assembly-CSharp.dll","","Constants",&constants);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(constants,"GetBroadcastVersion",nullptr,0,"System.Int32",1,&version);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_validate_native_method(version,30734292,&observed);
    if(status!=EHR_RUNTIME_OK)return status;
    if(!s.api.loadTyped())return EHR_RUNTIME_UNSUPPORTED;
    status=ehr_runtime_find_class("mscorlib.dll","System","Object",&s.objectClass);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_class("mscorlib.dll","System","IntPtr",&s.intPtrClass);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_class("mscorlib.dll","System","Action`1",&s.openAction);
    EHRRuntimeToken delegateClass=0;void *rawDelegate=nullptr;
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_class("mscorlib.dll","System","Delegate",&delegateClass);
    if(status==EHR_RUNTIME_OK)status=rawClass(delegateClass,&rawDelegate);
    if(status!=EHR_RUNTIME_OK)return status;
    const char *names[]={"method_ptr","invoke_impl","method","method_code","m_target","method_info"};
    const char *types[]={"System.IntPtr","System.IntPtr","System.IntPtr","System.IntPtr","System.Object","System.Reflection.MethodInfo"};
    for(size_t i=0;i<s.fields.size();++i){s.fields[i]=s.api.field(rawDelegate,names[i],types[i]);if(!s.fields[i])return EHR_RUNTIME_TYPE_MISMATCH;}
    const std::array<void *,4> entries{{reinterpret_cast<void *>(&invokeI32),reinterpret_cast<void *>(&invokeU8),reinterpret_cast<void *>(&invokeF32),reinterpret_cast<void *>(&invokeReference)}};
    for(size_t i=0;i<s.metadata.size();++i){auto &m=s.metadata[i];m.methodPointer=m.virtualMethodPointer=entries[i];m.parameterCount=1;m.slot=UINT16_MAX;}
    s.ready=true;return EHR_RUNTIME_OK;
}
EHRRuntimeStatus classify(void *argument,uint32_t abi){
    auto &api=state().api;const void *type=api.class_get_type(argument);
    if(!type||api.type_is_byref(type))return EHR_RUNTIME_UNSUPPORTED;
    if(abi==1)return api.typeEquals(type,"System.Int32") ? EHR_RUNTIME_OK:EHR_RUNTIME_TYPE_MISMATCH;
    if(abi==2)return api.typeEquals(type,"System.Byte") ? EHR_RUNTIME_OK:EHR_RUNTIME_TYPE_MISMATCH;
    if(abi==3)return api.typeEquals(type,"System.Single") ? EHR_RUNTIME_OK:EHR_RUNTIME_TYPE_MISMATCH;
    const int kind=api.type_get_type(type);
    return abi==4&&!api.class_is_valuetype(argument)&&(kind==0x0e||kind==0x12||kind==0x14||kind==0x15||kind==0x1c||kind==0x1d) ? EHR_RUNTIME_OK:EHR_RUNTIME_UNSUPPORTED;
}
EHRRuntimeStatus methods(void *owner,void *argument,uint32_t abi,const void **invoke){
    auto &api=state().api;void *iterator=nullptr;const void *ctor=nullptr;*invoke=nullptr;
    for(size_t i=0;i<4096;++i){const void *m=api.class_get_methods(owner,&iterator);if(!m)break;
        const char *name=api.method_get_name(m);uint32_t flags=0;
        if(!name||api.method_get_class(m)!=owner||(api.method_get_flags(m,&flags)&0x10)||!api.typeEquals(api.method_get_return_type(m),"System.Void"))continue;
        const auto count=api.method_get_param_count(m);
        if(!strcmp(name,".ctor")&&count==2&&api.typeEquals(api.method_get_param(m,0),"System.Object")&&api.typeEquals(api.method_get_param(m,1),"System.IntPtr")){if(ctor)return EHR_RUNTIME_AMBIGUOUS;ctor=m;}
        if(!strcmp(name,"Invoke")&&count==1){const void *type=api.method_get_param(m,0);
            if(type&&!api.type_is_byref(type)&&api.class_from_type(type)==argument){if(*invoke)return EHR_RUNTIME_AMBIGUOUS;*invoke=m;}}
    }
    if(!ctor||!*invoke)return EHR_RUNTIME_UNSUPPORTED;
    constexpr std::array<uint64_t,4> ctorRvas{{0x2debb88,0x2de9fa4,0x2f36f6c,0x2dec984}},invokeRvas{{0x2debc2c,0x2dea048,0x2f37010,0x2decaa8}};
    const auto validate=[&](const void *m,uint64_t expected){uint64_t observed=0;return ehr_pinned::validate({m,owner,api.method_get_class(m),api.method_get_name(m),api.method_get_token(m)},expected,&observed);};
    state().lastStep=6;auto status=validate(ctor,ctorRvas[abi-1]);if(status==EHR_RUNTIME_OK){state().lastStep=7;status=validate(*invoke,invokeRvas[abi-1]);}return status;
}
void schedule();
int32_t createImpl(uint64_t source,EHRRuntimeToken argumentClass,uint32_t abi,EHRRuntimeToken *result,uint64_t *registration,EHRRuntimeToken *exception){
    if(!result||!registration||!exception)return EHR_RUNTIME_BAD_ARGUMENT;*result=0;*registration=0;*exception=0;
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    auto &s=state();if(!source||!s.bound||abi<1||abi>4)return EHR_RUNTIME_BAD_ARGUMENT;
    s.lastStep=1;auto status=prepare();if(status!=EHR_RUNTIME_OK)return status;
    size_t removed=0;status=EHRManagedTypedActionSweep(&removed);if(status!=EHR_RUNTIME_OK)return status;
    auto *existing=s.entries.findSource(source);Context *slot=context(source);
    if((existing==nullptr)!=(slot==nullptr))return EHR_RUNTIME_BAD_ARGUMENT;
    if(!existing&&!s.entries.hasCapacity())return EHR_RUNTIME_LIMIT;
    if(!slot)for(auto &c:s.contexts)if(!c.source){slot=&c;break;}
    if(!slot)return EHR_RUNTIME_LIMIT;
    void *argument=nullptr,*closedRaw=nullptr;EHRRuntimeToken closed=0;
    s.lastStep=2;status=rawClass(argumentClass,&argument);if(status==EHR_RUNTIME_OK)status=classify(argument,abi);
    if(status==EHR_RUNTIME_OK&&existing&&(slot->abi!=abi||slot->argumentClass!=argument))return EHR_RUNTIME_TYPE_MISMATCH;
    if(status==EHR_RUNTIME_OK){s.lastStep=3;status=ehr_runtime_make_generic_class(s.openAction,&argumentClass,1,&closed,exception);}
    if(status==EHR_RUNTIME_OK){s.lastStep=4;status=rawClass(closed,&closedRaw);}
    const void *invoke=nullptr;if(status==EHR_RUNTIME_OK){s.lastStep=5;status=methods(closedRaw,argument,abi,&invoke);}
    if(status!=EHR_RUNTIME_OK)return status;
    Owned carrier,carrierPin,pointer,action,actionPin;void *self=nullptr,*nativeAction=nullptr;
    s.lastStep=8;
    if(existing){void *target=s.api.gchandle_get_target(existing->weak);if(!target)return EHR_RUNTIME_INVALID_TOKEN;status=EHRRuntimeActionRootBorrowed(target,&carrier.value);}
    else status=ehr_runtime_construct(s.objectClass,nullptr,0,&carrier.value,exception);
    if(status==EHR_RUNTIME_OK)status=EHRRuntimeIteratorPin(carrier.value,&carrierPin.value,&self);
    void *metadata=&s.metadata[abi-1];
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_box(s.intPtrClass,&metadata,sizeof(metadata),&pointer.value);
    const EHRRuntimeToken arguments[]={carrier.value,pointer.value};
    if(status==EHR_RUNTIME_OK){s.lastStep=9;status=ehr_runtime_construct(closed,arguments,2,&action.value,exception);}
    if(status==EHR_RUNTIME_OK)status=EHRRuntimeIteratorPin(action.value,&actionPin.value,&nativeAction);
    if(status!=EHR_RUNTIME_OK)return status;
    s.lastStep=10;void *reflection=s.api.method_get_object(invoke,closedRaw);RawPin reflectionPin{&s.api,reflection ? s.api.gchandle_new(reflection,true):0};
    if(!reflectionPin.handle)return EHR_RUNTIME_NOT_READY;
    reflection=s.api.gchandle_get_target(reflectionPin.handle);if(!reflection)return EHR_RUNTIME_NOT_READY;
    void *entry=s.metadata[abi-1].methodPointer;
    s.api.field_set_value(nativeAction,s.fields[0],&entry);s.api.field_set_value(nativeAction,s.fields[1],&entry);
    s.api.field_set_value(nativeAction,s.fields[2],&metadata);s.api.field_set_value(nativeAction,s.fields[3],&self);
    s.api.field_set_value_object(nativeAction,s.fields[4],self);s.api.field_set_value_object(nativeAction,s.fields[5],reflection);
    uint64_t id=existing?existing->registration:0;
    if(!existing){const uint32_t weak=s.api.gchandle_new_weakref(self,false);if(!weak)return EHR_RUNTIME_NOT_READY;
        id=s.entries.add(source,weak);if(!id){s.api.gchandle_free(weak);return EHR_RUNTIME_LIMIT;}}
    *slot={source,id,abi,argument};*result=action.value;action.value=0;*registration=id;s.lastStep=11;schedule();return EHR_RUNTIME_OK;
}
int32_t create(uint64_t source,EHRRuntimeToken arg,uint32_t abi,EHRRuntimeToken *result,uint64_t *reg,EHRRuntimeToken *exception) noexcept {
    try{return createImpl(source,arg,abi,result,reg,exception);}catch(...){
        if(result&&*result){ehr_runtime_object_release(*result);*result=0;}
        if(reg&&*reg){state().entries.close(*reg,forget);*reg=0;}
        return EHR_RUNTIME_LIMIT;
    }
}
int32_t close(uint64_t registration){if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;return state().bound ? state().entries.close(registration,forget):EHR_RUNTIME_NOT_READY;}
int32_t callbackStatus(uint64_t registration,int32_t *status){if(!status)return EHR_RUNTIME_BAD_ARGUMENT;*status=0;if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;auto *e=state().entries.find(registration);if(!e)return EHR_RUNTIME_INVALID_TOKEN;*status=e->status;return EHR_RUNTIME_OK;}
void schedule(){auto &s=state();if(s.timer||!s.entries.count())return;s.timer=true;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{state().timer=false;size_t n=0;EHRManagedTypedActionSweep(&n);schedule();});}
}
void EHRManagedTypedActionMakeTable(EHRManagedTypedActionHostV1 *table){if(table)*table={1,sizeof(*table),create,close,callbackStatus,[]()->int32_t{return NSThread.isMainThread?1:0;}};}
EHRRuntimeStatus EHRManagedTypedActionSetCallbacks(const EHRManagedTypedActionCallbacksV1 *table){
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    if(!table||table->abi_version!=1||table->byte_size!=sizeof(*table)||!table->invoke_i32||!table->invoke_u8||!table->invoke_f32||!table->invoke_reference||!table->forget)return EHR_RUNTIME_BAD_ARGUMENT;
    auto &s=state();if(s.bound&&(s.callbacks.invoke_i32!=table->invoke_i32||s.callbacks.invoke_u8!=table->invoke_u8||s.callbacks.invoke_f32!=table->invoke_f32||s.callbacks.invoke_reference!=table->invoke_reference||s.callbacks.forget!=table->forget))return EHR_RUNTIME_BAD_ARGUMENT;
    s.callbacks=*table;s.bound=true;return EHR_RUNTIME_OK;
}
EHRRuntimeStatus EHRManagedTypedActionSweep(size_t *removed){if(!removed)return EHR_RUNTIME_BAD_ARGUMENT;*removed=0;if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;auto &s=state();if(!s.ready||!s.bound)return EHR_RUNTIME_OK;auto status=ehr_runtime_initialize();if(status!=EHR_RUNTIME_OK)return status;*removed=s.entries.sweep([&](uint32_t h){return s.api.gchandle_get_target(h);},[&](uint32_t h){s.api.gchandle_free(h);},forget);return EHR_RUNTIME_OK;}
uint64_t EHRManagedTypedActionRegistrationCount(){return NSThread.isMainThread?state().entries.count():UINT64_MAX;}
uint64_t EHRManagedTypedActionActiveCount(){return NSThread.isMainThread?state().entries.active():UINT64_MAX;}
uint32_t EHRManagedTypedActionLastStep(){return NSThread.isMainThread?state().lastStep:UINT32_MAX;}
