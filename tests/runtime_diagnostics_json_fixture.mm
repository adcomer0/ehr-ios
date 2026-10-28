#import <Foundation/Foundation.h>
#include "EHRRuntimeDiagnostics.h"
int main(){@autoreleasepool {
 {EHRDiagnosticRouteScope scope(42,4096);scope.at(13,2);{EHRDiagnosticIteratorScope iterator(33,1);EHRDiagnosticLimit(ehr_diagnostics::RootCapacity,65536,65536);iterator.status=8;}scope.status=5;scope.flags=0;}
 {EHRDiagnosticComponentScope scope(7,2);scope.status=7;}
 EHRRuntimeDiagnosticsRecordAuth(1,1001,2);
 EHRRuntimeDiagnosticsRecordAuthInstall(0);EHRRuntimeDiagnosticsRecordAuthCounters(5,1,2,3);
 EHRRuntimeDiagnosticsRecordEOSLogin(1,42,0,1);EHRRuntimeDiagnosticsRecordEOSLogin(2,999,3,2);
 ehr_diagnostics::Gateway gateway;gateway.tick=5;gateway.loaded=1;gateway.roots=65536;gateway.root_limit=65536;gateway.deferred=123;gateway.deferred_limit=65536;gateway.enqueued=456;gateway.dequeued=333;gateway.released=300;ehr_diagnostics::state().gateway(gateway);
 ehr_diagnostics::Iterators iterators;iterators.entries=256;iterators.active=200;iterators.terminal=56;ehr_diagnostics::state().iterators(iterators);
 NSDictionary *value=EHRRuntimeDiagnosticsCopyStatus();NSError *error=nil;
 NSData *bytes=[NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
 if(!bytes||error||bytes.length>512*1024)return 1;
 NSDictionary *copy=[NSJSONSerialization JSONObjectWithData:bytes options:0 error:&error];
 NSSet *expected=[NSSet setWithArray:@[@"schema",@"sequence",@"routeLimit",@"eventLimit",@"unknownRoutes",@"routes",@"events",@"failureTotal",@"failures",@"application",@"appleAuth",@"eosLogin",@"guardLimit",@"guardTotal",@"guards",@"gateway",@"productionIterators",@"writeStatus",@"writtenSequence"]];
 if(error||![expected isEqualToSet:[NSSet setWithArray:copy.allKeys]])return 2;
 NSDictionary *route=[copy[@"routes"] firstObject];
 if([route[@"targetId"] unsignedLongLongValue]!=42||[route[@"started"] intValue]!=1||[route[@"completed"] intValue]!=1||[route[@"failed"] intValue]!=1||[route[@"lastStatus"] intValue]!=5||[route[@"lastFlags"] intValue]!=0||[route[@"lastPhase"] intValue]!=13||[route[@"lastArgument"] intValue]!=2)return 3;
 if([copy[@"events"] count]!=8||[copy[@"appleAuth"][@"code"] intValue]!=1001||[copy[@"writeStatus"] intValue]!=1||[copy[@"writtenSequence"] intValue]!=0)return 4;
 NSDictionary *auth=copy[@"appleAuth"];
 if([auth[@"requestCallbacks"] intValue]!=5||[auth[@"successCallbacks"] intValue]!=1||[auth[@"errorCallbacks"] intValue]!=2||[auth[@"overlapObservations"] intValue]!=3||[auth[@"installStatus"] intValue]!=0)return 5;
 NSDictionary *normal=copy[@"eosLogin"][@"normal"],*silent=copy[@"eosLogin"][@"silent"];
 if([normal[@"resultCode"] intValue]!=42||[normal[@"observerStatus"] intValue]!=0||[normal[@"observedCount"] intValue]!=1||[silent[@"resultCode"] intValue]!=0||[silent[@"observerStatus"] intValue]!=3||[silent[@"observedCount"] intValue]!=2)return 6;
 NSDictionary *guard=[copy[@"guards"] firstObject];
 if([copy[@"guardTotal"] intValue]!=1||[guard[@"targetId"] intValue]!=42||[guard[@"registrationId"] intValue]!=33||[guard[@"count"] intValue]!=65536||[guard[@"limit"] intValue]!=65536||[guard[@"phase"] intValue]!=13||[guard[@"argument"] intValue]!=2)return 7;
 if([copy[@"gateway"][@"rootCount"] intValue]!=65536||[copy[@"gateway"][@"deferredCount"] intValue]!=123||[copy[@"gateway"][@"deferredReleased"] intValue]!=300||[copy[@"productionIterators"][@"terminalTombstones"] intValue]!=56)return 8;
 // The fixture never starts the writer and never opens an app/game container.
 puts("{\"pass\":true,\"numericSerialization\":true,\"writerStarted\":false,\"gameCalls\":0}");return 0;
}}
