#import "EHRManagedTypedActionProbe.h"
#include "EHRManagedTypedActionAdapter.h"
NSDictionary<NSString *,id> *EHRManagedTypedActionSelfTest(){
#if EHR_HAS_MANAGED_RULES
    if(!NSThread.isMainThread)return @{ @"success":@NO,@"status":@(EHR_RUNTIME_WRONG_THREAD) };
    EHRManagedTypedActionHostV1 table{};EHRManagedTypedActionMakeTable(&table);
    EHRManagedTypedActionCallbacksV1 callbacks{};
    const auto bound=ehr_typed_action_bind_gateway(&table,sizeof(table),&callbacks,sizeof(callbacks));
    const auto routed=bound==0?EHRManagedTypedActionSetCallbacks(&callbacks):EHR_RUNTIME_NOT_READY;
    const auto before=EHRManagedTypedActionActiveCount();
    EHRManagedTypedActionProofV1 proof{};
    const auto status=routed==EHR_RUNTIME_OK?ehr_typed_action_self_test(&proof,sizeof(proof)):routed;
    return @{ @"success":@(bound==0&&routed==EHR_RUNTIME_OK&&status==0&&proof.pass==1&&before==EHRManagedTypedActionActiveCount()),
        @"bindStatus":@(bound),@"routeStatus":@(routed),@"managedStatus":@(status),@"nativeFactoryStep":@(EHRManagedTypedActionLastStep()),@"caseId":@(proof.case_id),@"lookupStep":@(proof.lookup_step),
        @"int32Exact":@(proof.int32_exact),@"byteExact":@(proof.byte_exact),@"floatExact":@(proof.float_exact),@"referenceIdentity":@(proof.reference_identity),
        @"optionBehaviourNull":@(proof.option_null),@"gameObjectNull":@(proof.gameobject_null),@"sourceExceptionContained":@(proof.exception_contained),
        @"proxyDisposePreservesNative":@(proof.proxy_dispose_preserves_native),@"closeLateInvokeNoop":@(proof.close_late_noop),@"combineRemoveExisting":@(proof.combine_remove),
        @"sourceEntriesAfter":@(proof.source_entries_after),@"allOwnedRootsReleased":@(proof.roots_released),@"activeAfter":@(EHRManagedTypedActionActiveCount()),
        @"weakTombstonesAfter":@(EHRManagedTypedActionRegistrationCount()),@"nativePointersExposed":@NO,@"gameplayMutationPerformed":@NO };
#else
    return @{ @"success":@NO,@"status":@"managed_rules_not_built" };
#endif
}
