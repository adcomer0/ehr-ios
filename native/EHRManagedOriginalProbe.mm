#import "EHRManagedOriginalProbe.h"
#import "EHRNativeHooks.h"
#include "EHRManagedOriginalV1.h"
#include "EHRRuntimeGateway.h"

NSDictionary<NSString *, id> *EHRManagedOriginalAotSelfTest(void) {
#if EHR_HAS_MANAGED_RULES
    if (!NSThread.isMainThread) return @{ @"success": @NO, @"status": @(EHR_RUNTIME_WRONG_THREAD) };
    EHRManagedOriginalV1 table{};
    EHRManagedOriginalMakeTable(&table);
    const int32_t bound = ehr_original_bind_gateway(&table, sizeof(table));
    if (bound != 0) return @{ @"success": @NO, @"bindStatus": @(bound) };
    const uint64_t poolsBefore = EHRManagedOriginalOpenPoolCount(), rootsBefore = EHRManagedOriginalPooledRootCount();
    NSDictionary *before = EHRNativeHooksCopyStatus();
    EHRManagedOriginalSelfTestV1 result{};
    const int32_t status = ehr_original_self_test(&result, sizeof(result));
    NSDictionary *after = EHRNativeHooksCopyStatus();
    // This release occurs after the NativeAOT export returned. A real native
    // dispatch thunk could instead rethrow this exact native exception then.
    const bool escaped = result.escaped_native_exception != 0;
    const auto exceptionRelease = escaped ? ehr_runtime_object_release(result.escaped_native_exception) : EHR_RUNTIME_OK;
    const uint64_t poolsAfter = EHRManagedOriginalOpenPoolCount(), rootsAfter = EHRManagedOriginalPooledRootCount();
    const uint64_t bypassDelta = [after[@"broadcastOriginalBypasses"] unsignedLongLongValue] - [before[@"broadcastOriginalBypasses"] unsignedLongLongValue];
    const uint64_t normalDelta = [after[@"broadcastVersionCallbacks"] unsignedLongLongValue] - [before[@"broadcastVersionCallbacks"] unsignedLongLongValue];
    const uint64_t postfixDelta = [after[@"managedVersionPostfixCalls"] unsignedLongLongValue] - [before[@"managedVersionPostfixCalls"] unsignedLongLongValue];
    const bool passed = status == 0 && result.abi_version == 1 && result.byte_size == sizeof(result) &&
        result.proof.abi_version == 1 && result.proof.byte_size == sizeof(result.proof) &&
        result.pass == 1 && result.status == 0 && result.scope_closed == 1 && result.proof.original_request_accepted == 1 &&
        result.wrong_target_status == EHR_RUNTIME_TYPE_MISMATCH && result.repeat_status == EHR_RUNTIME_BAD_ARGUMENT &&
        result.proof.runtime_invoke_entered == 1 && result.proof.permit_consumed == 1 && result.proof.hook_consumptions == 1 &&
        bypassDelta == 1 && normalDelta == 0 && postfixDelta == 0 && poolsAfter == poolsBefore && rootsAfter == rootsBefore &&
        !escaped && exceptionRelease == EHR_RUNTIME_OK;
    return @{ @"success": @(passed), @"status": @(status), @"bindStatus": @(bound),
        @"coreTableBytes": @(sizeof(EHRManagedGatewayV1)), @"originalTableBytes": @(sizeof(table)),
        @"rawOriginalValue": @(result.raw_original_value), @"scopeClosed": @(result.scope_closed),
        @"wrongTargetStatus": @(result.wrong_target_status), @"repeatStatus": @(result.repeat_status),
        @"requestAccepted": @(result.proof.original_request_accepted), @"runtimeInvokeEntered": @(result.proof.runtime_invoke_entered),
        @"permitConsumed": @(result.proof.permit_consumed), @"hookConsumptions": @(result.proof.hook_consumptions),
        @"originalBypassDelta": @(bypassDelta), @"normalVersionCallbackDelta": @(normalDelta), @"managedPostfixDelta": @(postfixDelta),
        @"poolsBefore": @(poolsBefore), @"poolsAfter": @(poolsAfter), @"poolRootsBefore": @(rootsBefore), @"poolRootsAfter": @(rootsAfter),
        @"nativeExceptionReturnedAfterAot": @(escaped), @"exceptionRootReleaseStatus": @(exceptionRelease),
        @"nativePointersExposed": @NO, @"gameplayMutationPerformed": @NO, @"fullEHRAvailable": @NO };
#else
    return @{ @"success": @NO, @"status": @"managed_rules_not_built", @"fullEHRAvailable": @NO };
#endif
}
