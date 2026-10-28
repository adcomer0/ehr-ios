#import "EHRManagedUnityActionProbe.h"
#include "EHRManagedActionAdapter.h"
NSDictionary<NSString *,id> *EHRManagedUnityActionSelfTest() {
#if EHR_HAS_MANAGED_RULES
    if(!NSThread.isMainThread)return @{ @"success":@NO,@"status":@(EHR_RUNTIME_WRONG_THREAD) };
    EHRManagedActionFamiliesV1 table{};EHRManagedActionMakeFamiliesTable(&table);
    const auto bound=ehr_action_bind_families(&table,sizeof(table));
    const auto before=EHRManagedActionActiveCount();
    EHRManagedUnityActionProofV1 proof{};
    const auto status=bound==0 ? ehr_unity_action_self_test(&proof,sizeof(proof)) : bound;
    return @{ @"success":@(bound==0 && status==0 && proof.pass==1 && before==EHRManagedActionActiveCount()),
        @"bindStatus":@(bound),@"managedStatus":@(status),@"firstEffects":@(proof.first_effects),@"secondEffects":@(proof.second_effects),
        @"removeExactNativeListener":@(proof.remove_exact_listener),@"proxyDisposePreservesListener":@(proof.proxy_dispose_preserves_listener),
        @"closedListenerNoop":@(proof.closed_listener_noop),@"sourceEntriesAfter":@(proof.source_entries_after),
        @"allOwnedRootsReleased":@(proof.roots_released),@"activeAfter":@(EHRManagedActionActiveCount()),
        @"weakTombstonesAfter":@(EHRManagedActionRegistrationCount()),@"separateActualButtonClickedEvent":@YES,
        @"sceneButtonMutationPerformed":@NO,@"metadataRecordsForZeroArgumentAbi":@1 };
#else
    return @{ @"success":@NO,@"status":@"managed_rules_not_built" };
#endif
}
