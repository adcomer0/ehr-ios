#pragma once
#include "EHRRuntimeGateway.h"
#ifdef __cplusplus
extern "C" {
#endif
// Separate ABI. Object/metadata pointers stay entirely inside native code.
// Create returns one NEW caller-owned real Action root and a registration ID.
// Close immediately forgets the source callback; retained native Actions then
// safely no-op. The weak native carrier entry survives until a main-thread
// sweep observes collection. All operations require the Unity main thread.
typedef struct EHRManagedActionHostV1 {
    uint32_t abi_version, byte_size;
    int32_t (*create)(uint64_t source, EHRRuntimeToken *owned_action, uint64_t *registration, EHRRuntimeToken *owned_exception);
    int32_t (*close)(uint64_t registration);
    int32_t (*sweep)(size_t *removed);
    int32_t (*callback_status)(uint64_t registration, int32_t *status);
    int32_t (*is_main_thread)(void);
} EHRManagedActionHostV1;
typedef struct EHRManagedActionCallbacksV1 {
    uint32_t abi_version, byte_size;
    int32_t (*invoke)(uint64_t source);
    int32_t (*forget)(uint64_t source);
} EHRManagedActionCallbacksV1;
typedef struct EHRManagedActionProofV1 {
    uint32_t abi_version, byte_size, pass, status;
    uint32_t source_effects, callback_exception_contained, closed_late_invoke_noop, source_entries_after;
    uint32_t callback_success_status, callback_error_status, roots_released, proxy_dispose_preserves_native;
} EHRManagedActionProofV1;
int32_t ehr_action_bind_gateway(const EHRManagedActionHostV1 *,size_t,EHRManagedActionCallbacksV1 *,size_t);
int32_t ehr_action_self_test(EHRManagedActionProofV1 *,size_t);
#ifdef __cplusplus
}
static_assert(sizeof(EHRManagedActionHostV1)==48);
static_assert(sizeof(EHRManagedActionCallbacksV1)==24);
static_assert(sizeof(EHRManagedActionProofV1)==48);
#endif
