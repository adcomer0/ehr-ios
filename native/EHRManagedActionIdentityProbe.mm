#import "EHRManagedActionIdentityProbe.h"
#include <stdint.h>
extern "C" int32_t ehr_action_identity_self_test(uint32_t *,size_t);
NSDictionary<NSString *,id> *EHRManagedActionIdentitySelfTest(){
#if EHR_HAS_MANAGED_RULES
    if(!NSThread.isMainThread)return @{ @"success":@NO,@"status":@2 };
    uint32_t p[12]{};auto status=ehr_action_identity_self_test(p,12);
    return @{ @"success":@(status==0&&p[0]==1),@"status":@(status),@"managedStatus":@(p[1]),
      @"zeroActionFreshRemoval":@(p[2]),@"typedActionFreshRemoval":@(p[3]),@"unityEventFreshRemoval":@(p[4]),
      @"proxyDisposePreservesAlias":@(p[5]),@"closeAliasTombstonesSource":@(p[6]),@"distinctTargetsSeparate":@(p[7]),
      @"zeroSourceEntriesAfter":@(p[8]),@"typedSourceEntriesAfter":@(p[9]),@"allOwnedRootsReleased":@(p[10]),@"lookupStep":@(p[11]),
      @"nativePointersExposed":@NO,@"sceneEventSubscriptionPerformed":@NO };
#else
    return @{ @"success":@NO,@"status":@"managed_rules_not_built" };
#endif
}
