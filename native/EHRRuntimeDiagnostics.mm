#import <Foundation/Foundation.h>
#include "EHRRuntimeDiagnostics.h"
#include <atomic>
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {
std::atomic<int32_t> writeStatus{1};std::atomic<uint64_t> writtenSequence{0};
NSDictionary *eventDictionary(const ehr_diagnostics::Event&e){return @{@"sequence":@(e.sequence),@"monotonicNs":@(e.tick),@"kind":@(e.kind),@"id":@(e.id),@"methodRva":@(e.rva),@"detail":@(e.detail),@"status":@(e.status),@"flags":@(e.flags)};}
NSDictionary *dictionary(const ehr_diagnostics::Snapshot &s) {
 NSMutableArray *routes=[NSMutableArray arrayWithCapacity:s.route_count];
 for(size_t i=0;i<s.route_count;++i){const auto&r=s.routes[i];[routes addObject:@{@"targetId":@(r.id),@"methodRva":@(r.rva),@"checks":@(r.checks),@"activeChecks":@(r.active_checks),@"wrongThreadChecks":@(r.wrong_thread_checks),@"started":@(r.started),@"completed":@(r.completed),@"failed":@(r.failed),@"unentered":@(r.unentered),@"lastStatus":@(r.last_status),@"lastFlags":@(r.last_flags),@"lastPhase":@(r.last_phase),@"lastArgument":@(r.last_argument),@"lastBeginSequence":@(r.last_begin_sequence),@"lastEndSequence":@(r.last_end_sequence),@"lastBeginNs":@(r.last_begin_tick),@"lastEndNs":@(r.last_end_tick)}];}
 NSMutableArray *events=[NSMutableArray arrayWithCapacity:s.event_count];
 const uint64_t first=s.sequence-s.event_count+1;
 for(size_t i=0;i<s.event_count;++i)[events addObject:eventDictionary(s.events[(first+i-1)%ehr_diagnostics::EventLimit])];
 NSMutableArray *failures=[NSMutableArray arrayWithCapacity:s.failure_count];
 for(size_t i=0;i<s.failure_count;++i)[failures addObject:eventDictionary(s.failures[(s.failure_total-s.failure_count+i)%ehr_diagnostics::FailureLimit])];
 NSMutableArray *guards=[NSMutableArray arrayWithCapacity:s.guard_count];
 for(size_t i=0;i<s.guard_count;++i){const auto&g=s.guards[(s.guard_total-s.guard_count+i)%ehr_diagnostics::GuardLimit];[guards addObject:@{@"sequence":@(g.sequence),@"monotonicNs":@(g.tick),@"targetId":@(g.target),@"methodRva":@(g.rva),@"registrationId":@(g.iterator),@"category":@(g.category),@"count":@(g.count),@"limit":@(g.limit),@"phase":@(g.phase),@"argument":@(g.argument),@"gatewaySnapshotNs":@(g.gateway_tick),@"rootCount":@(g.roots),@"weakRootCount":@(g.weak_roots),@"deferredCount":@(g.deferred),@"deferredEnqueued":@(g.enqueued),@"deferredDequeued":@(g.dequeued),@"deferredReleased":@(g.released),@"iteratorSnapshotNs":@(g.iterator_tick),@"iteratorEntries":@(g.iterator_entries),@"iteratorActive":@(g.iterator_active),@"iteratorTerminal":@(g.iterator_terminal)}];}
 const auto&g=s.gateway;const auto&i=s.iterators;
 const auto&a=s.application;
 return @{@"schema":@"ehr.numeric-runtime-diagnostics.v1",@"sequence":@(s.sequence),@"routeLimit":@(ehr_diagnostics::RouteLimit),@"eventLimit":@(ehr_diagnostics::EventLimit),@"unknownRoutes":@(s.unknown_routes),@"routes":routes,@"events":events,@"failureTotal":@(s.failure_total),@"failures":failures,@"guardLimit":@(ehr_diagnostics::GuardLimit),@"guardTotal":@(s.guard_total),@"guards":guards,
 @"gateway":@{@"monotonicNs":@(g.tick),@"samples":@(g.samples),@"loaded":@(g.loaded),@"rootCount":@(g.roots),@"weakRootCount":@(g.weak_roots),@"rootLimit":@(g.root_limit),@"observedRootHighWater":@(g.observed_root_high_water),@"deferredCount":@(g.deferred),@"deferredLimit":@(g.deferred_limit),@"deferredHighWater":@(g.deferred_high_water),@"deferredEnqueued":@(g.enqueued),@"deferredDequeued":@(g.dequeued),@"deferredReleased":@(g.released),@"deferredFull":@(g.full)},
 @"productionIterators":@{@"monotonicNs":@(i.tick),@"entries":@(i.entries),@"entryLimit":@256,@"activeSources":@(i.active),@"terminalTombstones":@(i.terminal),@"currentRoots":@(i.current),@"carrierWeakRoots":@(i.weak),@"associationWeakRoots":@(i.associations),@"temporaryPins":@(i.pins),@"created":@(i.created),@"swept":@(i.swept),@"closed":@(i.closed),@"callbackFailures":@(i.callback_failures)},
 @"application":@{@"stage":@(a.stage),@"status":@(a.status),@"readyFlags":@(a.flags),@"state":@(a.state),@"loadAttempts":@(a.load_attempts),@"optionsLoaded":@(a.options_loaded),@"optionCount":@(a.options),@"activeBindings":@(a.active),@"candidates":@(a.candidates),@"postLoadTasksComplete":@(a.post_load)},
 @"appleAuth":@{@"domain":@(s.auth.domain),@"code":@(s.auth.code),@"observedCount":@(s.auth.count),@"installStatus":@(s.auth.install_status),@"requestCallbacks":@(s.auth.requests),@"successCallbacks":@(s.auth.successes),@"errorCallbacks":@(s.auth.errors),@"overlapObservations":@(s.auth.overlaps)},
 @"eosLogin":@{@"normal":@{@"resultCode":@(s.eos[0].result),@"observerStatus":@(s.eos[0].status),@"observedCount":@(s.eos[0].count)},@"silent":@{@"resultCode":@(s.eos[1].result),@"observerStatus":@(s.eos[1].status),@"observedCount":@(s.eos[1].count)}}};
}
// All filesystem work is on the private diagnostics queue. The worker never
// queries IL2CPP, game objects, source state, UIKit or account data.
void writeSnapshot() {
 @autoreleasepool {try {@try {
  const auto snapshot=ehr_diagnostics::state().snapshot();
  NSData *data=[NSJSONSerialization dataWithJSONObject:dictionary(snapshot) options:0 error:nil];
  if(!data||data.length>512*1024){writeStatus.store(8);return;}
  NSURL *caches=[[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
  if(!caches){writeStatus.store(7);return;}
  struct FD {int value=-1;~FD(){if(value>=0)close(value);}} parent,folder,file;
  parent.value=open(caches.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
  if(parent.value<0){writeStatus.store(7);return;}
  if(mkdirat(parent.value,"EHRDiagnostics",0700)&&errno!=EEXIST){writeStatus.store(7);return;}
  folder.value=openat(parent.value,"EHRDiagnostics",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
  if(folder.value<0){writeStatus.store(7);return;}
  // Own, uniquely named complete snapshot; never append to or follow an input.
  NSString *name=[@".snapshot-" stringByAppendingString:NSUUID.UUID.UUIDString];
  file.value=openat(folder.value,name.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
  if(file.value<0){writeStatus.store(7);return;}
  const uint8_t *bytes=static_cast<const uint8_t *>(data.bytes);size_t left=data.length;bool ok=true;
  while(left){ssize_t count=write(file.value,bytes,left);if(count<0&&errno==EINTR)continue;if(count<=0){ok=false;break;}bytes+=count;left-=size_t(count);}
  struct stat existing{};
  if(fstatat(folder.value,"runtime-native-v1.json",&existing,AT_SYMLINK_NOFOLLOW)==0){if(!S_ISREG(existing.st_mode)||existing.st_nlink!=1)ok=false;}else if(errno!=ENOENT)ok=false;
  if(ok)ok=renameat(folder.value,name.fileSystemRepresentation,folder.value,"runtime-native-v1.json")==0;
  if(!ok)unlinkat(folder.value,name.fileSystemRepresentation,0); // own partial only
  writeStatus.store(ok?0:7);if(ok)writtenSequence.store(snapshot.sequence);
 }@catch(__unused NSException *e){writeStatus.store(7);}}catch(...){writeStatus.store(8);}}
}
}
void EHRRuntimeDiagnosticsStart(void) {
 static dispatch_once_t once;dispatch_once(&once,^{
  dispatch_queue_t queue=dispatch_queue_create("local.ehr.numeric-diagnostics",DISPATCH_QUEUE_SERIAL);
  static dispatch_source_t timer;timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,queue);
  dispatch_source_set_timer(timer,DISPATCH_TIME_NOW,2*NSEC_PER_SEC,NSEC_PER_SEC/5);
  dispatch_source_set_event_handler(timer,^{writeSnapshot();});dispatch_resume(timer);
 });
}
void EHRRuntimeDiagnosticsRecordAuth(uint32_t domain,int32_t code,uint64_t count) {ehr_diagnostics::state().auth(EHRDiagnosticTick(),domain,code,count);}
void EHRRuntimeDiagnosticsRecordAuthInstall(int32_t status) {ehr_diagnostics::state().authInstall(status);}
void EHRRuntimeDiagnosticsRecordAuthCounters(uint64_t requests,uint64_t successes,uint64_t errors,uint64_t overlaps) {ehr_diagnostics::state().authCounters(requests,successes,errors,overlaps);}
void EHRRuntimeDiagnosticsRecordEOSLogin(uint32_t phase,int32_t result,int32_t status,uint64_t count) {ehr_diagnostics::state().eosLogin(phase,result,status,count);}
NSDictionary *EHRRuntimeDiagnosticsCopyStatus(void) {
 NSMutableDictionary *value=[dictionary(ehr_diagnostics::state().snapshot()) mutableCopy];
 value[@"writeStatus"]=@(writeStatus.load());value[@"writtenSequence"]=@(writtenSequence.load());return value;
}
