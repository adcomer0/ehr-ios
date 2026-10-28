#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// Validate checks compiled/installed entry identity, runtime method association
// and ABI without activating a handler. Activate publishes one fully validated
// set atomically. Every failure leaves all source handlers inactive.
typedef struct EHRManagedPatchTargetsV1 {
    uint32_t abi_version,byte_size;
    int32_t (*validate)(uint64_t target_id);
    int32_t (*activate)(const uint64_t *target_ids,size_t count);
    int32_t (*deactivate)(void);
} EHRManagedPatchTargetsV1;
int32_t ehr_source_bind_patch_targets_v1(const EHRManagedPatchTargetsV1 *,size_t);
#ifdef __cplusplus
}
static_assert(sizeof(EHRManagedPatchTargetsV1)==32);
#endif
