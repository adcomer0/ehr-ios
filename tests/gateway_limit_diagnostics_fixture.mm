// Exercises production numeric guard paths with synthetic private state only.
// No IL2CPP symbols are resolved, and no game/framework/app is loaded.
#include "EHRRuntimeGateway.mm"
#include <cstdio>
#include <cstdlib>
#include <thread>
#define CHECK(x) do{++checks;if(!(x)){std::fprintf(stderr,"line %d\n",__LINE__);return 1;}}while(0)
static size_t frees=0;
static void fakeFree(uint32_t){++frees;}
static char *fakeName(const Type*){return strdup("ABC");}
static void fakeRuntimeFree(void*p){free(p);}
int main(){@autoreleasepool {size_t checks=0;auto&s=state();
 // A full root map rejects before allocating/calling the GC API.
 for(size_t i=1;i<=kMaxRoots;++i)s.roots.emplace(i,uint32_t(i));
 ehr_diagnostics::context={42,4096,33,13,2};EHRRuntimeToken owned=777;
 CHECK(root(reinterpret_cast<Object*>(1),&owned)==EHR_RUNTIME_LIMIT&&owned==0);
 auto snapshot=ehr_diagnostics::state().snapshot();CHECK(snapshot.guard_total==1);
 auto guard=snapshot.guards[0];CHECK(guard.category==ehr_diagnostics::RootCapacity&&guard.count==65536&&guard.limit==65536&&guard.target==42&&guard.iterator==33&&guard.phase==13&&guard.argument==2&&guard.roots==65536&&guard.gateway_tick!=0);
 CHECK(snapshot.gateway.roots==65536&&snapshot.gateway.root_limit==65536);
 // Per-call promotion rejection also occurs before touching a managed object.
 {WeakTokenScope scope;scope.count=scope.leases.size();Object*value=nullptr;
  CHECK(scope.promote(1,1,&value)==EHR_RUNTIME_LIMIT);scope.count=0;}
 snapshot=ehr_diagnostics::state().snapshot();CHECK(snapshot.guards[1].category==ehr_diagnostics::WeakPromotionCapacity&&snapshot.guards[1].count==129);
 // Empty output is the documented size query; short non-empty storage is a
 // real capacity guard. Both keep their original LIMIT result.
 s.api.type_get_name=fakeName;s.api.runtime_free=fakeRuntimeFree;size_t required=0;char shortName[2]{};
 CHECK(copyTypeName(reinterpret_cast<Type*>(1),nullptr,0,&required)==EHR_RUNTIME_LIMIT&&required==4);
 CHECK(ehr_diagnostics::state().snapshot().guard_total==2);
 CHECK(copyTypeName(reinterpret_cast<Type*>(1),shortName,sizeof(shortName),&required)==EHR_RUNTIME_LIMIT&&required==4);
 snapshot=ehr_diagnostics::state().snapshot();CHECK(snapshot.guards[2].category==ehr_diagnostics::TypeNameCapacity&&snapshot.guards[2].count==4&&snapshot.guards[2].limit==2);
 // Any-thread enqueue stays independent of root-map/IL2CPP reads. Do not run
 // the app main loop: the queued callback is not executed in this fixture.
 for(size_t i=1;i<=kMaxRoots;++i)CHECK(ehr_runtime_object_release_deferred(i)==EHR_RUNTIME_OK);
 EHRRuntimeGatewayPublishDiagnosticSnapshot();snapshot=ehr_diagnostics::state().snapshot();
 CHECK(snapshot.gateway.deferred==65536&&snapshot.gateway.enqueued==65536&&snapshot.gateway.deferred_high_water==65536);
 auto samples=snapshot.gateway.samples;bool workerPassed=false;
 std::thread worker([&]{EHRRuntimeGatewayPublishDiagnosticSnapshot();workerPassed=ehr_runtime_object_release_deferred(1)==EHR_RUNTIME_LIMIT;});worker.join();
 snapshot=ehr_diagnostics::state().snapshot();CHECK(workerPassed&&snapshot.gateway.samples==samples);
 EHRRuntimeGatewayPublishDiagnosticSnapshot();snapshot=ehr_diagnostics::state().snapshot();CHECK(snapshot.gateway.full==1&&snapshot.gateway.deferred==65536);
 s.api.gchandle_free=fakeFree;CHECK(drainDeferred(2)==2&&frees==2);
 snapshot=ehr_diagnostics::state().snapshot();CHECK(snapshot.gateway.roots==65534&&snapshot.gateway.deferred==65534&&snapshot.gateway.dequeued==2&&snapshot.gateway.released==2&&snapshot.gateway.observed_root_high_water==65536);
 CHECK(!s.loaded);std::printf("{\"pass\":true,\"checks\":%zu,\"gameLoaded\":false,\"realGcCalls\":0,\"mockGcFrees\":%zu}\n",checks,frees);return 0;
}}
