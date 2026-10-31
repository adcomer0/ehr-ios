#import <Foundation/Foundation.h>
#include "EHRRuntimeDiagnostics.h"
#if EHR_HAS_NETWORK_DIAGNOSTICS
#include "EHRNativePatchThunks.h"
extern "C" NSDictionary *EHRNativeDisconnectCopyStatus(void){return @{@"schemaVersion":@1,@"count":@1,@"reason":@5};}
#endif
#if EHR_HAS_AUTH_HANDOFF
#include "EHRAuthHandoffDiagnostics.h"
extern "C" NSDictionary<NSString *,id> *EHRAuthHandoffDiagnosticsCopyStatus(void){return @{@"preparedStatus":@0,@"phaseSequence":@9,@"loginEntries":@1};}
#endif
#if EHR_HAS_GAME_START_ITERATOR
#include "EHRGameStartIteratorAdapter.h"
// Fixed owned counters only: exercise the writer's optional linkage/schema
// without loading a runtime or inspecting game state.
extern "C" NSDictionary *EHRGameStartIteratorCopyStatus(void){return @{@"preparedStatus":@0,@"enabled":@YES,@"replacements":@2};}
#endif
int main(){@autoreleasepool {
 {EHRDiagnosticRouteScope scope(42,4096);scope.at(13,2);{EHRDiagnosticIteratorScope iterator(33,1);EHRDiagnosticLimit(ehr_diagnostics::RootCapacity,65536,65536);iterator.status=8;}scope.status=5;scope.flags=0;}
 {EHRDiagnosticComponentScope scope(7,2);scope.status=7;}
 EHRRuntimeDiagnosticsRecordAuth(1,1001,2);
 EHRRuntimeDiagnosticsRecordAuthInstall(0);EHRRuntimeDiagnosticsRecordAuthCounters(5,1,2,3);
 EHRRuntimeDiagnosticsRecordEOSLogin(1,42,0,1);EHRRuntimeDiagnosticsRecordEOSLogin(2,999,3,2);
 ehr_diagnostics::Gateway gateway;gateway.tick=5;gateway.loaded=1;gateway.roots=65536;gateway.root_limit=65536;gateway.deferred=123;gateway.deferred_limit=65536;gateway.enqueued=456;gateway.dequeued=333;gateway.released=300;ehr_diagnostics::state().gateway(gateway);
 ehr_diagnostics::Iterators iterators;iterators.entries=256;iterators.active=200;iterators.terminal=56;ehr_diagnostics::state().iterators(iterators);
 uint32_t sourceWords[12]={1,12,5,0,42,0,7,89,0,1,6,1};ehr_diagnostics::context={42,4096,33,15,0};if(!EHRDiagnosticSourceFailure(42,6,sourceWords,12))return 9;
 ehr_diagnostics::FailureDetail native;native.kind=2;native.method_token=0x60000ab;native.owner_hash=123;native.method_hash=456;native.exception_kind=1;native.status=6;ehr_diagnostics::state().failureDetail(8,native,ehr_diagnostics::context);
 uint64_t coroutineWords[12]={1,12,77,12345,3,3,6,6,9,3,6,0};if(!EHRDiagnosticCoroutineFailure(77,6,coroutineWords,12))return 15;
 NSDictionary *value=EHRRuntimeDiagnosticsCopyStatus();NSError *error=nil;
 NSData *bytes=[NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
 if(!bytes||error||bytes.length>512*1024)return 1;
 NSDictionary *copy=[NSJSONSerialization JSONObjectWithData:bytes options:0 error:&error];
 NSMutableSet *expected=[NSMutableSet setWithArray:@[@"schema",@"sequence",@"routeLimit",@"eventLimit",@"unknownRoutes",@"routes",@"events",@"failureTotal",@"failures",@"application",@"appleAuth",@"eosLogin",@"guardLimit",@"guardTotal",@"guards",@"gateway",@"productionIterators",@"failureDetailLimit",@"failureDetailTotal",@"failureDetails",@"writeStatus",@"writtenSequence"]];
#if EHR_HAS_GAME_START_ITERATOR
 [expected addObject:@"gameStartIterator"];
 if(![copy[@"gameStartIterator"] isEqualToDictionary:@{@"preparedStatus":@0,@"enabled":@YES,@"replacements":@2}])return 12;
#endif
#if EHR_HAS_AUTH_HANDOFF
 [expected addObject:@"authHandoff"];
 if(![copy[@"authHandoff"] isEqualToDictionary:@{@"preparedStatus":@0,@"phaseSequence":@9,@"loginEntries":@1}])return 13;
#endif
#if EHR_HAS_NETWORK_DIAGNOSTICS
 [expected addObject:@"networkDisconnect"];
 if(![copy[@"networkDisconnect"] isEqualToDictionary:@{@"schemaVersion":@1,@"count":@1,@"reason":@5}])return 14;
#endif
 if(error||![expected isEqualToSet:[NSSet setWithArray:copy.allKeys]])return 2;
 NSDictionary *route=[copy[@"routes"] firstObject];
 if([route[@"targetId"] unsignedLongLongValue]!=42||[route[@"started"] intValue]!=1||[route[@"completed"] intValue]!=1||[route[@"failed"] intValue]!=1||[route[@"lastStatus"] intValue]!=5||[route[@"lastFlags"] intValue]!=0||[route[@"lastPhase"] intValue]!=13||[route[@"lastArgument"] intValue]!=2)return 3;
 if([copy[@"events"] count]!=11||[copy[@"appleAuth"][@"code"] intValue]!=1001||[copy[@"writeStatus"] intValue]!=1||[copy[@"writtenSequence"] intValue]!=0)return 4;
 NSDictionary *auth=copy[@"appleAuth"];
 if([auth[@"requestCallbacks"] intValue]!=5||[auth[@"successCallbacks"] intValue]!=1||[auth[@"errorCallbacks"] intValue]!=2||[auth[@"overlapObservations"] intValue]!=3||[auth[@"installStatus"] intValue]!=0)return 5;
 NSDictionary *normal=copy[@"eosLogin"][@"normal"],*silent=copy[@"eosLogin"][@"silent"];
 if([normal[@"resultCode"] intValue]!=42||[normal[@"observerStatus"] intValue]!=0||[normal[@"observedCount"] intValue]!=1||[silent[@"resultCode"] intValue]!=0||[silent[@"observerStatus"] intValue]!=3||[silent[@"observedCount"] intValue]!=2)return 6;
 NSDictionary *guard=[copy[@"guards"] firstObject];
 if([copy[@"guardTotal"] intValue]!=1||[guard[@"targetId"] intValue]!=42||[guard[@"registrationId"] intValue]!=33||[guard[@"count"] intValue]!=65536||[guard[@"limit"] intValue]!=65536||[guard[@"phase"] intValue]!=13||[guard[@"argument"] intValue]!=2)return 7;
 if([copy[@"gateway"][@"rootCount"] intValue]!=65536||[copy[@"gateway"][@"deferredCount"] intValue]!=123||[copy[@"gateway"][@"deferredReleased"] intValue]!=300||[copy[@"productionIterators"][@"terminalTombstones"] intValue]!=56)return 8;
 if([copy[@"failureDetailTotal"] intValue]!=3||[copy[@"failureDetails"] count]!=3)return 10;
 NSDictionary *source=copy[@"failureDetails"][0],*caught=copy[@"failureDetails"][1];
 if([source[@"kind"] intValue]!=1||[source[@"callbackIndexPlusOne"] intValue]!=89||[source[@"stage"] intValue]!=7||[source[@"sourceSequence"] intValue]!=5||[caught[@"metadataMethodToken"] intValue]!=0x60000ab)return 11;
 NSDictionary *coroutine=copy[@"failureDetails"][2];if([coroutine[@"kind"] intValue]!=3||[coroutine[@"sourceId"] intValue]!=77||[coroutine[@"iteratorTypeHash"] intValue]!=12345||[coroutine[@"primaryStatus"] intValue]!=6||[coroutine[@"cleanupExceptionKind"] intValue]!=3||[coroutine[@"cleanupStatus"] intValue]!=6)return 16;
 // The fixture never starts the writer and never opens an app/game container.
 puts("{\"pass\":true,\"numericSerialization\":true,\"writerStarted\":false,\"gameCalls\":0}");return 0;
}}
