#pragma once
#include "EHRManagedFacadeExtensionsV1.h"
#include "EHRManagedOriginalV1.h"
#ifdef __cplusplus
extern "C" {
#endif
// Separate extension; every existing table keeps its original layout.
typedef struct EHRManagedPatchHostV1 {
    uint32_t abi_version,byte_size;
    int32_t (*register_original)(uint64_t,uint64_t,uint64_t);
    int32_t (*begin)(uint64_t,uint64_t,uint64_t *);
    int32_t (*invoke_refs)(uint64_t,uint64_t,uint64_t,uint64_t,
        const EHRManagedArgumentV1 *,size_t,const EHRManagedByRefOutputV1 *,size_t,
        uint64_t *,uint64_t *,EHRManagedOriginalProofV1 *,size_t);
    int32_t (*end)(uint64_t);
    int32_t (*class_is_value)(uint64_t,int32_t *);
} EHRManagedPatchHostV1;
int32_t ehr_source_bind_patch_host(const EHRManagedPatchHostV1 *,size_t);
// Inputs are borrowed roots. Each nonzero output is an independent owned root.
// Ref output slots are indexed by the original parameter position; all other
// slots are zero. Native code must release/transfer every output exactly once.
int32_t ehr_source_patch_dispatch(uint64_t,uint64_t,const uint64_t *,size_t,
    uint64_t *,uint64_t *,uint64_t *,size_t);
// Independent V2 export; every existing table and the V1 dispatch stay fixed.
// Flags are initialized only after all caller spans/overlaps validate. Once
// dispatcher_entered is1, native handlers MUST NOT retry original on failure.
// Capture flags survive copyback/cleanup exceptions. Hidden native method
// context never enters this token-only ABI.
typedef struct EHRManagedPatchDispatchProofV2 {
    uint32_t abi_version,byte_size,target_found,dispatcher_entered;
    uint32_t original_attempted,runtime_entered,permit_consumed,hook_consumptions;
} EHRManagedPatchDispatchProofV2;
int32_t ehr_source_patch_dispatch_v2(uint64_t,uint64_t,const uint64_t *,size_t,
    uint64_t *,uint64_t *,uint64_t *,size_t,EHRManagedPatchDispatchProofV2 *,size_t);
// Optional independent numeric diagnostic export; no existing ABI is resized.
// Read on the same thread immediately after a failing dispatch. Exactly12words:
// version1,words12,sequenceLo/Hi,targetLo/Hi,stage,callbackIndex+1,
// argumentIndex+1,exceptionKind,status,originalEntered. Zero index means none.
// Wrong target/no current record returns NOT_FOUND3 without consuming it.
// Each new dispatch invalidates older records. No text, pointer or GC token.
int32_t ehr_source_patch_failure_v1(uint64_t,uint32_t *,size_t);
int32_t ehr_source_patch_fixture_fail_setup(uint64_t,uint64_t,uint32_t);
int32_t ehr_source_patch_fixture_setup(uint64_t,uint64_t);
int32_t ehr_source_patch_fixture_clear(void);
#ifdef __cplusplus
}
static_assert(sizeof(EHRManagedPatchDispatchProofV2)==32);
void EHRManagedPatchMakeTable(EHRManagedPatchHostV1 *);
#endif
