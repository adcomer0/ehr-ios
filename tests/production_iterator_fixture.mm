#import <Foundation/Foundation.h>
#if !defined(EHR_TEST_PRODUCTION_NO_HOOKS)
#define EHR_PRODUCTION_ITERATOR_TEST_HOOKS 1
#endif
#ifndef EHR_PRODUCTION_SOURCE
#define EHR_PRODUCTION_SOURCE "../native/EHRManagedIteratorProduction.mm"
#endif
#include EHR_PRODUCTION_SOURCE
#if defined(EHR_COMBINED_ADAPTER)
#include EHR_COMBINED_ADAPTER
#endif
#include <cassert>
#include <cstdio>
#include <functional>
#include <thread>
#include <stdexcept>
#include <unordered_set>

namespace fixture {
struct Object{uint64_t klass=0;bool alive=true;bool terminal=false;};
struct Handle{Object *object;bool weak;};
std::unordered_map<uint64_t,Handle> handles;
uint64_t nextToken=1,pins=0;unsigned checks=0,runtimeCalls=0;
void *legacyIdentity=nullptr;
constexpr uint64_t Enumerator=1001,Value=1002,Mono=1003,Coroutine=1004,Foreign=1005,DerivedMono=1006;
std::unordered_map<uint64_t,unsigned>steps,cancels,resets,otherSteps,otherCancels;
Object yielded{Value};Object *selfYield=nullptr,*cycleA=nullptr,*cycleB=nullptr;EHRManagedIteratorProductionV1 host{};uint64_t closeDuringStep=0;
EHRProductionIteratorFailureV1 duringFailure{};Object *failingStopHandle=nullptr;
bool failureReset=false,throwStop=false;
unsigned failureReads=0,failureFlushes=0;uint64_t failureSource=0;
bool failMarker=false,failWeak=false;size_t markerWrites=0;
bool exercisePublication=false;std::atomic<bool>publicationTried{false},publicationFinished{false};
std::thread publicationWorker;bool publicationHandled=false;
std::unordered_map<Object*,unsigned>engineStops;
void require(bool value){++checks;if(!value){fprintf(stderr,"check %u failed\n",checks);abort();}}
void touch(){require(NSThread.isMainThread);++runtimeCalls;}
uint64_t root(Object&object,bool weak=false){const auto token=nextToken++;handles.emplace(token,Handle{&object,weak});return token;}
size_t strong(Object&object){size_t count=0;for(auto&p:handles)count+=p.second.object==&object&&!p.second.weak;return count;}
void collect(Object&object){require(strong(object)==0);object.alive=false;}
int raised(std::function<void()> action){try{action();return 0;}catch(EHRRuntimeStatus status){return status;}}
EHRProductionIteratorStatusV1 status(){EHRProductionIteratorStatusV1 value{};require(host.copy_status(&value,sizeof(value))==0);require(value.temporary_pins==0);return value;}
void release(uint64_t token){require(ehr_runtime_object_release(token)==0);}
int32_t step(uint64_t source,int32_t *next,uint64_t *current){++steps[source];*current=0;
 if(source==404){*next=1;*current=root(yielded);require(EHRManagedIteratorProductionFailClosed(&duringFailure,sizeof(duringFailure))==6);require(duringFailure.deferred==1&&duringFailure.active_sources==1);require(cancels[404]==0);return 0;}
 if(source==401){*next=1;*current=root(yielded);return 0;}
 if(source==61){*next=0;return EHR_RUNTIME_LIMIT;}
 if(source==50){*next=1;if(closeDuringStep){auto entry=ehr_production_iterators::byId(closeDuringStep);require(entry&&entry->executing&&!EHRProductionIteratorHasActiveIdentity(entry->identity));require(host.close(closeDuringStep)==0);}return 0;}
 if(source==51){*next=0;*current=root(yielded);return EHR_RUNTIME_UNSUPPORTED;}
 if(source==52){*next=1;*current=root(*selfYield);return 0;}
 if(source==53||source==54){*next=1;*current=root(source==53?*cycleB:*cycleA);return 0;}
 if(source>=100){*next=1;return 0;}
 *next=steps[source]<3;if(steps[source]==2)*current=root(yielded);return 0;}
int32_t reset(uint64_t source){++resets[source];if(source==404&&failureReset){require(EHRManagedIteratorProductionFailClosed(&duringFailure,sizeof(duringFailure))==6);require(duringFailure.deferred==1&&duringFailure.active_sources==1&&cancels[404]==0);return 0;}return source==60?0:7;}
int32_t cancel(uint64_t source){++cancels[source];if(source==401){EHRProductionIteratorFailureV1 nested{};require(EHRManagedIteratorProductionFailClosed(&nested,sizeof(nested))==0&&nested.sealed==1);}return source==403?4:0;}
int32_t stepOther(uint64_t source,int32_t *next,uint64_t *current){++otherSteps[source];*next=0;*current=0;return 0;}
int32_t cancelOther(uint64_t source){++otherCancels[source];return 0;}
int32_t readFailure(uint64_t source,uint64_t *words,size_t count){
 ++failureReads;require(count==12&&words&&cancels[source]==0);failureSource=source;
 if(source!=51&&source!=61)return 3;
 const uint64_t status=source==51?7:8;const uint64_t values[12]={1,12,source,12345,3,source==51?5u:2u,status,status,source,0,0,0};
 std::copy(std::begin(values),std::end(values),words);return 0;
}
int32_t otherFailureReader(uint64_t,uint64_t *,size_t){return 3;}
int32_t flushFailure(){++failureFlushes;require(ehr_diagnostics::state().snapshot().iterators.callback_failures>0);if(failureSource)require(cancels[failureSource]==1);return 0;}
const EHRManagedIteratorCallbacksV1 callbacks{1,sizeof(callbacks),step,reset,cancel};
const EHRManagedIteratorCallbacksV1 callbacksOther{1,sizeof(callbacksOther),stepOther,reset,cancelOther};
uint64_t add(Object&object,uint64_t source,uint64_t *owned=nullptr,const EHRManagedIteratorCallbacksV1 *cb=&callbacks){auto token=root(object);uint64_t id=0;require(host.register_carrier(token,source,cb,&id)==0&&id);if(owned)*owned=token;else release(token);return id;}
void finish(Object&object,uint64_t owned){release(owned);collect(object);uint32_t scanned=0,pruned=0;require(host.sweep(256,&scanned,&pruned)==0);}
}
#if !defined(EHR_COMBINED_ADAPTER)
bool EHRManagedIteratorOwnsIdentity(void *identity){return fixture::legacyIdentity==identity;}
#endif
// Numeric snapshot publication has its own actual gateway fixture.
void EHRRuntimeGatewayPublishDiagnosticSnapshot(void) noexcept {}
extern "C" EHRRuntimeStatus ehr_runtime_find_class(const char*,const char*,const char*name,uint64_t *output){fixture::touch();*output=!strcmp(name,"ArrayList+ArrayListEnumeratorSimple")?fixture::Enumerator:!strcmp(name,"MonoBehaviour")?fixture::Mono:!strcmp(name,"Coroutine")?fixture::Coroutine:0;return *output?EHR_RUNTIME_OK:EHR_RUNTIME_NOT_FOUND;}
extern "C" EHRRuntimeStatus ehr_runtime_find_method(uint64_t klass,const char *name,const char*const*parameters,size_t count,const char*result,int isStatic,uint64_t *output){fixture::touch();*output=0;if(klass==fixture::Enumerator){*output=!strcmp(name,"MoveNext")?2001:!strcmp(name,"get_Current")?2002:!strcmp(name,"Reset")?2003:0;}else if((klass==fixture::Mono||klass==fixture::DerivedMono)&&!strcmp(name,"StartCoroutine"))*output=2004;else if((klass==fixture::Mono||klass==fixture::DerivedMono)&&!strcmp(name,"StopCoroutine")){fixture::require(count==1&&parameters&&!strcmp(parameters[0],"UnityEngine.Coroutine")&&!strcmp(result,"System.Void")&&!isStatic);*output=2005;}return *output?EHR_RUNTIME_OK:EHR_RUNTIME_NOT_FOUND;}
extern "C" EHRRuntimeStatus ehr_runtime_invoke(uint64_t method,uint64_t receiver,const EHRRuntimeArgument *arguments,size_t count,uint64_t *result,uint64_t *exception){fixture::touch();*result=*exception=0;fixture::require(method==2005&&count==1&&arguments&&arguments->kind==EHR_RUNTIME_REFERENCE);auto owner=fixture::handles.find(receiver),coroutine=fixture::handles.find(arguments->token);fixture::require(owner!=fixture::handles.end()&&owner->second.object->klass==fixture::DerivedMono&&coroutine!=fixture::handles.end()&&coroutine->second.object->klass==fixture::Coroutine);++fixture::engineStops[coroutine->second.object];if(coroutine->second.object==fixture::failingStopHandle){if(fixture::throwStop)throw std::runtime_error("owned stop exception");*exception=fixture::root(fixture::yielded);return EHR_RUNTIME_MANAGED_EXCEPTION;}return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_validate_native_method(uint64_t method,uint64_t rva,uint64_t *observed){fixture::touch();*observed=rva;return (method==2001&&rva==0x367ade0)||(method==2002&&rva==0x367afe4)||(method==2003&&rva==0x367b0dc)?EHR_RUNTIME_OK:EHR_RUNTIME_TYPE_MISMATCH;}
extern "C" EHRRuntimeStatus ehr_runtime_object_class(uint64_t token,uint64_t *output){fixture::touch();*output=0;auto i=fixture::handles.find(token);if(i==fixture::handles.end()||!i->second.object->alive)return EHR_RUNTIME_INVALID_TOKEN;*output=i->second.object->klass;return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_release(uint64_t token){fixture::touch();return fixture::handles.erase(token)?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;}
extern "C" EHRRuntimeStatus ehr_runtime_object_weak(uint64_t token,uint64_t *output){fixture::touch();*output=0;if(fixture::failWeak)return EHR_RUNTIME_LIMIT;auto i=fixture::handles.find(token);if(i==fixture::handles.end()||!i->second.object->alive)return EHR_RUNTIME_INVALID_TOKEN;*output=fixture::root(*i->second.object,true);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_weak_alive(uint64_t token,int32_t *output){fixture::touch();*output=0;auto i=fixture::handles.find(token);if(i==fixture::handles.end()||!i->second.weak)return EHR_RUNTIME_INVALID_TOKEN;*output=i->second.object->alive;return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_same(uint64_t left,uint64_t right,int32_t *output){fixture::touch();*output=0;auto a=fixture::handles.find(left),b=fixture::handles.find(right);if(a==fixture::handles.end()||b==fixture::handles.end()||!a->second.object->alive||!b->second.object->alive)return EHR_RUNTIME_INVALID_TOKEN;*output=a->second.object==b->second.object;return EHR_RUNTIME_OK;}
EHRRuntimeStatus EHRRuntimeIteratorPin(uint64_t token,uint64_t *owned,void **identity){fixture::touch();*owned=0;*identity=nullptr;auto i=fixture::handles.find(token);if(i==fixture::handles.end()||!i->second.object->alive)return EHR_RUNTIME_INVALID_TOKEN;*identity=i->second.object;*owned=fixture::root(*i->second.object);++fixture::pins;return EHR_RUNTIME_OK;}
EHRRuntimeStatus EHRRuntimeIteratorBorrow(uint64_t token,void **object){fixture::touch();*object=nullptr;if(!token)return EHR_RUNTIME_OK;auto i=fixture::handles.find(token);if(i==fixture::handles.end()||!i->second.object->alive)return EHR_RUNTIME_INVALID_TOKEN;if(i->second.weak)return EHR_RUNTIME_UNSUPPORTED;*object=i->second.object;return EHR_RUNTIME_OK;}
EHRRuntimeStatus EHRRuntimeIteratorTerminalPrepare(uint64_t token){fixture::touch();auto i=fixture::handles.find(token);return i!=fixture::handles.end()&&i->second.object->klass==fixture::Enumerator?EHR_RUNTIME_OK:EHR_RUNTIME_TYPE_MISMATCH;}
EHRRuntimeStatus EHRRuntimeIteratorMarkTerminal(uint64_t token){fixture::touch();if(fixture::failMarker)return EHR_RUNTIME_TYPE_MISMATCH;auto i=fixture::handles.find(token);if(i==fixture::handles.end()||!i->second.object->alive)return EHR_RUNTIME_INVALID_TOKEN;fixture::require(i->second.object->klass==fixture::Enumerator&&!i->second.weak);
 if(fixture::exercisePublication){auto*object=i->second.object;fixture::publicationWorker=std::thread([object]{auto&mutex=ehr_production_iterators::state().mutex;if(mutex.try_lock())abort();fixture::publicationTried.store(true);bool moved=true;fixture::publicationHandled=EHRProductionIteratorMoveNext(object,&moved)&&!moved;fixture::publicationFinished.store(true);});while(!fixture::publicationTried.load())std::this_thread::yield();fixture::require(!fixture::publicationFinished.load());}
 i->second.object->terminal=true;++fixture::markerWrites;return EHR_RUNTIME_OK;}
bool EHRRuntimeIteratorIsTerminal(const void *identity) noexcept {const auto*object=static_cast<const fixture::Object*>(identity);return object&&object->klass==fixture::Enumerator&&object->terminal;}
void EHRRuntimeIteratorRaise(EHRRuntimeStatus status){throw status;}

int main(){@autoreleasepool{using namespace fixture;EHRManagedIteratorProductionMakeTable(&host);require(host.byte_size==72&&sizeof(EHRProductionIteratorStatusV1)==104&&host.is_main()==1);
#if defined(EHR_TEST_PRODUCTION_NO_HOOKS)
 Object unsupported{Enumerator};auto unsupportedRoot=root(unsupported);uint64_t unsupportedId=7;require(host.register_carrier(unsupportedRoot,1,&callbacks,&unsupportedId)==7&&unsupportedId==0);release(unsupportedRoot);require(handles.empty()&&status().entries==0);printf("PASS %u no-hook production registration rejection checks; no game executed\n",checks);return 0;
#endif
 require(!EHRManagedIteratorProductionFailureDiagnosticsBound());
 require(EHRManagedIteratorProductionSetFailureDiagnostics(nullptr,flushFailure)==4);
 int wrongBind=0;std::thread bindWorker([&]{wrongBind=EHRManagedIteratorProductionSetFailureDiagnostics(readFailure,flushFailure);});bindWorker.join();require(wrongBind==2);
 require(EHRManagedIteratorProductionSetFailureDiagnostics(readFailure,flushFailure)==0&&EHRManagedIteratorProductionFailureDiagnosticsBound());
 require(EHRManagedIteratorProductionSetFailureDiagnostics(readFailure,flushFailure)==0);
 require(EHRManagedIteratorProductionSetFailureDiagnostics(otherFailureReader,flushFailure)==4);
 // Synthetic registry population exercises the actual existing256 guard;
 // no managed object/native entry is manufactured by production code.
 {auto&registry=ehr_production_iterators::state();for(uint64_t i=1;i<=256;++i)registry.entries.emplace(i,std::make_shared<ehr_production_iterators::Entry>());
  Object rejected{Enumerator};auto token=root(rejected);uint64_t rejectedId=7;
  require(host.register_carrier(token,999,&callbacks,&rejectedId)==EHR_RUNTIME_LIMIT&&rejectedId==0);
  auto proof=ehr_diagnostics::state().snapshot();const auto&guard=proof.guards[(proof.guard_total-1)%ehr_diagnostics::GuardLimit];
  require(guard.category==ehr_diagnostics::IteratorCapacity&&guard.count==256&&guard.limit==256);
  registry.entries.clear();release(token);require(handles.empty());}
 require(status().entries==0);uint64_t id=99;require(host.register_carrier(0,0,nullptr,&id)==4&&id==0);
 Object carrier{Enumerator},ordinary{Enumerator},foreign{Foreign};auto invalid=root(foreign);require(host.register_carrier(invalid,1,&callbacks,&id)==5&&id==0);release(invalid);
 uint64_t owned=0;id=add(carrier,1,&owned);require(strong(carrier)==1);require(status().carrier_weak_roots==1&&status().active_sources==1);
 auto predicateCalls=runtimeCalls;require(EHRProductionIteratorHasActiveIdentity(&carrier)&&!EHRProductionIteratorHasActiveIdentity(&ordinary)&&!EHRProductionIteratorHasActiveIdentity(nullptr)&&runtimeCalls==predicateCalls);
 uint64_t acquired=0;require(host.acquire(id,&acquired)==0&&acquired!=owned&&strong(carrier)==2);release(acquired);
 uint64_t duplicate=0;require(host.register_carrier(owned,2,&callbacksOther,&duplicate)==4&&!duplicate);
 bool next=true;void *current=reinterpret_cast<void*>(1);require(!EHRProductionIteratorMoveNext(&ordinary,&next));require(raised([&]{EHRProductionIteratorCurrent(&carrier,&current);})==4);
 require(raised([&]{EHRProductionIteratorReset(&carrier);})==7&&resets[1]==1);require(EHRProductionIteratorMoveNext(&carrier,&next)&&next&&steps[1]==1);
 require(EHRProductionIteratorCurrent(&carrier,&current)&&current==nullptr);require(EHRProductionIteratorMoveNext(&carrier,&next)&&next&&steps[1]==2);
 require(EHRProductionIteratorCurrent(&carrier,&current)&&current==&yielded);void *again=nullptr;require(EHRProductionIteratorCurrent(&carrier,&again)&&again==current);require(status().current_roots==1&&strong(yielded)==1);
 require(raised([&]{EHRProductionIteratorReset(&carrier);})==7&&status().current_roots==1);
 require(EHRProductionIteratorMoveNext(&carrier,&next)&&!next&&cancels[1]==1);require(EHRProductionIteratorMoveNext(&carrier,&next)&&!next&&steps[1]==3&&cancels[1]==1);
 auto terminalStatus=status();require(terminalStatus.entries==0&&terminalStatus.active_sources==0&&terminalStatus.terminal_tombstones==0&&terminalStatus.carrier_weak_roots==0&&terminalStatus.current_roots==0&&strong(yielded)==0);
 require(!EHRProductionIteratorHasActiveIdentity(&carrier)&&EHRProductionIteratorOwnsIdentity(&carrier));
 require(host.register_carrier(owned,2,&callbacks,&duplicate)==4&&duplicate==0&&EHRProductionIteratorOwnsIdentity(&carrier));
 require(host.acquire(id,&acquired)==7&&acquired==0);require(host.close(id)==0&&cancels[1]==1);require(raised([&]{EHRProductionIteratorCurrent(&carrier,&current);})==4);require(raised([&]{EHRProductionIteratorReset(&carrier);})==7);finish(carrier,owned);require(status().entries==0);
 Object second{Enumerator};id=add(second,1,&owned,&callbacksOther);require(EHRProductionIteratorMoveNext(&second,&next)&&!next&&otherSteps[1]==1&&otherCancels[1]==1&&steps[1]==3);finish(second,owned);
 Object assoc{Enumerator},owner{DerivedMono},handle{Coroutine},otherOwner{DerivedMono},otherHandle{Coroutine};id=add(assoc,100,&owned);auto ownerToken=root(owner),handleToken=root(handle),foreignToken=root(foreign),otherOwnerToken=root(otherOwner),otherHandleToken=root(otherHandle);
 require(host.associate(id,ownerToken,foreignToken)==5);require(host.associate(id,ownerToken,handleToken)==0);require(host.associate(id,ownerToken,handleToken)==0);require(host.associate(id,otherOwnerToken,otherHandleToken)==4);require(status().association_weak_roots==2&&strong(owner)==1&&strong(handle)==1);
 uint32_t closed=0;require(host.close_matching(EHR_ITERATOR_MATCH_OWNER,otherOwnerToken,&closed)==0&&closed==0);require(host.close_matching(EHR_ITERATOR_MATCH_COROUTINE,handleToken,&closed)==0&&closed==1&&cancels[100]==1);require(host.close_matching(EHR_ITERATOR_MATCH_CARRIER,owned,&closed)==0&&closed==0);finish(assoc,owned);
 release(ownerToken);release(handleToken);release(foreignToken);release(otherOwnerToken);release(otherHandleToken);
 Object weakAssoc{Enumerator},weakOwner{DerivedMono},weakCoroutine{Coroutine};id=add(weakAssoc,107,&owned);ownerToken=root(weakOwner);handleToken=root(weakCoroutine);
 require(host.associate(id,ownerToken,handleToken)==0);release(ownerToken);release(handleToken);collect(weakOwner);collect(weakCoroutine);
 uint32_t weakScanned=0,weakPruned=0;require(host.sweep(256,&weakScanned,&weakPruned)==0&&weakPruned==0&&cancels[107]==0);require(EHRProductionIteratorMoveNext(&weakAssoc,&next)&&next);
 require(host.close_matching(EHR_ITERATOR_MATCH_CARRIER,owned,&closed)==0&&closed==1&&cancels[107]==1);finish(weakAssoc,owned);
 Object legacy{Enumerator};auto legacyRoot=root(legacy);
#if defined(EHR_COMBINED_ADAPTER)
 EHRManagedIteratorHostV1 oldHost{};EHRManagedIteratorMakeTable(&oldHost);require(EHRManagedIteratorSetCallbacks(&callbacks)==0);uint64_t oldId=0;require(oldHost.register_carrier(legacyRoot,202,&oldId)==0);
#else
 legacyIdentity=&legacy;
#endif
 require(host.register_carrier(legacyRoot,2,&callbacks,&id)==4&&id==0);
#if defined(EHR_COMBINED_ADAPTER)
 Object productionOwned{Enumerator};uint64_t productionRoot=0;auto productionId=add(productionOwned,201,&productionRoot);uint64_t rejectedOld=0;require(oldHost.register_carrier(productionRoot,203,&rejectedOld)==4&&rejectedOld==0);
 require(EHRManagedIteratorMoveNext(&productionOwned,&next)&&next&&steps[201]==1);require(EHRManagedIteratorMoveNext(&legacy,&next)&&next&&steps[202]==1);require(host.close(productionId)==0);finish(productionOwned,productionRoot);require(oldHost.release_carrier(oldId)==0&&cancels[202]==1);require(EHRManagedIteratorRegistrationCount()==0);
#else
 legacyIdentity=nullptr;
#endif
 release(legacyRoot);
 Object abandoned{Enumerator};id=add(abandoned,101);require(strong(abandoned)==0);collect(abandoned);uint32_t scanned=0,pruned=0;require(host.sweep(1,&scanned,&pruned)==0&&scanned==1&&pruned==1&&cancels[101]==1&&status().entries==0);require(host.acquire(id,&acquired)==7&&acquired==0&&host.close(id)==0);
 Object recycled{Enumerator};id=add(recycled,102);collect(recycled);recycled.alive=true; // public weak handles must remember the OLD identity generation; mark old handles collected explicitly.
 for(auto&pair:handles)if(pair.second.object==&recycled)pair.second.object=&abandoned;
 require(!EHRProductionIteratorMoveNext(&recycled,&next)&&cancels[102]==1&&!EHRProductionIteratorOwnsIdentity(&recycled));
 Object reentrant{Enumerator};id=add(reentrant,50,&owned);closeDuringStep=id;require(raised([&]{EHRProductionIteratorMoveNext(&reentrant,&next);})==4&&cancels[50]==1);closeDuringStep=0;finish(reentrant,owned);
 Object failing{Enumerator};id=add(failing,51,&owned);require(raised([&]{EHRProductionIteratorMoveNext(&failing,&next);})==7&&cancels[51]==1&&strong(yielded)==0);finish(failing,owned);
 Object selfCycle{Enumerator};selfYield=&selfCycle;id=add(selfCycle,52,&owned);require(raised([&]{EHRProductionIteratorMoveNext(&selfCycle,&next);})==7&&cancels[52]==1&&strong(selfCycle)==1);finish(selfCycle,owned);selfYield=nullptr;
 Object nativeCycleA{Enumerator},nativeCycleB{Enumerator};cycleA=&nativeCycleA;cycleB=&nativeCycleB;uint64_t cycleRootA=0,cycleRootB=0;auto cycleIdA=add(nativeCycleA,53,&cycleRootA);add(nativeCycleB,54,&cycleRootB);
 require(EHRProductionIteratorMoveNext(&nativeCycleA,&next)&&next);require(raised([&]{EHRProductionIteratorMoveNext(&nativeCycleB,&next);})==7&&cancels[54]==1);require(host.close(cycleIdA)==0);finish(nativeCycleA,cycleRootA);finish(nativeCycleB,cycleRootB);cycleA=cycleB=nullptr;
 Object resettable{Enumerator};id=add(resettable,60,&owned);require(EHRProductionIteratorMoveNext(&resettable,&next)&&next);require(EHRProductionIteratorReset(&resettable)&&resets[60]==1);require(raised([&]{EHRProductionIteratorCurrent(&resettable,&current);})==4);require(host.close(id)==0);finish(resettable,owned);
 Object limitedStep{Enumerator};id=add(limitedStep,61,&owned);
 require(raised([&]{EHRProductionIteratorMoveNext(&limitedStep,&next);})==EHR_RUNTIME_BAD_ARGUMENT&&cancels[61]==1);
 require(failureReads==2&&failureFlushes==3&&failureSource==61);
 {auto proof=ehr_diagnostics::state().snapshot();const auto&detail=proof.details[(proof.detail_total-1)%ehr_diagnostics::DetailLimit];require(detail.kind==3&&detail.source_id==61&&detail.iterator_type_hash==12345&&detail.iterator==id&&detail.stage==3&&detail.exception_kind==2&&detail.status==8&&detail.primary_status==8);}
 {auto proof=ehr_diagnostics::state().snapshot();const auto&guard=proof.guards[(proof.guard_total-1)%ehr_diagnostics::GuardLimit];
  require(guard.category==ehr_diagnostics::CallbackReturnedLimit&&guard.iterator==id&&guard.count==0&&guard.limit==0&&guard.iterator_entries==1&&guard.iterator_active==1);}
 finish(limitedStep,owned);
 Object workerCarrier{Enumerator};id=add(workerCarrier,103,&owned);auto calls=runtimeCalls;int wrong=0;std::thread worker([&]{uint64_t result=7;wrong=host.acquire(id,&result);require(result==0&&!EHRProductionIteratorHasActiveIdentity(&workerCarrier));bool resultNext=true;require(EHRProductionIteratorMoveNext(&workerCarrier,&resultNext)&&!resultNext);require(!EHRProductionIteratorMoveNext(&ordinary,&resultNext));require(host.is_main()==0);});worker.join();require(wrong==2&&runtimeCalls==calls&&steps[103]==0);require(host.close(id)==0);finish(workerCarrier,owned);
 // Retained terminal identities no longer consume registry/weak-handle slots.
 // Keep all 1024 real fixture receivers alive while one source stays active.
 Object longLived{Enumerator};uint64_t longRoot=0;auto longId=add(longLived,800,&longRoot);
 std::array<Object,1024>retained{};std::array<uint64_t,1024>retainedRoots{},retainedIds{};
 for(size_t n=0;n<retained.size();++n){retained[n].klass=Enumerator;retainedIds[n]=add(retained[n],10000+n,&retainedRoots[n],&callbacksOther);
  require(EHRProductionIteratorMoveNext(&retained[n],&next)&&!next&&otherCancels[10000+n]==1);
  const auto snapshot=status();require(snapshot.entries==1&&snapshot.active_sources==1&&snapshot.terminal_tombstones==0&&snapshot.carrier_weak_roots==1&&snapshot.current_roots==0);}
 for(size_t n=0;n<retained.size();++n){const auto before=runtimeCalls;
  require(EHRProductionIteratorMoveNext(&retained[n],&next)&&!next&&runtimeCalls==before);
  require(raised([&]{EHRProductionIteratorCurrent(&retained[n],&current);})==4);
  require(raised([&]{EHRProductionIteratorReset(&retained[n]);})==7);
  require(host.acquire(retainedIds[n],&acquired)==7&&acquired==0&&host.close(retainedIds[n])==0&&otherCancels[10000+n]==1);
  require(host.register_carrier(retainedRoots[n],900,&callbacks,&duplicate)==4&&duplicate==0);}
 calls=runtimeCalls;std::thread terminalWorker([&]{for(auto&object:retained){bool moved=true;void*value=reinterpret_cast<void*>(1);require(EHRProductionIteratorMoveNext(&object,&moved)&&!moved);require(EHRProductionIteratorCurrent(&object,&value)&&!value);require(EHRProductionIteratorReset(&object));}require(!EHRProductionIteratorMoveNext(&ordinary,&next));});terminalWorker.join();require(runtimeCalls==calls);
 for(size_t n=0;n<retained.size();++n){release(retainedRoots[n]);collect(retained[n]);}
 require(host.sweep(256,&scanned,&pruned)==0&&pruned==0&&status().entries==1);require(host.close(longId)==0);finish(longLived,longRoot);
 // Registration failures do not publish IDs. Thus the compact issued range
 // cannot misclassify a failed or future registration as a closed source.
 auto&registry=ehr_production_iterators::state();const auto unissued=registry.next;
 require(ehr_production_iterators::registrationAvailable(ehr_production_iterators::firstRegistration)&&ehr_production_iterators::registrationAvailable(ehr_production_iterators::pastLastRegistration-1)&&!ehr_production_iterators::registrationAvailable(ehr_production_iterators::pastLastRegistration)&&!ehr_production_iterators::registrationAvailable(UINT64_MAX)&&!ehr_production_iterators::registrationAvailable(0));
 Object failedAdd{Enumerator};auto failedRoot=root(failedAdd);failWeak=true;id=42;
 require(host.register_carrier(failedRoot,700,&callbacks,&id)==8&&id==0&&registry.next==unissued);failWeak=false;
 require(host.acquire(unissued,&acquired)==9&&acquired==0&&host.close(unissued)==9);
 require(host.acquire(ehr_production_iterators::firstRegistration-1,&acquired)==9&&host.close(UINT64_MAX)==9);
 registry.next=ehr_production_iterators::pastLastRegistration;require(host.register_carrier(failedRoot,700,&callbacks,&id)==8&&id==0&&registry.next==ehr_production_iterators::pastLastRegistration);registry.next=unissued;
 id=add(failedAdd,701,&owned);require(id==unissued);release(failedRoot);require(host.close(id)==0);finish(failedAdd,owned);
 Object collectedAtAcquire{Enumerator};id=add(collectedAtAcquire,703);collect(collectedAtAcquire);
 require(host.acquire(id,&acquired)==7&&acquired==0&&cancels[703]==1&&host.close(id)==0&&status().entries==0);
 // Registry publication is one critical section: a concurrent worker can see
 // either the active map or the final marker, never an original-fallthrough gap.
 Object concurrentTerminal{Enumerator};id=add(concurrentTerminal,704,&owned);calls=runtimeCalls;exercisePublication=true;
 require(host.close(id)==0);exercisePublication=false;publicationWorker.join();require(publicationFinished&&publicationHandled&&cancels[704]==1);
 require(runtimeCalls>calls&&status().entries==0);finish(concurrentTerminal,owned);
 // Reusing that fixture address represents a newly allocated native object,
 // whose payload is freshly initialized and must pass through to the original.
 concurrentTerminal=Object{Enumerator};require(!EHRProductionIteratorMoveNext(&concurrentTerminal,&next)&&!EHRProductionIteratorOwnsIdentity(&concurrentTerminal));
 // A barrier failure keeps a routed tombstone; sweep retries rather than
 // returning an owned terminal receiver to the unrelated original method.
 Object publicationFailure{Enumerator};id=add(publicationFailure,702,&owned);failMarker=true;
 require(host.close(id)==0&&cancels[702]==1&&status().terminal_tombstones==1&&status().entries==1);
 require(!EHRProductionIteratorHasActiveIdentity(&publicationFailure)&&EHRProductionIteratorOwnsIdentity(&publicationFailure));
 require(EHRProductionIteratorMoveNext(&publicationFailure,&next)&&!next&&host.acquire(id,&acquired)==7);
 require(raised([&]{EHRProductionIteratorCurrent(&publicationFailure,&current);})==4&&raised([&]{EHRProductionIteratorReset(&publicationFailure);})==7);
 failMarker=false;require(host.sweep(256,&scanned,&pruned)==0&&pruned==1&&status().entries==0&&cancels[702]==1);finish(publicationFailure,owned);
 Object fairA{Enumerator},fairB{Enumerator},fairC{Enumerator};add(fairA,104);add(fairB,105);add(fairC,106);collect(fairA);collect(fairB);collect(fairC);for(int i=0;i<3;++i)require(host.sweep(1,&scanned,&pruned)==0&&scanned==1&&pruned==1);require(status().entries==0);
 auto end=status();require(end.active_sources==0&&end.current_roots==0&&end.carrier_weak_roots==0&&end.association_weak_roots==0&&end.temporary_pins==0&&handles.empty());
 // Failure shutdown is permanent, contained, reentrant-safe and exact-handle only.
 EHRProductionIteratorFailureV1 failure{};require(EHRManagedIteratorProductionFailClosed(nullptr,sizeof(failure))==4);
 require(EHRManagedIteratorProductionFailClosed(&failure,sizeof(failure)-1)==4);failureReset=getenv("EHR_FAILURE_RESET")!=nullptr;throwStop=getenv("EHR_FAILURE_THROW_STOP")!=nullptr;
 int wrongCleanup=0;std::thread cleanupWorker([&]{wrongCleanup=EHRManagedIteratorProductionFailClosed(&failure,sizeof(failure));});cleanupWorker.join();require(wrongCleanup==2);
 Object shutdownA{Enumerator},shutdownB{Enumerator},shutdownC{Enumerator},shutdownD{Enumerator},completedCarrier{Enumerator};
 Object shutdownOwner{DerivedMono},shutdownHandleA{Coroutine},shutdownHandleC{Coroutine},unrelatedNativeHandle{Coroutine},completedHandle{Coroutine};
 uint64_t shutdownRootA=0,shutdownRootB=0,shutdownRootC=0,shutdownRootD=0,completedRoot=0;
 auto shutdownIdA=add(shutdownA,401,&shutdownRootA);add(shutdownB,402,&shutdownRootB);auto shutdownIdC=add(shutdownC,403,&shutdownRootC);add(shutdownD,404,&shutdownRootD);auto completedId=add(completedCarrier,406,&completedRoot);
 auto shutdownOwnerRoot=root(shutdownOwner),shutdownHandleARoot=root(shutdownHandleA),shutdownHandleCRoot=root(shutdownHandleC),unrelatedRoot=root(unrelatedNativeHandle),completedHandleRoot=root(completedHandle);
 require(host.associate(shutdownIdA,shutdownOwnerRoot,shutdownHandleARoot)==0);require(host.associate(shutdownIdC,shutdownOwnerRoot,shutdownHandleCRoot)==0);failingStopHandle=&shutdownHandleC;
 require(host.associate(completedId,shutdownOwnerRoot,completedHandleRoot)==0);require(host.close(completedId)==0&&cancels[406]==1);
 require(EHRProductionIteratorMoveNext(&shutdownA,&next)&&next&&strong(yielded)==1);
 if(failureReset)require(EHRProductionIteratorReset(&shutdownD));else require(EHRProductionIteratorMoveNext(&shutdownD,&next)&&!next);
 require(cancels[401]==1&&cancels[402]==1&&cancels[403]==1&&cancels[404]==1&&strong(yielded)==0);
 require(engineStops[&shutdownHandleA]==1&&engineStops[&shutdownHandleC]==1&&engineStops[&unrelatedNativeHandle]==0&&engineStops[&completedHandle]==0&&cancels[406]==1);
 require(EHRManagedIteratorProductionFailClosed(&failure,sizeof(failure))==6&&failure.sealed==1&&failure.entries==0&&failure.deferred==0&&failure.active_sources==0&&failure.current_roots==0&&failure.association_weak_roots==0&&failure.carrier_weak_roots==0&&failure.engine_stop_attempts==2&&failure.engine_stop_failures==1&&failure.cancel_failures==1);
 require(EHRManagedIteratorProductionFailClosed(&failure,sizeof(failure))==6&&cancels[404]==1&&engineStops[&shutdownHandleA]==1);
 uint64_t noRegistration=1,noAcquired=1;require(host.register_carrier(shutdownRootA,999,&callbacks,&noRegistration)==1&&noRegistration==0);require(host.acquire(shutdownIdA,&noAcquired)==7&&noAcquired==0);
 require(EHRProductionIteratorMoveNext(&shutdownA,&next)&&!next&&steps[401]==1);require(!EHRProductionIteratorMoveNext(&ordinary,&next));
 finish(shutdownA,shutdownRootA);finish(shutdownB,shutdownRootB);finish(shutdownC,shutdownRootC);finish(shutdownD,shutdownRootD);finish(completedCarrier,completedRoot);
 release(shutdownOwnerRoot);release(shutdownHandleARoot);release(shutdownHandleCRoot);release(unrelatedRoot);release(completedHandleRoot);failingStopHandle=nullptr;
 end=status();require(end.entries==0&&end.active_sources==0&&end.current_roots==0&&end.carrier_weak_roots==0&&end.association_weak_roots==0&&end.temporary_pins==0&&handles.empty());
 [ehr_production_iterators::state().timer invalidate];ehr_production_iterators::state().timer=nil;
 printf("PASS %u production weak iterator lifecycle checks; old strong ABI unchanged; no game executed\n",checks);
}}
