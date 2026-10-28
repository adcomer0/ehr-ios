#pragma once
#include "EHRRuntimeGateway.h"
#ifdef __cplusplus
extern "C" {
#endif
// Separate ABI; the core gateway is unchanged. IDs and roots, never pointers,
// cross NativeAOT. Register borrows the carrier and owns an independent pin.
typedef struct EHRManagedIteratorHostV1 {
    uint32_t abi_version, byte_size;
    int32_t (*register_carrier)(EHRRuntimeToken carrier, uint64_t source_id, uint64_t *registration);
    int32_t (*release_carrier)(uint64_t registration);
    int32_t (*object_same)(EHRRuntimeToken left, EHRRuntimeToken right, int32_t *same);
    int32_t (*object_class)(EHRRuntimeToken object, EHRRuntimeToken *klass);
} EHRManagedIteratorHostV1;
// Step returns one NEW owned current root (or null) to native on success. Native
// owns it until the next step/cancel. Every callback catches .NET exceptions.
typedef struct EHRManagedIteratorCallbacksV1 {
    uint32_t abi_version, byte_size;
    int32_t (*step)(uint64_t source_id, int32_t *has_next, EHRRuntimeToken *owned_current);
    int32_t (*reset)(uint64_t source_id);
    int32_t (*cancel)(uint64_t source_id);
} EHRManagedIteratorCallbacksV1;
typedef struct EHRManagedIteratorProofV1 {
    uint32_t abi_version, byte_size, pass, status;
    uint32_t side_effects, disposed_once, null_yield, string_yield;
    uint32_t repeated_current_identity, reset_exception, before_current_exception, after_current_exception;
    uint32_t unregistered_fallback, completed_false, registrations_closed, reserved;
} EHRManagedIteratorProofV1;
int32_t ehr_iterator_bind_gateway(const EHRManagedIteratorHostV1 *, size_t,
                                EHRManagedIteratorCallbacksV1 *, size_t);
int32_t ehr_iterator_self_test(EHRRuntimeToken carrier, EHRRuntimeToken ordinary,
                             EHRManagedIteratorProofV1 *, size_t);
#ifdef __cplusplus
}
static_assert(sizeof(EHRManagedIteratorHostV1) == 40);
static_assert(sizeof(EHRManagedIteratorCallbacksV1) == 32);
static_assert(sizeof(EHRManagedIteratorProofV1) == 64);
#endif
