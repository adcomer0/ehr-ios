#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct EHRManagedPatchSignatureV1 {
    uint32_t abi_version,byte_size,parameter_count,flags;
    // flags: receiver1, result2, native-value result4.
    uint64_t method,owner_class,result_class,expected_rva;
} EHRManagedPatchSignatureV1;
typedef struct EHRManagedPatchParameterV1 {
    uint64_t value_class;
    // flags: native value1, by-reference2, out4. reserved must remain zero.
    uint32_t flags,reserved;
} EHRManagedPatchParameterV1;
// Metadata description only: count must exactly equal the prepared target's
// argument count. Both outputs require8-byte alignment and must not overlap.
// A returned declaration never establishes installed-hook availability.
int32_t ehr_source_patch_signature_v1(uint64_t,EHRManagedPatchSignatureV1 *,size_t,
    EHRManagedPatchParameterV1 *,size_t);
#ifdef __cplusplus
}
static_assert(sizeof(EHRManagedPatchSignatureV1)==48);
static_assert(sizeof(EHRManagedPatchParameterV1)==16);
#endif
