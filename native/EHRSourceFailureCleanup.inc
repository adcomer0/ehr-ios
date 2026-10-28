#import "EHRSourceFailureCleanup.h"
#include "EHRManagedIteratorProduction.h"
#include "EHRSourceComponents.h"
#include "EHRNativePatchThunks.h"
#include "EHRTouchUI.h"

NSDictionary *EHRFullSourceFailureCleanup(void){
    if(!NSThread.isMainThread)return @{@"success":@NO,@"status":@(EHR_RUNTIME_WRONG_THREAD)};
#if EHR_HAS_FULL_SOURCE
    static bool cleaning=false;
    if(cleaning)return @{@"success":@NO,@"inProgress":@YES,@"status":@(EHR_RUNTIME_NOT_READY)};
    cleaning=true;struct Guard{bool&value;~Guard(){value=false;}}guard{cleaning};
    int32_t deactivated=EHR_RUNTIME_MANAGED_EXCEPTION,iterators=EHR_RUNTIME_MANAGED_EXCEPTION,touchHidden=EHR_RUNTIME_MANAGED_EXCEPTION;
    EHRProductionIteratorFailureV1 before{},after{};NSDictionary *components=nil;
    @try{try{EHRManagedPatchTargetsV1 targets{};EHRNativePatchMakeTargetsTable(&targets);
        deactivated=targets.abi_version==1&&targets.byte_size==sizeof(targets)&&targets.deactivate?targets.deactivate():EHR_RUNTIME_BAD_ARGUMENT;
    }catch(...){deactivated=EHR_RUNTIME_LIMIT;}}@catch(__unused NSException*e){deactivated=EHR_RUNTIME_MANAGED_EXCEPTION;}
    @try{try{const auto*touch=EHRTouchUIGetV1();touchHidden=touch&&touch->version==1&&touch->size==sizeof(*touch)&&touch->hide?touch->hide():EHR_RUNTIME_BAD_ARGUMENT;
    }catch(...){touchHidden=EHR_RUNTIME_LIMIT;}}@catch(__unused NSException*e){touchHidden=EHR_RUNTIME_MANAGED_EXCEPTION;}
    // Stop only OUR returned Coroutine handles before destroying native owners.
    // A stop error does not prevent source cancellation or component teardown.
    iterators=EHRManagedIteratorProductionFailClosed(&before,sizeof(before));
    @try{try{components=EHRSourceComponentsCloseAll();}catch(...){components=@{@"status":@(EHR_RUNTIME_LIMIT)};}}
    @catch(__unused NSException*e){components=@{@"status":@(EHR_RUNTIME_MANAGED_EXCEPTION)};}
    const int32_t finalStatus=EHRManagedIteratorProductionFailClosed(&after,sizeof(after));
    const bool componentStatusPresent=components[@"status"]!=nil;
    const bool statesReleased=componentStatusPresent&&[components[@"status"] intValue]==0
        &&components[@"activeNativeRegistrations"]!=nil&&[components[@"activeNativeRegistrations"] unsignedLongLongValue]==0
        &&components[@"managedStateCount"]!=nil&&[components[@"managedStateCount"] unsignedLongLongValue]==0
        &&components[@"nativeWeakSelfTokens"]!=nil&&[components[@"nativeWeakSelfTokens"] unsignedLongLongValue]==0
        &&components[@"pluginOwnerRooted"]!=nil&&![components[@"pluginOwnerRooted"] boolValue];
    const bool pending=after.deferred!=0;
    const bool success=deactivated==0&&touchHidden==0&&iterators==0&&finalStatus==0&&statesReleased&&!pending
        &&after.active_sources==0&&after.current_roots==0&&after.association_weak_roots==0;
    return @{@"success":@(success),@"targetsDeactivated":@(deactivated==0),@"targetStatus":@(deactivated),@"sourceTouchHidden":@(touchHidden==0),@"touchStatus":@(touchHidden),
        @"iteratorStatus":@(iterators?iterators:finalStatus),@"components":components?:@{},@"sourceStatesReleased":@(statesReleased),
        @"registrationSealed":@(after.sealed!=0),@"deferred":@(after.deferred),@"activeSources":@(after.active_sources),
        @"currentRoots":@(after.current_roots),@"associationWeakRoots":@(after.association_weak_roots),
        @"carrierWeakTombstones":@(after.carrier_weak_roots),@"engineStopAttempts":@(after.engine_stop_attempts),
        @"engineStopFailures":@(after.engine_stop_failures),@"cancelFailures":@(after.cancel_failures)};
#else
    return @{@"success":@NO,@"status":@(EHR_RUNTIME_UNSUPPORTED)};
#endif
}
