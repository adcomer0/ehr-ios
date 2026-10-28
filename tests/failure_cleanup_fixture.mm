#import <Foundation/Foundation.h>
#define EHR_HAS_FULL_SOURCE 1
#ifndef EHR_FAILURE_CLEANUP_SOURCE
#define EHR_FAILURE_CLEANUP_SOURCE "../native/EHRSourceFailureCleanup.inc"
#endif
#include EHR_FAILURE_CLEANUP_SOURCE
#include <cassert>
#include <cstdio>
#include <thread>
#include <vector>

namespace fixture {
std::vector<char> events;unsigned checks=0;
int32_t targetStatus=0,iteratorStatus=0,touchStatus=0;bool componentThrows=false,componentMissing=false,deferred=false,reenter=false;
void require(bool value){++checks;if(!value){fprintf(stderr,"coordinator check %u failed\n",checks);abort();}}
NSDictionary *run(){events.clear();auto result=EHRFullSourceFailureCleanup();require(events==std::vector<char>({'T','H','I','C','I'}));return result;}
}
void EHRNativePatchMakeTargetsTable(EHRManagedPatchTargetsV1 *output){*output={1,sizeof(*output),nullptr,nullptr,[]()->int32_t{fixture::events.push_back('T');return fixture::targetStatus;}};}
extern "C" const EHRTouchUIV1 *EHRTouchUIGetV1(void){static const EHRTouchUIV1 table{1,sizeof(table),nullptr,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr,[]()->int32_t{fixture::events.push_back('H');return fixture::touchStatus;}};return &table;}
extern "C" EHRRuntimeStatus EHRManagedIteratorProductionFailClosed(EHRProductionIteratorFailureV1 *output,size_t bytes){fixture::require(bytes==sizeof(*output));fixture::events.push_back('I');*output={1,sizeof(*output),fixture::iteratorStatus,1,3,fixture::deferred?1u:0u,2,0,0,fixture::deferred?1u:0u,0,3,0};return static_cast<EHRRuntimeStatus>(fixture::iteratorStatus);}
NSDictionary *EHRSourceComponentsCloseAll(void){fixture::events.push_back('C');if(fixture::componentThrows)@throw [NSException exceptionWithName:@"OwnedFailure" reason:nil userInfo:nil];if(fixture::reenter){auto nested=EHRFullSourceFailureCleanup();fixture::require([nested[@"inProgress"] boolValue]&&[nested[@"status"] intValue]==1);}if(fixture::componentMissing)return @{};return @{@"status":@0,@"activeNativeRegistrations":@0,@"managedStateCount":@0,@"nativeWeakSelfTokens":@0,@"pluginOwnerRooted":@NO};}
int main(){@autoreleasepool{using namespace fixture;
 auto result=run();require([result[@"success"] boolValue]&&[result[@"registrationSealed"] boolValue]&&[result[@"carrierWeakTombstones"] intValue]==3&&[result[@"sourceTouchHidden"] boolValue]);
 result=run();require([result[@"success"] boolValue]);
 reenter=true;result=run();require([result[@"success"] boolValue]);reenter=false;
 targetStatus=7;result=run();require(![result[@"success"] boolValue]&&![result[@"targetsDeactivated"] boolValue]);targetStatus=0;
 touchStatus=4;result=run();require(![result[@"success"] boolValue]&&![result[@"sourceTouchHidden"] boolValue]&&[result[@"sourceStatesReleased"] boolValue]);touchStatus=0;
 iteratorStatus=6;result=run();require(![result[@"success"] boolValue]&&[result[@"sourceStatesReleased"] boolValue]);iteratorStatus=0;
 componentThrows=true;result=run();require(![result[@"success"] boolValue]&&[result[@"components"][@"status"] intValue]!=0);componentThrows=false;
 componentMissing=true;result=run();require(![result[@"success"] boolValue]&&![result[@"sourceStatesReleased"] boolValue]);componentMissing=false;
 deferred=true;result=run();require(![result[@"success"] boolValue]&&[result[@"deferred"] intValue]==1);deferred=false;
 events.clear();int workerStatus=0;std::thread worker([&]{@autoreleasepool{workerStatus=[EHRFullSourceFailureCleanup()[@"status"] intValue];}});worker.join();require(workerStatus==2&&events.empty());
 printf("PASS %u actual-source failure cleanup ordering/containment checks; no game executed\n",checks);
}}
