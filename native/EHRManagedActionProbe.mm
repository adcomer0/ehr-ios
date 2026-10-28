#import "EHRManagedActionProbe.h"
#include "EHRManagedActionAdapter.h"
NSDictionary<NSString *,id> *EHRManagedActionSelfTest() {
#if EHR_HAS_MANAGED_RULES
    if(!NSThread.isMainThread) return @{ @"success":@NO,@"status":@(EHR_RUNTIME_WRONG_THREAD) };
    EHRManagedActionHostV1 host{};EHRManagedActionMakeTable(&host);
    EHRManagedActionCallbacksV1 callbacks{};
    const int32_t bound=ehr_action_bind_gateway(&host,sizeof(host),&callbacks,sizeof(callbacks));
    const auto routed=bound==0 ? EHRManagedActionSetCallbacks(&callbacks) : EHR_RUNTIME_NOT_READY;
    const auto before=EHRManagedActionActiveCount();
    EHRManagedActionProofV1 proof{};
    const int32_t status=routed==EHR_RUNTIME_OK ? ehr_action_self_test(&proof,sizeof(proof)) : routed;
    size_t removed=0;const auto swept=EHRManagedActionSweep(&removed);
    const auto active=EHRManagedActionActiveCount(),weak=EHRManagedActionRegistrationCount();
    return @{ @"success":@(bound==0 && routed==EHR_RUNTIME_OK && status==0 && proof.pass==1 && before==active && swept==EHR_RUNTIME_OK),
        @"bindStatus":@(bound),@"routeStatus":@(routed),@"managedStatus":@(status),@"sourceEffects":@(proof.source_effects),
        @"sourceExceptionContained":@(proof.callback_exception_contained),@"closedRetainedNativeActionNoop":@(proof.closed_late_invoke_noop),
        @"proxyDisposePreservesRetainedNativeAction":@(proof.proxy_dispose_preserves_native),
        @"sourceEntriesAfter":@(proof.source_entries_after),@"successCallbackStatus":@(proof.callback_success_status),
        @"exceptionCallbackStatus":@(proof.callback_error_status),@"allOwnedDelegateRootsReleased":@(proof.roots_released),
        @"activeBefore":@(before),@"activeAfter":@(active),@"remainingWeakTombstones":@(weak),@"weakEntriesSwept":@(removed),
        @"automaticMainQueueWeakSweepEnabled":@YES,@"metadataRecordsPerAbi":@1,@"metadataRecordLifetime":@"process",
        @"eventSubscriptionTested":@NO,@"nativePointersExposed":@NO,@"runtimeCodeGenerationPerformed":@NO };
#else
    return @{ @"success":@NO,@"status":@"managed_rules_not_built" };
#endif
}
