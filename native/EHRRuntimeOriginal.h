#pragma once
#include "EHRRuntimeGateway.h"

#ifdef __cplusplus
extern "C" {
#endif

// A native compiled route ID is not a method pointer or a gateway object token.
// Additional routes require exact typed native thunks and explicit registration.
#define EHR_ORIGINAL_TARGET_BROADCAST_VERSION UINT64_C(1)
#define EHR_ORIGINAL_TARGET_IS_VERSION_MODDED UINT64_C(2)
typedef uint64_t EHROriginalInvocationToken;

typedef struct EHROriginalInvocationProofV1 {
    uint32_t abi_version;
    uint32_t byte_size;
    uint32_t original_request_accepted;
    uint32_t runtime_invoke_entered;
    uint32_t permit_consumed;
    uint32_t hook_consumptions;
} EHROriginalInvocationProofV1;

// Resolves the compiled exact target against actual IL2CPP metadata. Success
// proves metadata identity only; it does not claim that an interceptor ran.
EHRRuntimeStatus ehr_runtime_original_target_method(uint64_t target_id,
                                                   EHRRuntimeToken *method);
// Registers an ordinary method only after full pinned native association.
// Exact duplicate registrations are idempotent. IDs and methods cannot be
// rebound or aliased; an interceptor must consume this same route's permit.
// The registration itself does not establish that its interceptor is installed.
EHRRuntimeStatus ehr_runtime_original_register(uint64_t target_id,
    EHRRuntimeToken exact_method, uint64_t expected_native_rva);
// Invocation capabilities are single-use and Unity-main-thread-only. They own
// no managed objects. Caller-owned argument/receiver roots must outlive invoke.
EHRRuntimeStatus ehr_runtime_original_begin(uint64_t target_id,
    EHRRuntimeToken exact_method, EHROriginalInvocationToken *invocation);
EHRRuntimeStatus ehr_runtime_original_end(EHROriginalInvocationToken invocation);

// General ordinary-argument ABI. No byref conversion is inferred. target_id, exact_method
// and invocation must all identify the same registered route. A foreign/invalid
// pair never enters runtime_invoke and does not consume the capability.
//
// A validated request consumes the capability even if argument preflight fails.
// The bypass permit exists only immediately around caught runtime_invoke, after
// its argument/receiver preflight. A successful result requires hook consumption.
// An unconsumed normal return becomes UNSUPPORTED with no result root. A caught
// exception still returns MANAGED_EXCEPTION and its owned root; the proof makes
// clear whether the method hook was entered. Every nonzero output object token
// must be released exactly once, as in EHRRuntimeGateway.h. Nothing is thrown
// across this C ABI. Native rethrow must occur after a NativeAOT caller returns.
EHRRuntimeStatus ehr_runtime_invoke_original(EHROriginalInvocationToken invocation,
    uint64_t target_id, EHRRuntimeToken exact_method, EHRRuntimeToken instance,
    const EHRRuntimeArgument *arguments, size_t argument_count,
    EHRRuntimeToken *result, EHRRuntimeToken *exception,
    EHROriginalInvocationProofV1 *proof, size_t proof_byte_size);
// Same one-shot route/exception semantics with the gateway's explicit, typed
// scalar value ref/out buffers. General byref references remain unsupported.
EHRRuntimeStatus ehr_runtime_invoke_original_with_refs(EHROriginalInvocationToken invocation,
    uint64_t target_id, EHRRuntimeToken exact_method, EHRRuntimeToken instance,
    const EHRRuntimeArgument *arguments, size_t argument_count,
    const EHRRuntimeByRefOutput *outputs, size_t output_count,
    EHRRuntimeToken *result, EHRRuntimeToken *exception,
    EHROriginalInvocationProofV1 *proof, size_t proof_byte_size);

#ifdef __cplusplus
}
// Native-only hook entry: raw IL2CPP MethodInfo is never exposed through the
// token-only managed gateway. Consume before calling the signed trampoline.
bool EHRTryConsumeOriginalInvocation(uint64_t target_id, const void *method) noexcept;
uint64_t EHROriginalInvocationBypassCount(void) noexcept;
#endif

#ifdef __OBJC__
#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EHRRuntimeOriginalSelfTest(void);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EHRRuntimeOriginalRegisteredSelfTest(void);
#endif
