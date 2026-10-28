#include "EHRRuntimeDiagnostics.h"
#include <atomic>
#include <cstdio>
#include <thread>
#define CHECK(x) do{++checks;if(!(x)){std::fprintf(stderr,"line %d\n",__LINE__);return 1;}}while(0)
int main(){size_t checks=0;using namespace ehr_diagnostics;State state;
 state.begin(10,42,4096);auto one=state.snapshot();CHECK(one.route_count==1);CHECK(one.routes[0].started==1&&one.routes[0].completed==0);CHECK(one.events[0].kind==RouteBegin);
 state.end(11,42,4096,6,1|4|8|16|32|64);one=state.snapshot();CHECK(one.routes[0].failed==1);CHECK(one.routes[0].last_status==6);CHECK(one.routes[0].unentered==0);CHECK(one.routes[0].last_flags==125);
 state.begin(12,42,4096);state.end(13,42,4096,5,0,13,2);one=state.snapshot();CHECK(one.routes[0].started==2&&one.routes[0].completed==2);CHECK(one.routes[0].failed==2&&one.routes[0].unentered==1);CHECK(one.routes[0].last_phase==13&&one.routes[0].last_argument==2);
 // Conflicting RVA is rejected from the route summary, never merged silently.
 state.begin(14,42,8192);one=state.snapshot();CHECK(one.unknown_routes==1);CHECK(one.routes[0].rva==4096&&one.routes[0].started==2);
 Application app;app.stage=15;app.flags=63;app.state=3;app.options_loaded=1;app.options=5049;state.application(15,app);state.auth(16,1,1001,2);
 for(size_t i=0;i<600;++i){state.component(i,true,7,2,0);state.component(i,false,7,2,6);}
 one=state.snapshot();CHECK(one.event_count==EventLimit);CHECK(one.application.options==5049&&one.application.state==3);CHECK(one.auth.domain==1&&one.auth.code==1001&&one.auth.count==2);
 CHECK(one.failure_total==602&&one.failure_count==FailureLimit);CHECK(one.routes[0].last_begin_sequence==3&&one.routes[0].last_end_sequence==4);CHECK(one.routes[0].last_begin_tick==12&&one.routes[0].last_end_tick==13);
 state.checked(700,42,4096,true,true);state.checked(701,42,4096,false,false);state.authCounters(5,1,2,3);state.authInstall(0);one=state.snapshot();
 CHECK(one.routes[0].checks==2&&one.routes[0].active_checks==1&&one.routes[0].wrong_thread_checks==1);
 CHECK(one.auth.requests==5&&one.auth.successes==1&&one.auth.errors==2&&one.auth.overlaps==3&&one.auth.install_status==0);
 state.eosLogin(1,42,0,1);state.eosLogin(2,999,3,2);state.eosLogin(0,100,0,5);state.eosLogin(3,100,0,5);one=state.snapshot();
 CHECK(one.eos[0].result==42&&one.eos[0].status==0&&one.eos[0].count==1);
 CHECK(one.eos[1].result==0&&one.eos[1].status==3&&one.eos[1].count==2);
 const auto first=one.sequence-one.event_count+1;for(size_t i=0;i<one.event_count;++i){CHECK(one.events[(first+i-1)%EventLimit].sequence==first+i);}
 State bounded;for(size_t i=1;i<=RouteLimit+8;++i)bounded.begin(i,i,4096+i*4);one=bounded.snapshot();CHECK(one.route_count==RouteLimit);CHECK(one.unknown_routes==8);CHECK(one.event_count==EventLimit);
 State limits;Context origin;origin.target=42;origin.rva=4096;origin.iterator=33;origin.phase=13;origin.argument=2;
 for(size_t i=0;i<GuardLimit+17;++i)limits.guard(i,RootCapacity,65536,65536,origin);
 one=limits.snapshot();CHECK(one.guard_total==GuardLimit+17&&one.guard_count==GuardLimit);CHECK(one.failure_count==0);
 for(size_t i=0;i<one.guard_count;++i){const auto&g=one.guards[(one.guard_total-one.guard_count+i)%GuardLimit];CHECK(g.sequence==one.guard_total-one.guard_count+i+1);CHECK(g.target==42&&g.iterator==33&&g.phase==13&&g.argument==2&&g.count==65536&&g.limit==65536);}
 Gateway gateway;gateway.roots=200;limits.gateway(gateway);gateway.roots=100;limits.gateway(gateway);one=limits.snapshot();CHECK(one.gateway.samples==2&&one.gateway.roots==100&&one.gateway.observed_root_high_water==200);
 State concurrent;std::atomic<bool> running{true};std::thread worker([&]{while(running.load()){auto s=concurrent.snapshot();if(s.event_count>EventLimit||s.route_count>RouteLimit)std::abort();}});
 for(size_t i=0;i<5000;++i){concurrent.begin(i,1,4096);concurrent.end(i,1,4096,0,1|64);concurrent.iterator(i,true,7,1,0);concurrent.iterator(i,false,7,1,0);}running.store(false);worker.join();
 one=concurrent.snapshot();CHECK(one.routes[0].started==5000&&one.routes[0].completed==5000);CHECK(one.routes[0].failed==0);CHECK(one.event_count==EventLimit);CHECK(one.sequence==20000);
 // Reentrant scopes restore the caller's route/iterator context exactly.
 context={99,100,77,6,1};
 {EHRDiagnosticRouteScope outer(42,4096);outer.at(13,2);CHECK(context.target==42&&context.iterator==77&&context.phase==13);
  {EHRDiagnosticIteratorScope iterator(33,1);CHECK(context.target==42&&context.iterator==33);
   {EHRDiagnosticRouteScope inner(43,8192);inner.at(12);CHECK(context.target==43&&context.iterator==33);}
   CHECK(context.target==42&&context.phase==13&&context.argument==2);}
  CHECK(context.iterator==77&&context.phase==13);
  bool workerClean=false;std::thread isolated([&]{workerClean=context.target==0&&context.iterator==0;context.target=500;});isolated.join();CHECK(workerClean&&context.target==42);}
 CHECK(context.target==99&&context.rva==100&&context.iterator==77&&context.phase==6&&context.argument==1);
 std::printf("{\"pass\":true,\"checks\":%zu,\"gameCalls\":0}\n",checks);
}
