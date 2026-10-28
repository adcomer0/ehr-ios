#import "EHRRuntimeOriginal.h"
#import "EHRNativeHooks.h"
#if __has_include("EHRHookBinding.generated.h")
#include "EHRHookBinding.generated.h"
#endif

namespace {
struct InvocationLease {
    EHROriginalInvocationToken token = 0;
    ~InvocationLease() { if (token) ehr_runtime_original_end(token); }
};
struct RootLease {
    EHRRuntimeToken token = 0;
    ~RootLease() { if (token) ehr_runtime_object_release(token); }
};
uint64_t counter(NSDictionary *status, NSString *key) {
    id value = status[key];
    return [value respondsToSelector:@selector(unsignedLongLongValue)] ? [value unsignedLongLongValue] : 0;
}
NSDictionary *proofDictionary(const EHROriginalInvocationProofV1 &proof) {
    return @{ @"requestAccepted": @(proof.original_request_accepted),
        @"runtimeInvokeEntered": @(proof.runtime_invoke_entered), @"permitConsumed": @(proof.permit_consumed),
        @"hookConsumptions": @(proof.hook_consumptions) };
}
}

NSDictionary<NSString *, id> *EHRRuntimeOriginalSelfTest(void) {
    if (!NSThread.isMainThread) return @{ @"success": @NO, @"status": @(EHR_RUNTIME_WRONG_THREAD) };
    const uint64_t target = EHR_ORIGINAL_TARGET_BROADCAST_VERSION;
    EHRRuntimeToken method = 0, constants = 0, foreign = 0;
    auto status = ehr_runtime_original_target_method(target, &method);
    if (status != EHR_RUNTIME_OK) return @{ @"success": @NO, @"resolveStatus": @(status) };
    status = ehr_runtime_find_class("Assembly-CSharp.dll", "", "Constants", &constants);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_method(constants, "IsVersionModded", nullptr, 0, "System.Boolean", 1, &foreign);
    if (status != EHR_RUNTIME_OK || method == foreign) return @{ @"success": @NO, @"foreignMethodResolveStatus": @(status) };

    // Warm the exact class with the ordinary caught getter before measuring
    // bypass deltas. Class-initializer work belongs to setup, not its proof.
    RootLease warmed, warmException;
    status = ehr_runtime_invoke(method, 0, nullptr, 0, &warmed.token, &warmException.token);
    if (status != EHR_RUNTIME_OK || !warmed.token) return @{ @"success": @NO, @"warmGetterStatus": @(status) };

    InvocationLease invocation;
    status = ehr_runtime_original_begin(target, method, &invocation.token);
    if (status != EHR_RUNTIME_OK) return @{ @"success": @NO, @"beginStatus": @(status) };
    EHROriginalInvocationToken rejected = 0;
    const auto unknownBegin = ehr_runtime_original_begin(UINT64_MAX, method, &rejected);
    const bool unknownDidNotOpen = rejected == 0;
    const auto foreignBegin = ehr_runtime_original_begin(target, foreign, &rejected);
    const bool foreignDidNotOpen = rejected == 0;

    NSDictionary *before = EHRNativeHooksCopyStatus();
    const uint64_t bypassBefore = EHROriginalInvocationBypassCount();
    RootLease returned, raised;
    EHROriginalInvocationProofV1 wrongTarget{}, wrongMethod{}, actual{}, repeated{};
    const auto wrongTargetStatus = ehr_runtime_invoke_original(invocation.token, UINT64_MAX, method, 0, nullptr, 0,
        &returned.token, &raised.token, &wrongTarget, sizeof(wrongTarget));
    const auto wrongMethodStatus = ehr_runtime_invoke_original(invocation.token, target, foreign, 0, nullptr, 0,
        &returned.token, &raised.token, &wrongMethod, sizeof(wrongMethod));
    const auto actualStatus = ehr_runtime_invoke_original(invocation.token, target, method, 0, nullptr, 0,
        &returned.token, &raised.token, &actual, sizeof(actual));
    int32_t rawValue = -1;
    size_t copied = 0;
    const auto copyStatus = returned.token ? ehr_runtime_copy_value(returned.token, &rawValue, sizeof(rawValue), &copied) : EHR_RUNTIME_NOT_FOUND;
    // Keep the first roots separately: repeat rejection must not overwrite and
    // silently discard an earlier caller-owned successful result.
    RootLease repeatedResult, repeatedException;
    const auto repeatStatus = ehr_runtime_invoke_original(invocation.token, target, method, 0, nullptr, 0,
        &repeatedResult.token, &repeatedException.token, &repeated, sizeof(repeated));
    NSDictionary *after = EHRNativeHooksCopyStatus();
    const uint64_t bypassDelta = EHROriginalInvocationBypassCount() - bypassBefore;
    const uint64_t versionDelta = counter(after, @"broadcastVersionCallbacks") - counter(before, @"broadcastVersionCallbacks");
    const uint64_t postfixDelta = counter(after, @"managedVersionPostfixCalls") - counter(before, @"managedVersionPostfixCalls");
    const uint64_t moddedDelta = counter(after, @"moddedBroadcastVersions") - counter(before, @"moddedBroadcastVersions");
    const bool rejectedWithoutEntry = unknownBegin == EHR_RUNTIME_NOT_FOUND && unknownDidNotOpen &&
        foreignBegin == EHR_RUNTIME_TYPE_MISMATCH && foreignDidNotOpen &&
        wrongTargetStatus == EHR_RUNTIME_TYPE_MISMATCH && wrongMethodStatus == EHR_RUNTIME_TYPE_MISMATCH &&
        !wrongTarget.original_request_accepted && !wrongTarget.runtime_invoke_entered && !wrongTarget.permit_consumed &&
        !wrongMethod.original_request_accepted && !wrongMethod.runtime_invoke_entered && !wrongMethod.permit_consumed;
    const bool passed = rejectedWithoutEntry && actualStatus == EHR_RUNTIME_OK && actual.original_request_accepted == 1 &&
        actual.runtime_invoke_entered == 1 && actual.permit_consumed == 1 && actual.hook_consumptions == 1 &&
        copyStatus == EHR_RUNTIME_OK && copied == sizeof(rawValue) && rawValue >= 0 && raised.token == 0 &&
        repeatStatus == EHR_RUNTIME_BAD_ARGUMENT && !repeated.original_request_accepted && !repeated.runtime_invoke_entered &&
        bypassDelta == 1 && versionDelta == 0 && postfixDelta == 0 && moddedDelta == 0;
    return @{ @"success": @(passed), @"actualStatus": @(actualStatus), @"copyStatus": @(copyStatus),
        @"rawOriginalValue": @(rawValue), @"proof": proofDictionary(actual),
        @"invalidTargetBeginStatus": @(unknownBegin), @"foreignMethodBeginStatus": @(foreignBegin),
        @"invalidTargetInvokeStatus": @(wrongTargetStatus), @"foreignMethodInvokeStatus": @(wrongMethodStatus),
        @"invalidTargetProof": proofDictionary(wrongTarget), @"foreignMethodProof": proofDictionary(wrongMethod),
        @"repeatStatus": @(repeatStatus), @"repeatProof": proofDictionary(repeated),
        @"originalBypassDelta": @(bypassDelta), @"normalVersionCallbackDelta": @(versionDelta),
        @"managedVersionPostfixDelta": @(postfixDelta), @"moddedVersionDelta": @(moddedDelta),
        @"nativePointersExposed": @NO, @"gameplayMutationPerformed": @NO, @"fullEHRAvailable": @NO };
}

NSDictionary<NSString *, id> *EHRRuntimeOriginalRegisteredSelfTest(void) {
#if EHR_HAS_IS_MODDED_HOOK
    if (!NSThread.isMainThread) return @{ @"success": @NO, @"status": @(EHR_RUNTIME_WRONG_THREAD) };
    EHRRuntimeToken constants=0,method=0;
    auto status=ehr_runtime_find_class("Assembly-CSharp.dll","","Constants",&constants);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(constants,"IsVersionModded",nullptr,0,"System.Boolean",1,&method);
    if(status!=EHR_RUNTIME_OK)return @{@"success":@NO,@"resolveStatus":@(status)};
    const uint64_t target=EHR_ORIGINAL_TARGET_IS_VERSION_MODDED;
    const auto wrongRVA=ehr_runtime_original_register(target,method,EHRIsModdedMethodRVA+4);
    const auto registration=ehr_runtime_original_register(target,method,EHRIsModdedMethodRVA);
    const auto repeat=ehr_runtime_original_register(target,method,EHRIsModdedMethodRVA);
    const auto alias=ehr_runtime_original_register(target+1,method,EHRIsModdedMethodRVA);
    EHRRuntimeToken bound=0;
    const auto lookupStatus=ehr_runtime_original_target_method(target,&bound);
    if(registration!=EHR_RUNTIME_OK || lookupStatus!=EHR_RUNTIME_OK || bound!=method)
        return @{@"success":@NO,@"registerStatus":@(registration),@"lookupStatus":@(lookupStatus)};
    bool passed=wrongRVA==EHR_RUNTIME_TYPE_MISMATCH && repeat==EHR_RUNTIME_OK && alias==EHR_RUNTIME_TYPE_MISMATCH;
    NSMutableArray *calls=[NSMutableArray array];
    for(int explicitRefs=0;explicitRefs<2;++explicitRefs){
        InvocationLease invocation;RootLease returned,raised;
        const auto begin=ehr_runtime_original_begin(target,method,&invocation.token);
        EHROriginalInvocationProofV1 proof{};
        const uint64_t before=EHROriginalInvocationBypassCount();
        const auto invoked=begin!=EHR_RUNTIME_OK?begin:explicitRefs?
            ehr_runtime_invoke_original_with_refs(invocation.token,target,method,0,nullptr,0,nullptr,0,&returned.token,&raised.token,&proof,sizeof(proof)):
            ehr_runtime_invoke_original(invocation.token,target,method,0,nullptr,0,&returned.token,&raised.token,&proof,sizeof(proof));
        uint8_t value=255;size_t copied=0;
        const auto copy=returned.token?ehr_runtime_copy_value(returned.token,&value,sizeof(value),&copied):EHR_RUNTIME_NOT_FOUND;
        const uint64_t delta=EHROriginalInvocationBypassCount()-before;
        const bool okay=invoked==EHR_RUNTIME_OK && !raised.token && copy==EHR_RUNTIME_OK && copied==1 && value<=1 &&
            proof.original_request_accepted==1 && proof.runtime_invoke_entered==1 && proof.permit_consumed==1 && proof.hook_consumptions==1 && delta==1;
        passed=passed&&okay;
        [calls addObject:@{@"success":@(okay),@"status":@(invoked),@"explicitRefEntry":@(explicitRefs!=0),@"scalarRefOutputsExercised":@NO,@"originalValue":@(value),@"bypassDelta":@(delta),@"proof":proofDictionary(proof)}];
    }
    return @{@"success":@(passed),@"registerStatus":@(registration),@"duplicateStatus":@(repeat),@"wrongRVAStatus":@(wrongRVA),@"aliasStatus":@(alias),@"calls":calls,@"gameplayMutationPerformed":@NO};
#else
    return @{@"success":@YES,@"enabled":@NO};
#endif
}
