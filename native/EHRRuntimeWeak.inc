#include "EHRRuntimeWeak.h"
extern "C" EHRRuntimeStatus ehr_runtime_object_weak(EHRRuntimeToken token,EHRRuntimeToken *result) {
    if(!result)return EHR_RUNTIME_BAD_ARGUMENT;*result=0;
    REQUIRE_READY();
    if(!token)return EHR_RUNTIME_BAD_ARGUMENT;
    using NewWeak=uint32_t (*)(Object *,bool);
    auto create=reinterpret_cast<NewWeak>(symbol("il2cpp_gchandle_new_weakref"));
    if(!create)return EHR_RUNTIME_UNSUPPORTED;
    Object *value=nullptr;auto status=object(token,&value);
    if(status!=EHR_RUNTIME_OK)return status;
    auto &s=state();if(s.roots.size()>=kMaxRoots)return diagnosticLimit(ehr_diagnostics::WeakRootCapacity,s.roots.size(),kMaxRoots);
    const uint32_t handle=create(value,false);if(!handle)return EHR_RUNTIME_NOT_READY;
    const auto weak=s.next++;
    try{s.roots.emplace(weak,handle);weakTokens().insert(weak);}
    catch(...){s.roots.erase(weak);weakTokens().erase(weak);s.api.gchandle_free(handle);return EHR_RUNTIME_LIMIT;}
    *result=weak;return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_object_weak_alive(EHRRuntimeToken token,int32_t *alive) {
    if(!alive)return EHR_RUNTIME_BAD_ARGUMENT;*alive=0;
    REQUIRE_READY();
    const auto found=state().roots.find(token);
    if(!weakTokens().count(token)||found==state().roots.end())return EHR_RUNTIME_INVALID_TOKEN;
    *alive=state().api.gchandle_get_target(found->second)!=nullptr;return EHR_RUNTIME_OK;
}
