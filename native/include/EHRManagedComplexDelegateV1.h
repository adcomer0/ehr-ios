#pragma once
#include "EHRRuntimeGateway.h"
#ifdef __cplusplus
extern "C" {
#endif
// Family1: Action<reference,Int32,Int32-enum>; family2: Func<reference,Boolean>;
// family3: UnityAction<Scene,Int32-enum>. All object tokens remain opaque.
typedef struct EHRComplexDelegateHostV1 {
 uint32_t abi_version,byte_size;
 int32_t (*create)(uint64_t source,uint32_t family,const EHRRuntimeToken *type_arguments,size_t count,EHRRuntimeToken *owned_delegate,uint64_t *registration,EHRRuntimeToken *owned_exception);
 int32_t (*close)(uint64_t registration);
 int32_t (*status)(uint64_t registration,int32_t *result);
 int32_t (*is_main_thread)(void);
} EHRComplexDelegateHostV1;
typedef struct EHRComplexDelegateCallbacksV1 {
 uint32_t abi_version,byte_size;
 int32_t (*action3)(uint64_t source,EHRRuntimeToken borrowed_reference,int32_t value,EHRRuntimeToken borrowed_enum);
 int32_t (*function)(uint64_t source,EHRRuntimeToken borrowed_reference,uint8_t *result);
 int32_t (*scene2)(uint64_t source,EHRRuntimeToken borrowed_scene,EHRRuntimeToken borrowed_enum);
 int32_t (*forget)(uint64_t source);
} EHRComplexDelegateCallbacksV1;
int32_t ehr_complex_delegate_bind_gateway(const EHRComplexDelegateHostV1 *,size_t,EHRComplexDelegateCallbacksV1 *,size_t);
#ifdef __cplusplus
}
static_assert(sizeof(EHRComplexDelegateHostV1)==40);
static_assert(sizeof(EHRComplexDelegateCallbacksV1)==40);
#endif
