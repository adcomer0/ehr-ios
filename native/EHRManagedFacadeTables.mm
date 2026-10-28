#include "EHRManagedFacadeTables.h"
#include "EHRRuntimeGateway.h"
#include "EHRRuntimeCollections.h"
#include "EHRRuntimeReflection.h"
#include "EHRRuntimeEngineColor.h"
#import "EHRNativeHooks.h"
namespace {
// Fixed adapters preserve exact C++ types on both sides of the function table.
// C# sees the documented Int32 status ABI and the same plain-data layout.
static_assert(sizeof(EHRRuntimeArgument) == sizeof(EHRManagedArgumentV1));
static_assert(alignof(EHRRuntimeArgument) == alignof(EHRManagedArgumentV1));
static_assert(sizeof(EHRRuntimeStatus) == sizeof(int32_t));
int32_t initialize() { return ehr_runtime_initialize(); }
int32_t findClass(const char *i, const char *s, const char *n, uint64_t *r) { return ehr_runtime_find_class(i,s,n,r); }
int32_t objectClass(uint64_t o, uint64_t *r) { return ehr_runtime_object_class(o,r); }
int32_t findMethod(uint64_t c, const char *n, const char *const *p, size_t count, const char *r, int s, uint64_t *out) { return ehr_runtime_find_method(c,n,p,count,r,s,out); }
int32_t findField(uint64_t c, const char *n, const char *t, int s, uint64_t *r) { return ehr_runtime_find_field(c,n,t,s,r); }
EHRRuntimeArgument convert(const EHRManagedArgumentV1 &a) { return {a.kind,a.reserved,a.token,a.bytes,a.byte_count}; }
int32_t invoke(uint64_t m, uint64_t o, const EHRManagedArgumentV1 *a, size_t count, uint64_t *r, uint64_t *e) {
    if (count > 128 || (count && !a)) return EHR_RUNTIME_BAD_ARGUMENT;
    EHRRuntimeArgument converted[128];
    for (size_t i=0; i<count; ++i) converted[i]=convert(a[i]);
    return ehr_runtime_invoke(m,o,count ? converted : nullptr,count,r,e);
}
int32_t readField(uint64_t f, uint64_t o, uint64_t *r) { return ehr_runtime_read_field(f,o,r); }
int32_t writeField(uint64_t f, uint64_t o, const EHRManagedArgumentV1 *a) {
    if (!a) return EHR_RUNTIME_BAD_ARGUMENT;
    const auto converted=convert(*a);
    return ehr_runtime_write_field(f,o,&converted);
}
int32_t valueSize(uint64_t c, size_t *s) { return ehr_runtime_value_size(c,s); }
int32_t box(uint64_t c, const void *b, size_t n, uint64_t *r) { return ehr_runtime_box(c,b,n,r); }
int32_t copyValue(uint64_t o, void *b, size_t n, size_t *s) { return ehr_runtime_copy_value(o,b,n,s); }
int32_t stringCreate(const uint16_t *u, size_t n, uint64_t *r) { return ehr_runtime_string_create(u,n,r); }
int32_t stringCopy(uint64_t o, uint16_t *u, size_t n, size_t *l) { return ehr_runtime_string_copy(o,u,n,l); }
int32_t release(uint64_t o) { return ehr_runtime_object_release(o); }
int32_t retain(uint64_t o, uint64_t *r) { return ehr_runtime_object_retain(o,r); }
uint64_t callbackCount() { return [EHRNativeHooksCopyStatus()[@"broadcastVersionCallbacks"] unsignedLongLongValue]; }
int32_t imageObserved() { return [EHRNativeHooksCopyStatus()[@"pinnedImageObserved"] boolValue] ? 1 : 0; }
int32_t invokeRefs(uint64_t m, uint64_t o, const EHRManagedArgumentV1 *a, size_t count,
    const EHRManagedByRefOutputV1 *outputs, size_t outputCount, uint64_t *r, uint64_t *e) {
    if (count > 128 || outputCount > 128 || (count && !a) || (outputCount && !outputs)) return EHR_RUNTIME_BAD_ARGUMENT;
    EHRRuntimeArgument converted[128];
    EHRRuntimeByRefOutput convertedOutputs[128];
    for (size_t i=0; i<count; ++i) converted[i]=convert(a[i]);
    for (size_t i=0; i<outputCount; ++i) {
        const auto &v=outputs[i];
        convertedOutputs[i]={v.argument_index,v.reserved,v.value_class,v.bytes,v.byte_count};
    }
    return ehr_runtime_invoke_with_refs(m,o,count ? converted : nullptr,count,
        outputCount ? convertedOutputs : nullptr,outputCount,r,e);
}
int32_t classTypeObject(uint64_t c, uint64_t *r) { return ehr_runtime_class_type_object(c,r); }
int32_t arrayCreate(uint64_t c, int32_t n, uint64_t *r, uint64_t *e) { return ehr_runtime_array_create(c,n,r,e); }
int32_t arrayLength(uint64_t a, int32_t *n, uint64_t *e) { return ehr_runtime_array_length(a,n,e); }
int32_t arrayGet(uint64_t a, int32_t i, uint64_t *r, uint64_t *e) { return ehr_runtime_array_get(a,i,r,e); }
int32_t arraySet(uint64_t a, int32_t i, uint64_t v, uint64_t *e) { return ehr_runtime_array_set(a,i,v,e); }
int32_t classFromTypeObject(uint64_t t, uint64_t *r) { return ehr_runtime_class_from_type_object(t,r); }
int32_t makeGenericClass(uint64_t c, const uint64_t *a, size_t n, uint64_t *r, uint64_t *e) { return ehr_runtime_make_generic_class(c,a,n,r,e); }
int32_t construct(uint64_t c, const uint64_t *a, size_t n, uint64_t *r, uint64_t *e) { return ehr_runtime_construct(c,a,n,r,e); }
int32_t initializeClass(uint64_t c, uint64_t *e) { return ehr_runtime_initialize_class(c,e); }
int32_t objectSame(uint64_t a, uint64_t b, int32_t *r) { return ehr_runtime_object_same(a,b,r); }
int32_t identityHash(uint64_t a, int32_t *h, uint64_t *e) { return ehr_runtime_object_identity_hash(a,h,e); }
int32_t releaseDeferred(uint64_t a) { return ehr_runtime_object_release_deferred(a); }
int32_t drainDeferred(size_t *n) { return ehr_runtime_drain_deferred_releases(n); }

int32_t classTypeName(uint64_t c,char *s,size_t n,size_t *r) { return ehr_runtime_class_type_name(c,s,n,r); }
int32_t vectorClass(uint64_t c,uint64_t *r) { return ehr_runtime_vector_class(c,r); }

int32_t methodObject(uint64_t m,uint64_t *r) { return ehr_runtime_method_object(m,r); }
int32_t methodFromObject(uint64_t m,uint64_t *r) { return ehr_runtime_method_from_object(m,r); }
int32_t makeGenericMethod(uint64_t m,const uint64_t *a,size_t n,uint64_t *r,uint64_t *e) { return ehr_runtime_make_generic_method(m,a,n,r,e); }
int32_t parseHtmlColor(uint64_t text,int32_t *parsed,uint32_t *rgba) { return ehr_runtime_color_parse_html(text,parsed,rgba); }

}
void EHRManagedFacadeMakeTables(EHRManagedFacadeTables *out) {
    if(!out)return;
    *out={
        {1,sizeof(EHRManagedGatewayV1),ehr_runtime_abi_version,initialize,findClass,objectClass,findMethod,findField,invoke,readField,writeField,valueSize,box,copyValue,stringCreate,stringCopy,release,retain,callbackCount,imageObserved},
        {1,sizeof(EHRManagedFacadeExtensionsV1),invokeRefs,classTypeObject,arrayCreate,arrayLength,arrayGet,arraySet},
        {1,sizeof(EHRManagedReflectionV1),classFromTypeObject,makeGenericClass,construct,initializeClass},
        {1,sizeof(EHRManagedLifetimeV1),objectSame,identityHash,releaseDeferred,drainDeferred},
        {1,sizeof(EHRManagedTypeNamesV1),classTypeName,vectorClass},
        {1,sizeof(EHRManagedMethodsV1),methodObject,methodFromObject,makeGenericMethod},
        {1,sizeof(EHRManagedEngineColorV1),parseHtmlColor}
    };
}
