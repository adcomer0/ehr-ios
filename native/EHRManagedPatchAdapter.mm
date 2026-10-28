#include "EHRManagedPatchHostV1.h"
#include "EHRRuntimeOriginal.h"
#include "EHRRuntimeReflection.h"
#include "EHRRuntimeIteratorPrivate.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <cstring>

static_assert(sizeof(EHRManagedPatchHostV1)==48);
namespace {
void *runtimeSymbol(const char *name) {
    if(void *value=dlsym(RTLD_DEFAULT,name))return value;
    for(uint32_t i=0;i<_dyld_image_count();++i){
        const char *path=_dyld_get_image_name(i);
        if(!path||!strstr(path,"/UnityFramework.framework/UnityFramework"))continue;
        void *handle=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);if(!handle)continue;
        void *value=dlsym(handle,name);dlclose(handle);if(value)return value;
    }
    return nullptr;
}
int32_t registerOriginal(uint64_t target,uint64_t method,uint64_t rva) {
    if(target!=EHR_ORIGINAL_TARGET_BROADCAST_VERSION)
        return ehr_runtime_original_register(target,method,rva);
    uint64_t exact=0,observed=0;
    auto status=ehr_runtime_original_target_method(target,&exact);
    if(status!=EHR_RUNTIME_OK)return status;
    if(method!=exact)return EHR_RUNTIME_TYPE_MISMATCH;
    return ehr_runtime_validate_native_method(method,rva,&observed);
}
int32_t begin(uint64_t target,uint64_t method,uint64_t *invocation) {
    return ehr_runtime_original_begin(target,method,invocation);
}
int32_t end(uint64_t invocation) {return ehr_runtime_original_end(invocation);}
int32_t invoke(uint64_t invocation,uint64_t target,uint64_t method,uint64_t receiver,
    const EHRManagedArgumentV1 *arguments,size_t count,const EHRManagedByRefOutputV1 *outputs,size_t outputCount,
    uint64_t *result,uint64_t *exception,EHRManagedOriginalProofV1 *proof,size_t proofSize) {
    if(!result||!exception||!proof||proofSize!=sizeof(*proof)||count>128||outputCount>128||
        (count&&!arguments)||(outputCount&&!outputs))return EHR_RUNTIME_BAD_ARGUMENT;
    EHRRuntimeArgument native[128];EHRRuntimeByRefOutput refs[128];
    for(size_t i=0;i<count;++i){const auto &a=arguments[i];native[i]={a.kind,a.reserved,a.token,a.bytes,a.byte_count};}
    for(size_t i=0;i<outputCount;++i){const auto &r=outputs[i];refs[i]={r.argument_index,r.reserved,r.value_class,r.bytes,r.byte_count};}
    EHROriginalInvocationProofV1 nativeProof{};
    auto status=ehr_runtime_invoke_original_with_refs(invocation,target,method,receiver,count?native:nullptr,count,
        outputCount?refs:nullptr,outputCount,result,exception,&nativeProof,sizeof(nativeProof));
    *proof={nativeProof.abi_version,nativeProof.byte_size,nativeProof.original_request_accepted,
        nativeProof.runtime_invoke_entered,nativeProof.permit_consumed,nativeProof.hook_consumptions};
    return status;
}
int32_t classIsValue(uint64_t klass,int32_t *result) {
    if(!result)return EHR_RUNTIME_BAD_ARGUMENT;*result=0;
    // Round trip the opaque metadata token through a genuine System.Type. No
    // class pointer or guessed layout is exposed to the managed function table.
    uint64_t root=0;auto status=ehr_runtime_class_type_object(klass,&root);
    if(status!=EHR_RUNTIME_OK)return status;
    struct Release {uint64_t token;~Release(){ehr_runtime_object_release(token);}} release{root};
    void *type=nullptr;status=EHRRuntimeIteratorBorrow(root,&type);
    if(status!=EHR_RUNTIME_OK)return status;
    auto fromType=reinterpret_cast<void *(*)(void *)>(runtimeSymbol("il2cpp_class_from_system_type"));
    auto isValue=reinterpret_cast<bool (*)(const void *)>(runtimeSymbol("il2cpp_class_is_valuetype"));
    if(!fromType||!isValue)return EHR_RUNTIME_NOT_FOUND;
    void *native=fromType(type);if(!native)return EHR_RUNTIME_TYPE_MISMATCH;
    *result=isValue(native)?1:0;return EHR_RUNTIME_OK;
}
}
void EHRManagedPatchMakeTable(EHRManagedPatchHostV1 *table) {
    if(table)*table={1,sizeof(*table),registerOriginal,begin,invoke,end,classIsValue};
}
