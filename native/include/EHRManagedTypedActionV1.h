#pragma once
#include "EHRRuntimeGateway.h"
#ifdef __cplusplus
extern "C" {
#endif
// Exact verified ABIs only; all ids/classes/objects are opaque gateway tokens.
enum EHRActionArgumentABI { EHR_ACTION_I32=1,EHR_ACTION_U8=2,EHR_ACTION_F32=3,EHR_ACTION_REFERENCE=4 };
typedef struct EHRManagedTypedActionHostV1 {
    uint32_t abi_version,byte_size;
    int32_t (*create)(uint64_t source,EHRRuntimeToken argument_class,uint32_t argument_abi,EHRRuntimeToken *owned_action,uint64_t *registration,EHRRuntimeToken *owned_exception);
    int32_t (*close)(uint64_t registration);
    int32_t (*callback_status)(uint64_t registration,int32_t *status);
    int32_t (*is_main_thread)(void);
} EHRManagedTypedActionHostV1;
typedef struct EHRManagedTypedActionCallbacksV1 {
    uint32_t abi_version,byte_size;
    int32_t (*invoke_i32)(uint64_t source,int32_t value);
    int32_t (*invoke_u8)(uint64_t source,uint8_t value);
    int32_t (*invoke_f32)(uint64_t source,float value);
    // Borrowed root exists until callback return; retain before it can escape.
    int32_t (*invoke_reference)(uint64_t source,EHRRuntimeToken borrowed_value);
    int32_t (*forget)(uint64_t source);
} EHRManagedTypedActionCallbacksV1;
typedef struct EHRManagedTypedActionProofV1 {
    uint32_t abi_version,byte_size,pass,status;
    uint32_t int32_exact,byte_exact,float_exact,reference_identity;
    uint32_t option_null,gameobject_null,exception_contained,proxy_dispose_preserves_native;
    uint32_t close_late_noop,combine_remove,source_entries_after,roots_released;
    uint32_t case_id,lookup_step,reserved0,reserved1;
} EHRManagedTypedActionProofV1;
int32_t ehr_typed_action_bind_gateway(const EHRManagedTypedActionHostV1 *,size_t,EHRManagedTypedActionCallbacksV1 *,size_t);
int32_t ehr_typed_action_self_test(EHRManagedTypedActionProofV1 *,size_t);
#ifdef __cplusplus
}
static_assert(sizeof(EHRManagedTypedActionHostV1)==40);
static_assert(sizeof(EHRManagedTypedActionCallbacksV1)==48);
static_assert(sizeof(EHRManagedTypedActionProofV1)==80);
#endif
