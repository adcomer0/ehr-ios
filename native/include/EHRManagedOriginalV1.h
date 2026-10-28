#pragma once
#include "EHRManagedBridgeV1.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct EHRManagedOriginalProofV1 {
    uint32_t abi_version, byte_size;
    uint32_t original_request_accepted, runtime_invoke_entered;
    uint32_t permit_consumed, hook_consumptions;
} EHRManagedOriginalProofV1;

// Fixed separate extension: 40 bytes on ARM64. Core gateway ABI stays 152 bytes.
// Invoke outputs are BORROWED roots owned by the invocation pool until End.
// Retain through the existing core gateway before constructing a RuntimeObject
// or a source-visible native exception wrapper. Never release these borrowed
// tokens directly. End deterministically releases both suppressed/replaced
// exception roots and successful result roots, regardless of managed outcomes.
typedef struct EHRManagedOriginalV1 {
    uint32_t abi_version, byte_size;
    int32_t (*target_method)(uint64_t, uint64_t *);
    int32_t (*begin)(uint64_t, uint64_t, uint64_t *);
    int32_t (*invoke)(uint64_t, uint64_t, uint64_t, uint64_t,
        const EHRManagedArgumentV1 *, size_t, uint64_t *, uint64_t *,
        EHRManagedOriginalProofV1 *, size_t);
    int32_t (*end)(uint64_t);
} EHRManagedOriginalV1;

typedef struct EHRManagedOriginalSelfTestV1 {
    uint32_t abi_version, byte_size;
    int32_t pass, status, raw_original_value, repeat_status;
    int32_t scope_closed, wrong_target_status;
    EHRManagedOriginalProofV1 proof;
    uint64_t escaped_native_exception; // owned clone, or 0; native caller releases
} EHRManagedOriginalSelfTestV1;

int32_t ehr_original_bind_gateway(const EHRManagedOriginalV1 *, size_t);
int32_t ehr_original_self_test(EHRManagedOriginalSelfTestV1 *, size_t);

#ifdef __cplusplus
}
// These functions stay native; no IL2CPP pointer crosses the extension table.
void EHRManagedOriginalMakeTable(EHRManagedOriginalV1 *table) noexcept;
uint64_t EHRManagedOriginalOpenPoolCount(void) noexcept;
uint64_t EHRManagedOriginalPooledRootCount(void) noexcept;
#endif
