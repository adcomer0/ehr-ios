#pragma once
#include "EHRRuntimeGateway.h"
#include "EHRManagedPatchHostV1.h"
#include "EHRManagedPatchSignatureV1.h"
#include "EHRManagedPatchTargetsV1.h"
#include <stddef.h>
#include <stdint.h>

// Native-only descriptors. No object, class, function or frame pointer enters
// a managed table. Names are observed runtime spellings, not '+' substitutions.
struct EHRNativePatchFieldV1 {const char *name,*runtime_type;uint32_t value_offset;};
struct EHRNativePatchTypeV1 {
    const char *runtime_name;
    uint32_t kind,size,alignment,flags; // kind: void0, reference1, value2.
    // flags: references1, blittable2, Boolean4, Char8, enum16,
    // exact observed blittability32. Without32, raw scalars still require the
    // public blittability check except the exact-sized Boolean/Char allowlist.
    const char *enum_underlying;
    const EHRNativePatchFieldV1 *fields;size_t field_count;
};
struct EHRNativePatchParameterV1 {const EHRNativePatchTypeV1 *type;uint32_t flags;};
// Parameter flags match SignatureV1: value1, byref2, out4; input-only ref8.
struct EHRNativePatchInstallV1 {
    uint64_t method_rva,stub_rva,trampoline_rva,got_rva;
    uint32_t entry_branch,trampoline_bytes;
    uint8_t stub_sha256[32],trampoline_sha256[32];
};
struct EHRNativePatchSiteV1 {
    uint64_t target_id,method_rva;uint32_t metadata_token,signature_flags;
    const uint8_t *framework_uuid;const void *handler;
    const EHRNativePatchInstallV1 *install;
    const EHRNativePatchTypeV1 *owner,*result;
    const EHRNativePatchParameterV1 *parameters;size_t parameter_count;
    bool source_binding_supported;
};
struct EHRNativePatchArgumentV1 {void *input;size_t size;void *output;};
struct EHRNativePatchOutcomeV1 {
    int32_t status;bool dispatcher_entered;
    EHRRuntimeToken exception;
    EHRManagedPatchDispatchProofV2 proof;
};
// Compile-time immutable site registration, on main before binding TargetsV1.
// No site is activated by registration, preparation or Validate.
EHRRuntimeStatus EHRNativePatchRegisterCompiled(const EHRNativePatchSiteV1 *const *,size_t);
using EHRSourcePatchFailureV1=int32_t(*)(uint64_t,uint32_t *,size_t);
// Pure numeric own-image callback; no existing managed table ABI changes.
EHRRuntimeStatus EHRNativePatchBindFailureDiagnostics(EHRSourcePatchFailureV1);
EHRRuntimeStatus EHRNativeGeneratedRegisterCompiled(); // supplied by generated .inc
void EHRNativePatchMakeTargetsTable(EHRManagedPatchTargetsV1 *);
uintptr_t EHRNativePatchOriginal(const EHRNativePatchSiteV1 &);
bool EHRNativePatchShouldDispatch(const EHRNativePatchSiteV1 &);
// Frame buffers are native typed local values. Every returned token is owned;
// this helper consumes all outputs except outcome.exception, consumed by Finish.
EHRNativePatchOutcomeV1 EHRNativePatchInvokePrepared(const EHRNativePatchSiteV1 &,
    void *receiver,const EHRNativePatchArgumentV1 *,size_t,void *result,size_t);
// Call after InvokePrepared iff dispatcher_entered. Never retry original then.
// Rethrows rooted native exceptions or constructs a real native exception for
// CLR-only failure, only after all NativeAOT frames have returned.
void EHRNativePatchFinish(EHRNativePatchOutcomeV1);
// Native-only failure path for adapters outside a source dispatch. Consumes
// owned_exception and propagates it, or constructs a native fallback for a
// nonzero status. No dispatcher participation or V2 proof is manufactured.
void EHRNativeRaiseOwnedFailure(int32_t status,EHRRuntimeToken owned_exception);
// Native-only bounded adapter for a real borrowed value payload (for example
// an incoming IL2CPP value argument or a pinned object's public unbox view).
// Only this native scope sees references in the payload. Returns one new root.
EHRRuntimeStatus EHRNativePatchBoxBorrowedValue(EHRRuntimeToken,
    const EHRNativePatchTypeV1 &,void *payload,size_t,EHRRuntimeToken *owned);
#ifdef __OBJC__
@class NSDictionary;
// Isolated boxed value + owned string only; no target body or lobby operation.
NSDictionary *EHRNativePatchBoxedReferenceSelfTest(const EHRNativePatchTypeV1 &,
    const char *image,const char *name_space,const char *name,const char *reference_field);
#endif
