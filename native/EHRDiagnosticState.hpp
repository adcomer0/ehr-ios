#pragma once
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <mutex>

// Only compile-time route IDs/RVAs, source component IDs and numeric outcomes
// belong here. No pointers, GC tokens, arguments, error text or user data.
namespace ehr_diagnostics {
constexpr size_t RouteLimit=384, EventLimit=128, FailureLimit=32, GuardLimit=32, DetailLimit=32;
enum Kind:uint32_t {RouteBegin=1,RouteEnd=2,Startup=3,ComponentBegin=4,ComponentEnd=5,Auth=6,IteratorBegin=7,IteratorEnd=8,RouteCheck=9,LimitGuard=10,FailureDetailEvent=11};
// Numeric categories identify the existing guard; zero limit means no numeric
// bound is known (allocation failure or a managed callback returning LIMIT).
enum GuardCategory:uint32_t {RootCapacity=1,WeakRootCapacity=2,PinRootCapacity=3,TokenExhaustion=4,WeakPromotionCapacity=5,
 DeferredCapacity=6,ValueSize=7,CopyValueCapacity=8,StringLength=9,StringCapacity=10,TypeNameLength=11,TypeNameCapacity=12,
 NestedDepth=13,AssemblyCount=14,NestedMemberCount=15,MethodCount=16,FieldCount=17,IteratorCapacity=18,IteratorTokenExhaustion=19,
 IteratorAllocation=20,ThunkCopyBytes=21,ThunkAllocation=22,CallbackReturnedLimit=23,NativeIteratorException=24};
struct Context {uint64_t target=0,rva=0,iterator=0;uint32_t phase=0,argument=0;};
inline thread_local Context context{};
// kind1: owned source enums/ordinals; kind2: native exception's fixed class
// enum and immutable public metadata identity; kind3: owned coroutine failure
// phase/type hash and fixed exception/status enums. No messages or roots.
struct FailureDetail {uint64_t sequence=0,tick=0,target=0,rva=0,iterator=0,source_sequence=0,owner_hash=0,method_hash=0;
 uint32_t kind=0,stage=0,callback=0,argument=0,exception_kind=0,method_token=0,original_entered=0;int32_t status=0;
 uint64_t source_id=0,iterator_type_hash=0;uint32_t cleanup_exception_kind=0;int32_t primary_status=0,cleanup_status=0;};
struct Event {uint64_t sequence=0,tick=0,id=0,rva=0;uint32_t kind=0,detail=0,flags=0;int32_t status=0;};
struct Route {uint64_t id=0,rva=0,started=0,completed=0,failed=0,unentered=0,last_begin_sequence=0,last_end_sequence=0,last_begin_tick=0,last_end_tick=0,checks=0,active_checks=0,wrong_thread_checks=0;int32_t last_status=0;uint32_t last_flags=0,last_phase=0,last_argument=0;};
struct Guard {uint64_t sequence=0,tick=0,target=0,rva=0,iterator=0,count=0,limit=0;uint32_t category=0,phase=0,argument=0;uint64_t gateway_tick=0,roots=0,weak_roots=0,deferred=0,enqueued=0,dequeued=0,released=0,iterator_tick=0,iterator_entries=0,iterator_active=0,iterator_terminal=0;};
struct Gateway {uint64_t tick=0,samples=0,roots=0,weak_roots=0,root_limit=0,observed_root_high_water=0,deferred=0,deferred_limit=0,deferred_high_water=0,enqueued=0,dequeued=0,released=0,full=0;uint32_t loaded=0;};
struct Iterators {uint64_t tick=0,entries=0,active=0,terminal=0,current=0,weak=0,associations=0,pins=0,created=0,swept=0,closed=0,callback_failures=0;};
struct Application {uint32_t stage=0,flags=0,state=0,load_attempts=0,options_loaded=0,options=0,active=0,candidates=0,post_load=0;int32_t status=0;};
struct AuthState {uint32_t domain=0;int32_t code=0,install_status=1;uint64_t count=0,requests=0,successes=0,errors=0,overlaps=0;};
struct EOSLogin {int32_t result=0,status=1;uint64_t count=0;};
struct Snapshot {uint64_t sequence=0,unknown_routes=0,failure_total=0,guard_total=0,detail_total=0;size_t route_count=0,event_count=0,failure_count=0,guard_count=0,detail_count=0;Application application{};AuthState auth{};Gateway gateway{};Iterators iterators{};std::array<EOSLogin,2> eos{};std::array<Route,RouteLimit> routes{};std::array<Event,EventLimit> events{};std::array<Event,FailureLimit> failures{};std::array<Guard,GuardLimit> guards{};std::array<FailureDetail,DetailLimit> details{};};
class State {
 std::mutex mutex_;Snapshot data_{};
 void event(uint32_t kind,uint64_t tick,uint64_t id,uint64_t rva,uint32_t detail,int32_t status,uint32_t flags) {
  auto sequence=++data_.sequence;data_.events[(sequence-1)%EventLimit]={sequence,tick,id,rva,kind,detail,flags,status};
  if(data_.event_count<EventLimit)++data_.event_count;
  if(status!=0&&(kind==RouteEnd||kind==ComponentEnd||kind==IteratorEnd)){
   data_.failures[data_.failure_total++%FailureLimit]=data_.events[(sequence-1)%EventLimit];
   if(data_.failure_count<FailureLimit)++data_.failure_count;
  }
 }
 Route *route(uint64_t id,uint64_t rva) {
  for(size_t i=0;i<data_.route_count;++i)if(data_.routes[i].id==id)return data_.routes[i].rva==rva?&data_.routes[i]:nullptr;
  if(!id||data_.route_count==RouteLimit)return nullptr;
  auto &row=data_.routes[data_.route_count++];row.id=id;row.rva=rva;return &row;
 }
public:
 void checked(uint64_t tick,uint64_t id,uint64_t rva,bool enabled,bool main) noexcept {
  std::lock_guard<std::mutex> guard(mutex_);if(auto *row=route(id,rva)){++row->checks;row->active_checks+=enabled;row->wrong_thread_checks+=!main;}else ++data_.unknown_routes;
  // The first decision is useful even when a route never reaches source.
  if(auto *row=route(id,rva);row&&row->checks==1)event(RouteCheck,tick,id,rva,0,main?0:2,enabled?1:0);
 }
 void begin(uint64_t tick,uint64_t id,uint64_t rva) noexcept {
  std::lock_guard<std::mutex> guard(mutex_);if(auto *row=route(id,rva)){++row->started;row->last_begin_sequence=data_.sequence+1;row->last_begin_tick=tick;}else ++data_.unknown_routes;
  event(RouteBegin,tick,id,rva,0,0,0);
 }
 void end(uint64_t tick,uint64_t id,uint64_t rva,int32_t status,uint32_t flags,uint32_t phase=0,uint32_t argument=0) noexcept {
  std::lock_guard<std::mutex> guard(mutex_);if(auto *row=route(id,rva)){++row->completed;row->last_end_sequence=data_.sequence+1;row->last_end_tick=tick;row->failed+=status!=0;row->unentered+=(flags&1)==0;row->last_status=status;row->last_flags=flags;}else ++data_.unknown_routes;
  if(auto *row=route(id,rva)){row->last_phase=phase;row->last_argument=argument;}
  event(RouteEnd,tick,id,rva,(phase&0xffff)|((argument&0xffff)<<16),status,flags);
 }
 void guard(uint64_t tick,uint32_t category,uint64_t count,uint64_t limit,Context origin) noexcept {
  std::lock_guard<std::mutex> lock(mutex_);event(LimitGuard,tick,origin.target,origin.rva,category,8,0);
  Guard value{data_.sequence,tick,origin.target,origin.rva,origin.iterator,count,limit,category,origin.phase,origin.argument};
  const auto&g=data_.gateway;value.gateway_tick=g.tick;value.roots=g.roots;value.weak_roots=g.weak_roots;value.deferred=g.deferred;value.enqueued=g.enqueued;value.dequeued=g.dequeued;value.released=g.released;
  const auto&i=data_.iterators;value.iterator_tick=i.tick;value.iterator_entries=i.entries;value.iterator_active=i.active;value.iterator_terminal=i.terminal;
  data_.guards[data_.guard_total++%GuardLimit]=value;
  if(data_.guard_count<GuardLimit)++data_.guard_count;
 }
 void gateway(Gateway value) noexcept {std::lock_guard<std::mutex> lock(mutex_);value.samples=data_.gateway.samples+1;value.observed_root_high_water=std::max(value.roots,data_.gateway.observed_root_high_water);data_.gateway=value;}
 void iterators(Iterators value) noexcept {std::lock_guard<std::mutex> lock(mutex_);data_.iterators=value;}
 void failureDetail(uint64_t tick,FailureDetail value,Context origin) noexcept {
  std::lock_guard<std::mutex> guard(mutex_);value.tick=tick;value.target=origin.target;value.rva=origin.rva;value.iterator=origin.iterator;
  event(FailureDetailEvent,tick,value.target,value.rva,value.kind,value.status,0);value.sequence=data_.sequence;
  data_.details[data_.detail_total++%DetailLimit]=value;if(data_.detail_count<DetailLimit)++data_.detail_count;
 }
 void component(uint64_t tick,bool begin,uint32_t type,uint32_t message,int32_t status) noexcept {
  std::lock_guard<std::mutex> guard(mutex_);event(begin?ComponentBegin:ComponentEnd,tick,type,0,message,status,0);
 }
 void iterator(uint64_t tick,bool begin,uint64_t registration,uint32_t operation,int32_t status) noexcept {
  std::lock_guard<std::mutex> guard(mutex_);event(begin?IteratorBegin:IteratorEnd,tick,registration,0,operation,status,0);
 }
 void application(uint64_t tick,Application value) noexcept {
  std::lock_guard<std::mutex> guard(mutex_);if(data_.application.stage!=value.stage||data_.application.status!=value.status||data_.application.state!=value.state||data_.application.options_loaded!=value.options_loaded){
   event(Startup,tick,0,0,value.stage,value.status,value.flags);
  }data_.application=value;
 }
 void auth(uint64_t tick,uint32_t domain,int32_t code,uint64_t count) noexcept {
  std::lock_guard<std::mutex> guard(mutex_);data_.auth.domain=domain;data_.auth.code=code;data_.auth.count=count;event(Auth,tick,0,0,domain,code,0);
 }
 void authInstall(int32_t status) noexcept {std::lock_guard<std::mutex> guard(mutex_);data_.auth.install_status=status;}
 void authCounters(uint64_t requests,uint64_t successes,uint64_t errors,uint64_t overlaps) noexcept {
  std::lock_guard<std::mutex> guard(mutex_);data_.auth.requests=requests;data_.auth.successes=successes;data_.auth.errors=errors;data_.auth.overlaps=overlaps;
 }
 void eosLogin(uint32_t phase,int32_t result,int32_t status,uint64_t count) noexcept {
  if(phase<1||phase>2)return;
  std::lock_guard<std::mutex> guard(mutex_);data_.eos[phase-1]={status==0?result:0,status,count};
 }
 Snapshot snapshot() noexcept {std::lock_guard<std::mutex> guard(mutex_);return data_;}
};
inline State &state(){static State value;return value;}
}
