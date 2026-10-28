#import "EHRManagedComplexDelegateProbe.h"
#include "EHRManagedComplexDelegateAdapter.h"
extern "C" int32_t ehr_complex_delegate_self_test(uint32_t *,size_t);
NSDictionary<NSString *,id> *EHRManagedComplexDelegateSelfTest(){
#if EHR_HAS_MANAGED_RULES
 if(!NSThread.isMainThread)return @{ @"success":@NO,@"status":@2 };
 EHRComplexDelegateHostV1 host{};EHRComplexDelegateMakeTable(&host);EHRComplexDelegateCallbacksV1 callbacks{};
 auto bound=ehr_complex_delegate_bind_gateway(&host,sizeof(host),&callbacks,sizeof(callbacks));
 auto routed=bound==0?EHRComplexDelegateSetCallbacks(&callbacks):EHR_RUNTIME_NOT_READY;auto before=EHRComplexDelegateActiveCount();
 uint32_t p[20]{};auto status=routed==EHR_RUNTIME_OK?ehr_complex_delegate_self_test(p,20):routed;
 return @{ @"success":@(bound==0&&routed==EHR_RUNTIME_OK&&status==0&&p[0]==1&&before==EHRComplexDelegateActiveCount()),
 @"bindStatus":@(bound),@"routeStatus":@(routed),@"status":@(status),@"managedStatus":@(p[1]),@"nativeFactoryStep":@(EHRComplexDelegateLastStep()),@"caseId":@(p[18]),@"lookupStep":@(p[19]),
 @"action3Exact":@(p[2]),@"functionTrue":@(p[3]),@"functionFalse":@(p[4]),@"networkedPlayerNull":@(p[5]),@"sceneHandleEscapesOwned":@(p[6]),@"sceneModeExact":@(p[7]),
 @"sourceExceptionContainedReturnsFalse":@(p[8]),@"proxyDisposePreservesNative":@(p[9]),@"closeLateInvokeFalse":@(p[10]),@"freshMethodGroupRemove":@(p[11]),
 @"scopeUnsubscribeThenClose":@(p[12]),@"scopeContinuesAfterFailure":@(p[13]),@"sourceEntriesAfter":@(p[14]),@"allOwnedRootsReleased":@(p[15]),
 @"activeAfter":@(EHRComplexDelegateActiveCount()),@"weakTombstonesAfter":@(EHRComplexDelegateWeakCount()),@"nativePointersExposed":@NO,@"sceneEventSubscriptionPerformed":@NO,@"gameplayMutationPerformed":@NO };
#else
 return @{ @"success":@NO,@"status":@"managed_rules_not_built" };
#endif
}
