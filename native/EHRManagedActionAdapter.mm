#import <Foundation/Foundation.h>
#include "EHRManagedActionAdapter.h"
#include "EHRActionRuntimeAPI.hpp"
#include "EHRActionRegistry.hpp"
#include "EHRRuntimeReflection.h"
#include "EHRRuntimeIteratorPrivate.h"
#include "EHRRuntimeActionPrivate.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>

namespace ehr_action {
void *actionSymbol(const char *symbol) {
    if(void *value=dlsym(RTLD_DEFAULT,symbol)) return value;
    for(uint32_t i=0;i<_dyld_image_count();++i) {
        const char *path=_dyld_get_image_name(i);
        if(!path || !strstr(path,"/UnityFramework.framework/UnityFramework")) continue;
        void *handle=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);
        if(!handle) continue;
        void *value=dlsym(handle,symbol);dlclose(handle);if(value) return value;
    }
    return nullptr;
}
namespace {
struct Owned {
    EHRRuntimeToken value=0;
    ~Owned(){if(value) ehr_runtime_object_release(value);}
};
struct State {
    Registry entries;
    API api{};
    PinnedMethodInfo2022 metadata{};
    EHRManagedActionCallbacksV1 callbacks{};
    bool bound=false,ready=false,timerScheduled=false;
    EHRRuntimeToken actionClass=0,objectClass=0,intPtrClass=0,invokeMethod=0;
    EHRRuntimeToken unityClass=0,unityInvoke=0;
    void *methodPtrField=nullptr,*invokeImplField=nullptr,*methodField=nullptr,*methodCodeField=nullptr,*targetField=nullptr,*methodInfoField=nullptr;
};
State &state(){static State value;return value;}
void scheduleSweep();
void callback(void *identity,const void *method) noexcept {
    auto &s=state();
    // Off-main invocations are contained without managed execution or GC work.
    if(!NSThread.isMainThread || !s.ready || !s.bound || method!=&s.metadata || ehr_runtime_initialize()!=EHR_RUNTIME_OK) return;
    s.entries.dispatch(identity,[&](uint32_t weak){return s.api.gchandle_get_target(weak);},
        [&](uint64_t source){return s.callbacks.invoke(source);});
}
EHRRuntimeStatus prepare() {
    if(!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    auto status=ehr_runtime_initialize();if(status!=EHR_RUNTIME_OK) return status;
    auto &s=state();if(s.ready) return EHR_RUNTIME_OK;
    // Private callback metadata is never initialized/consumed until the exact
    // signed framework hash, loaded UUID and version association are proven.
    EHRRuntimeToken constants=0,version=0;uint64_t observed=0;
    status=ehr_runtime_find_class("Assembly-CSharp.dll","","Constants",&constants);
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_find_method(constants,"GetBroadcastVersion",nullptr,0,"System.Int32",1,&version);
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_validate_native_method(version,UINT64_C(30734292),&observed);
    if(status!=EHR_RUNTIME_OK) return status;
    if(!s.api.load()) return EHR_RUNTIME_UNSUPPORTED;
    status=ehr_runtime_find_class("mscorlib.dll","System","Action",&s.actionClass);
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_find_class("mscorlib.dll","System","Object",&s.objectClass);
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_find_class("mscorlib.dll","System","IntPtr",&s.intPtrClass);
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_find_method(s.actionClass,"Invoke",nullptr,0,"System.Void",0,&s.invokeMethod);
    if(status!=EHR_RUNTIME_OK) return status;
    size_t count=0;const void **assemblies=s.api.domain_get_assemblies(s.api.domain_get(),&count);
    const void *image=nullptr;
    if(!assemblies || count>4096) return EHR_RUNTIME_NOT_READY;
    for(size_t i=0;i<count;++i) {
        const void *candidate=s.api.assembly_get_image(assemblies[i]);
        const char *name=candidate ? s.api.image_get_name(candidate) : nullptr;
        if(name && !strcmp(name,"mscorlib.dll")) {if(image) return EHR_RUNTIME_AMBIGUOUS;image=candidate;}
    }
    void *actionClass=image ? s.api.class_from_name(image,"System","Action") : nullptr;
    void *delegateClass=image ? s.api.class_from_name(image,"System","Delegate") : nullptr;
    if(!actionClass || !delegateClass || !s.api.method(actionClass,".ctor",{"System.Object","System.IntPtr"},"System.Void") ||
       !s.api.method(actionClass,"Invoke",{},"System.Void")) return EHR_RUNTIME_TYPE_MISMATCH;
    s.methodPtrField=s.api.field(delegateClass,"method_ptr","System.IntPtr");
    s.invokeImplField=s.api.field(delegateClass,"invoke_impl","System.IntPtr");
    s.methodField=s.api.field(delegateClass,"method","System.IntPtr");
    s.methodCodeField=s.api.field(delegateClass,"method_code","System.IntPtr");
    s.targetField=s.api.field(delegateClass,"m_target","System.Object");
    s.methodInfoField=s.api.field(delegateClass,"method_info","System.Reflection.MethodInfo");
    if(!s.methodPtrField || !s.invokeImplField || !s.methodField || !s.methodCodeField || !s.targetField || !s.methodInfoField) return EHR_RUNTIME_TYPE_MISMATCH;
    size_t width=0;status=ehr_runtime_value_size(s.intPtrClass,&width);
    if(status!=EHR_RUNTIME_OK || width!=sizeof(void *)) return EHR_RUNTIME_UNSUPPORTED;
    s.metadata.methodPointer=reinterpret_cast<void *>(&callback);
    s.metadata.virtualMethodPointer=reinterpret_cast<void *>(&callback);
    s.metadata.slot=UINT16_MAX;s.metadata.parameterCount=0;
    s.ready=true;return EHR_RUNTIME_OK;
}
EHRRuntimeStatus prepareUnity() {
    auto status=prepare();if(status!=EHR_RUNTIME_OK) return status;
    auto &s=state();if(s.unityClass && s.unityInvoke) return EHR_RUNTIME_OK;
    EHRRuntimeToken klass=0,invoke=0,constructor=0;uint64_t observed=0;
    status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine.Events","UnityAction",&klass);
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_find_method(klass,"Invoke",nullptr,0,"System.Void",0,&invoke);
    const char *parameters[]={"System.Object","System.IntPtr"};
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_find_method(klass,".ctor",parameters,2,"System.Void",0,&constructor);
    // These exact entries were independently classified read-only as the same
    // two-argument self/hidden-metadata callback ABI. No target bytes are copied.
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_validate_native_method(invoke,UINT64_C(0x44d49f8),&observed);
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_validate_native_method(constructor,UINT64_C(0x44d4958),&observed);
    if(status==EHR_RUNTIME_OK) {s.unityClass=klass;s.unityInvoke=invoke;}
    return status;
}
int32_t createImpl(uint64_t source,EHRRuntimeToken *result,uint64_t *registration,EHRRuntimeToken *exception,bool unity) {
    if(!result || !registration || !exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *result=0;*registration=0;*exception=0;
    if(!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    auto &s=state();if(!source || !s.bound) return EHR_RUNTIME_BAD_ARGUMENT;
    auto status=unity ? prepareUnity() : prepare();if(status!=EHR_RUNTIME_OK) return status;
    size_t removed=0;status=EHRManagedActionSweep(&removed);if(status!=EHR_RUNTIME_OK) return status;
    auto *existing=s.entries.findSource(source);
    if(!existing && !s.entries.hasCapacity()) return EHR_RUNTIME_LIMIT;
    Owned carrier,pinnedCarrier,pointer,action,pinnedAction,reflection;
    if(existing) {
        void *target=s.api.gchandle_get_target(existing->weak);
        if(!target)return EHR_RUNTIME_INVALID_TOKEN;
        status=EHRRuntimeActionRootBorrowed(target,&carrier.value);
    } else status=ehr_runtime_construct(s.objectClass,nullptr,0,&carrier.value,exception);
    void *holder=nullptr,*delegate=nullptr,*methodObject=nullptr;
    if(status==EHR_RUNTIME_OK) status=EHRRuntimeIteratorPin(carrier.value,&pinnedCarrier.value,&holder);
    void *metadata=&s.metadata;
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_box(s.intPtrClass,&metadata,sizeof(metadata),&pointer.value);
    const EHRRuntimeToken arguments[]={carrier.value,pointer.value};
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_construct(unity ? s.unityClass : s.actionClass,arguments,2,&action.value,exception);
    if(status==EHR_RUNTIME_OK) status=EHRRuntimeIteratorPin(action.value,&pinnedAction.value,&delegate);
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_method_object(unity ? s.unityInvoke : s.invokeMethod,&reflection.value);
    if(status==EHR_RUNTIME_OK) status=EHRRuntimeIteratorBorrow(reflection.value,&methodObject);
    if(status!=EHR_RUNTIME_OK) return status;
    void *entry=reinterpret_cast<void *>(&callback);
    s.api.field_set_value(delegate,s.methodPtrField,&entry);
    s.api.field_set_value(delegate,s.invokeImplField,&entry);
    s.api.field_set_value(delegate,s.methodField,&metadata);
    s.api.field_set_value(delegate,s.methodCodeField,&holder);
    s.api.field_set_value_object(delegate,s.targetField,holder);
    s.api.field_set_value_object(delegate,s.methodInfoField,methodObject);
    uint64_t id=existing ? existing->registration:0;
    if(!existing) {
        const uint32_t weak=s.api.gchandle_new_weakref(holder,false);
        if(!weak) return EHR_RUNTIME_NOT_READY;
        id=s.entries.add(source,weak);
        if(!id) {s.api.gchandle_free(weak);return EHR_RUNTIME_LIMIT;}
    }
    *result=action.value;action.value=0;*registration=id;
    scheduleSweep();return EHR_RUNTIME_OK;
}
int32_t createFamily(uint64_t source,EHRRuntimeToken *result,uint64_t *registration,EHRRuntimeToken *exception,bool unity) noexcept {
    try {return createImpl(source,result,registration,exception,unity);}
    catch(...) {
        // No C++ exception may unwind across a NativeAOT host-table call.
        if(result && *result) {ehr_runtime_object_release(*result);*result=0;}
        if(registration && *registration) {
            auto &s=state();s.entries.close(*registration,[&](uint64_t id){return s.callbacks.forget(id);});*registration=0;
        }
        return EHR_RUNTIME_LIMIT;
    }
}
int32_t create(uint64_t source,EHRRuntimeToken *result,uint64_t *registration,EHRRuntimeToken *exception) noexcept {
    return createFamily(source,result,registration,exception,false);
}
int32_t createUnity(uint64_t source,EHRRuntimeToken *result,uint64_t *registration,EHRRuntimeToken *exception) noexcept {
    return createFamily(source,result,registration,exception,true);
}
int32_t close(uint64_t registration) {
    if(!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    auto &s=state();if(!s.bound) return EHR_RUNTIME_NOT_READY;
    return s.entries.close(registration,[&](uint64_t source){return s.callbacks.forget(source);});
}
int32_t callbackStatus(uint64_t registration,int32_t *status) {
    if(!status) return EHR_RUNTIME_BAD_ARGUMENT;*status=0;
    if(!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    const auto *entry=state().entries.find(registration);
    if(!entry) return EHR_RUNTIME_INVALID_TOKEN;*status=entry->status;return EHR_RUNTIME_OK;
}
void scheduleSweep() {
    auto &s=state();if(s.timerScheduled || !s.entries.count()) return;
    s.timerScheduled=true;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        state().timerScheduled=false;size_t removed=0;
        EHRManagedActionSweep(&removed);
        scheduleSweep();
    });
}
}
}
void EHRManagedActionMakeTable(EHRManagedActionHostV1 *table) {
    if(table) *table={1,sizeof(*table),ehr_action::create,ehr_action::close,
        [](size_t *removed)->int32_t{return EHRManagedActionSweep(removed);},ehr_action::callbackStatus,
        []()->int32_t{return NSThread.isMainThread ? 1 : 0;}};
}
void EHRManagedActionMakeFamiliesTable(EHRManagedActionFamiliesV1 *table) {
    if(table) *table={1,sizeof(*table),ehr_action::createUnity};
}
EHRRuntimeStatus EHRManagedActionSetCallbacks(const EHRManagedActionCallbacksV1 *table) {
    if(!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    if(!table || table->abi_version!=1 || table->byte_size!=sizeof(*table) || !table->invoke || !table->forget) return EHR_RUNTIME_BAD_ARGUMENT;
    auto &s=ehr_action::state();
    if(s.bound && (s.callbacks.invoke!=table->invoke || s.callbacks.forget!=table->forget)) return EHR_RUNTIME_BAD_ARGUMENT;
    s.callbacks=*table;s.bound=true;return EHR_RUNTIME_OK;
}
EHRRuntimeStatus EHRManagedActionSweep(size_t *removed) {
    if(!removed) return EHR_RUNTIME_BAD_ARGUMENT;*removed=0;
    if(!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    auto &s=ehr_action::state();if(!s.ready || !s.bound) return EHR_RUNTIME_OK;
    const auto status=ehr_runtime_initialize();if(status!=EHR_RUNTIME_OK) return status;
    *removed=s.entries.sweep([&](uint32_t weak){return s.api.gchandle_get_target(weak);},
        [&](uint32_t weak){s.api.gchandle_free(weak);},[&](uint64_t source){return s.callbacks.forget(source);});
    return EHR_RUNTIME_OK;
}
uint64_t EHRManagedActionRegistrationCount(){return NSThread.isMainThread ? ehr_action::state().entries.count() : UINT64_MAX;}
uint64_t EHRManagedActionActiveCount(){return NSThread.isMainThread ? ehr_action::state().entries.active() : UINT64_MAX;}
