#pragma once
#include "EHRManagedActionV1.h"
#ifdef __cplusplus
extern "C" {
#endif
// Optional family extension; the original48-byte Action host is unchanged.
// The identical zero-argument ABI uses the same immutable callback metadata.
typedef struct EHRManagedActionFamiliesV1 {
    uint32_t abi_version,byte_size;
    int32_t (*create_unity_action)(uint64_t source,EHRRuntimeToken *owned_action,uint64_t *registration,EHRRuntimeToken *owned_exception);
} EHRManagedActionFamiliesV1;
typedef struct EHRManagedUnityActionProofV1 {
    uint32_t abi_version,byte_size,pass,status;
    uint32_t first_effects,second_effects,remove_exact_listener,proxy_dispose_preserves_listener;
    uint32_t closed_listener_noop,source_entries_after,roots_released,reserved;
} EHRManagedUnityActionProofV1;
int32_t ehr_action_bind_families(const EHRManagedActionFamiliesV1 *,size_t);
int32_t ehr_unity_action_self_test(EHRManagedUnityActionProofV1 *,size_t);
#ifdef __cplusplus
}
static_assert(sizeof(EHRManagedActionFamiliesV1)==16);
static_assert(sizeof(EHRManagedUnityActionProofV1)==48);
#endif
