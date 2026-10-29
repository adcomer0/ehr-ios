#import <Foundation/Foundation.h>
#include "EHRManagedIteratorProduction.h"
#include "EHRRuntimeIteratorPrivate.h"
#include "EHRRuntimeWeak.h"
#include "EHRRuntimeDiagnostics.h"
#include <array>
#include <atomic>
#include <map>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>
#if __has_include("EHRHookBinding.generated.h")
#include "EHRHookBinding.generated.h"
#endif

namespace ehr_production_iterators {
constexpr uint64_t firstRegistration=UINT64_C(0x50524f4400000001);
constexpr uint64_t pastLastRegistration=UINT64_C(0x50524f4500000000);
constexpr bool registrationAvailable(uint64_t next){return next>=firstRegistration&&next<pastLastRegistration;}
struct Entry {
    uint64_t registration=0,source=0;
    EHRRuntimeToken weak=0,current=0,owner=0,coroutine=0;
    void *identity=nullptr,*currentIdentity=nullptr;
    EHRManagedIteratorCallbacksV1 callbacks{};
    bool executing=false,terminal=false,hasCurrent=false,cancelRequested=false,sourceClosed=false;
    bool failureRetire=false,failureStopAttempted=false;
};
struct State {
    std::mutex mutex;
    std::map<uint64_t,std::shared_ptr<Entry>> entries;
    std::unordered_map<void *,std::shared_ptr<Entry>> identities;
    uint64_t next=firstRegistration,cursor=0;
    uint64_t created=0,swept=0,closed=0,callbackFailures=0,temporaryPins=0;
    std::atomic<uint64_t> rejectedThreads{0};
    NSTimer *timer=nil;
    bool failureSealed=false,failureCleaning=false;
    int32_t failureStatus=EHR_RUNTIME_OK;
    uint64_t failureStopAttempts=0,failureStopFailures=0,failureCancelFailures=0;
};
State &state(){static State *s=new State;return *s;}
void publishDiagnostics(){
    if(!NSThread.isMainThread)return;
    auto&s=state();ehr_diagnostics::Iterators value;value.tick=EHRDiagnosticTick();
    {std::lock_guard<std::mutex>lock(s.mutex);value.entries=s.entries.size();value.pins=s.temporaryPins;
     value.created=s.created;value.swept=s.swept;value.closed=s.closed;value.callback_failures=s.callbackFailures;
     for(const auto&item:s.entries){const auto&e=*item.second;value.active+=!e.sourceClosed;value.terminal+=e.terminal;
      value.current+=e.current!=0;value.weak+=e.weak!=0;value.associations+=(e.owner!=0)+(e.coroutine!=0);}}
    ehr_diagnostics::state().iterators(value);
    EHRRuntimeGatewayPublishDiagnosticSnapshot();
}
constexpr bool hooksPresent(){
#if (defined(EHR_HAS_ITERATOR_HOOKS) && EHR_HAS_ITERATOR_HOOKS) || defined(EHR_PRODUCTION_ITERATOR_TEST_HOOKS)
    return true;
#else
    return false;
#endif
}
bool main(){if(NSThread.isMainThread)return true;++state().rejectedThreads;return false;}
std::shared_ptr<Entry> byId(uint64_t id){auto&s=state();std::lock_guard<std::mutex>g(s.mutex);auto i=s.entries.find(id);return i==s.entries.end()?nullptr:i->second;}
std::shared_ptr<Entry> byIdentity(void *identity){auto&s=state();std::lock_guard<std::mutex>g(s.mutex);auto i=s.identities.find(identity);return i==s.identities.end()?nullptr:i->second;}
bool issued(uint64_t id){auto&s=state();std::lock_guard<std::mutex>g(s.mutex);return registrationAvailable(id)&&id<s.next;}
bool terminalIdentity(const void *identity){auto&s=state();std::lock_guard<std::mutex>g(s.mutex);return EHRRuntimeIteratorIsTerminal(identity);}
bool ownedIdentity(void *identity){auto&s=state();std::lock_guard<std::mutex>g(s.mutex);return s.identities.count(identity)||EHRRuntimeIteratorIsTerminal(identity);}
struct Root {
    EHRRuntimeToken token=0;
    Root()=default;Root(const Root&)=delete;Root&operator=(const Root&)=delete;
    ~Root(){if(token&&ehr_runtime_object_release(token)!=EHR_RUNTIME_OK)++state().callbackFailures;}
    EHRRuntimeToken take(){auto t=token;token=0;return t;}
};
struct Lease {
    Root root;void *identity=nullptr;bool counted=false;
    EHRRuntimeStatus pin(const Entry &entry){auto status=EHRRuntimeIteratorPin(entry.weak,&root.token,&identity);if(status!=EHR_RUNTIME_OK)return status;
        if(identity!=entry.identity)return EHR_RUNTIME_TYPE_MISMATCH;++state().temporaryPins;counted=true;return EHR_RUNTIME_OK;}
    ~Lease(){if(counted)--state().temporaryPins;}
};
void release(EHRRuntimeToken &token){if(token){auto owned=token;token=0;if(ehr_runtime_object_release(owned)!=EHR_RUNTIME_OK)++state().callbackFailures;}}
void releaseCurrent(Entry&e){e.hasCurrent=false;e.currentIdentity=nullptr;release(e.current);}
int32_t cancelSource(Entry&e){if(e.sourceClosed)return EHR_RUNTIME_OK;e.sourceClosed=true;++state().closed;
    int32_t status=EHR_RUNTIME_MANAGED_EXCEPTION;{EHRDiagnosticIteratorScope trace(e.registration,3);@try{try{status=e.callbacks.cancel(e.source);}catch(...){status=EHR_RUNTIME_MANAGED_EXCEPTION;}}@catch(__unused NSException*error){status=EHR_RUNTIME_MANAGED_EXCEPTION;}trace.status=status;}
    if(status!=EHR_RUNTIME_OK)++state().callbackFailures;return status;}
bool unlinkLocked(const std::shared_ptr<Entry>&entry){auto&s=state();
    auto i=s.entries.find(entry->registration);if(i==s.entries.end()||i->second!=entry)return false;
    s.entries.erase(i);auto identity=s.identities.find(entry->identity);if(identity!=s.identities.end()&&identity->second==entry)s.identities.erase(identity);
    return true;
}
void releaseRegistration(Entry&e){release(e.weak);release(e.owner);release(e.coroutine);++state().swept;}
bool unlink(const std::shared_ptr<Entry>&entry){auto&s=state();{
    std::lock_guard<std::mutex>g(s.mutex);if(!unlinkLocked(entry))return false;}
    releaseRegistration(*entry);return true;
}
// The only per-terminal identity is inside its actual native carrier. Publish it
// through the runtime barrier BEFORE releasing the registry route/weak handle.
// Failed publication preserves the old bounded tombstone instead of falling
// through into the underlying ArrayList implementation.
bool retire(Entry&e){auto entry=byId(e.registration);if(!entry||entry.get()!=&e||e.executing)return false;
    Lease pin;auto status=pin.pin(e);
    if(status==EHR_RUNTIME_OK){bool removed=false;{
        auto&s=state();std::lock_guard<std::mutex>lock(s.mutex);
        // Only a reference field API runs under this lock: no callback, invoke,
        // root release or allocation. Worker lookup+payload inspection uses the
        // same mutex, including a lookup delayed from before registration.
        status=EHRRuntimeIteratorMarkTerminal(pin.root.token);
        if(status==EHR_RUNTIME_OK)removed=unlinkLocked(entry);}
        if(removed){releaseRegistration(e);return true;}}
    if(status!=EHR_RUNTIME_OK&&status!=EHR_RUNTIME_INVALID_TOKEN){++state().callbackFailures;return false;}
    return unlink(entry);
}
int32_t terminal(Entry&e){e.terminal=true;e.cancelRequested=false;releaseCurrent(e);const auto result=cancelSource(e);retire(e);return result;}
void erase(const std::shared_ptr<Entry>&entry){
    // Remove the route BEFORE callbacks: a recycled address cannot see old state.
    if(!unlink(entry))return;entry->terminal=true;entry->cancelRequested=false;releaseCurrent(*entry);cancelSource(*entry);
}
EHRRuntimeStatus validate(EHRRuntimeToken carrier){
    EHRRuntimeToken expected=0,actual=0;auto status=ehr_runtime_find_class("mscorlib.dll","System.Collections","ArrayList+ArrayListEnumeratorSimple",&expected);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_object_class(carrier,&actual);if(status!=EHR_RUNTIME_OK)return status;if(expected!=actual)return EHR_RUNTIME_TYPE_MISMATCH;
    struct Method {const char *name,*result;uint64_t rva;};constexpr std::array<Method,3>methods{{{"MoveNext","System.Boolean",0x367ade0},{"get_Current","System.Object",0x367afe4},{"Reset","System.Void",0x367b0dc}}};
    for(const auto&m:methods){EHRRuntimeToken token=0;uint64_t observed=0;status=ehr_runtime_find_method(expected,m.name,nullptr,0,m.result,0,&token);if(status==EHR_RUNTIME_OK)status=ehr_runtime_validate_native_method(token,m.rva,&observed);if(status!=EHR_RUNTIME_OK)return status;}
    return EHR_RUNTIME_OK;
}
EHRRuntimeStatus validateAssociation(EHRRuntimeToken owner,EHRRuntimeToken coroutine){
    EHRRuntimeToken actual=0,expected=0;auto status=ehr_runtime_object_class(coroutine,&actual);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","Coroutine",&expected);
    if(status!=EHR_RUNTIME_OK)return status;if(actual!=expected)return EHR_RUNTIME_TYPE_MISMATCH;
    EHRRuntimeToken mono=0,ownerClass=0,baseMethod=0,ownerMethod=0;
    status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","MonoBehaviour",&mono);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_object_class(owner,&ownerClass);
    const char *parameters[]={"System.Collections.IEnumerator"};
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(mono,"StartCoroutine",parameters,1,"UnityEngine.Coroutine",0,&baseMethod);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(ownerClass,"StartCoroutine",parameters,1,"UnityEngine.Coroutine",0,&ownerMethod);
    return status!=EHR_RUNTIME_OK?status:baseMethod==ownerMethod?EHR_RUNTIME_OK:EHR_RUNTIME_TYPE_MISMATCH;
}
int32_t sweep(uint32_t maximum,uint32_t *scanned,uint32_t *pruned);
bool ensureTimer(){auto&s=state();if(s.timer)return true;s.timer=[NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(__unused NSTimer*t){
    uint32_t scanned=0,pruned=0;@try{try{sweep(16,&scanned,&pruned);}catch(...){++state().callbackFailures;}}@catch(__unused NSException*e){++state().callbackFailures;}
    publishDiagnostics();auto&current=state();std::lock_guard<std::mutex>g(current.mutex);if(current.entries.empty()){[current.timer invalidate];current.timer=nil;}}];return s.timer!=nil;}
int32_t registerCarrier(EHRRuntimeToken carrier,uint64_t source,const EHRManagedIteratorCallbacksV1 *callbacks,uint64_t *registration){
    if(!registration)return EHR_RUNTIME_BAD_ARGUMENT;*registration=0;if(!main())return EHR_RUNTIME_WRONG_THREAD;
    if(state().failureSealed)return EHR_RUNTIME_NOT_READY;
    if(!source||!callbacks||callbacks->abi_version!=1||callbacks->byte_size!=sizeof(*callbacks)||!callbacks->step||!callbacks->reset||!callbacks->cancel)return EHR_RUNTIME_BAD_ARGUMENT;
    if(!hooksPresent())return EHR_RUNTIME_UNSUPPORTED;
    auto status=validate(carrier);if(status!=EHR_RUNTIME_OK)return status;
    Root pin;void *identity=nullptr;status=EHRRuntimeIteratorPin(carrier,&pin.token,&identity);if(status!=EHR_RUNTIME_OK)return status;
    if(EHRManagedIteratorOwnsIdentity(identity)||terminalIdentity(identity))return EHR_RUNTIME_BAD_ARGUMENT;
    if(auto previous=byIdentity(identity)){int32_t alive=0;status=ehr_runtime_object_weak_alive(previous->weak,&alive);if(status!=EHR_RUNTIME_OK)return status;if(alive)return EHR_RUNTIME_BAD_ARGUMENT;erase(previous);}
    auto&s=state();{std::lock_guard<std::mutex>g(s.mutex);if(s.entries.size()>=256||!registrationAvailable(s.next)){EHRDiagnosticLimit(s.entries.size()>=256?ehr_diagnostics::IteratorCapacity:ehr_diagnostics::IteratorTokenExhaustion,s.entries.size()>=256?s.entries.size():s.next,s.entries.size()>=256?256:pastLastRegistration-1);return EHR_RUNTIME_LIMIT;}}
    status=EHRRuntimeIteratorTerminalPrepare(pin.token);if(status!=EHR_RUNTIME_OK)return status;
    auto entry=std::make_shared<Entry>();Root weak;status=ehr_runtime_object_weak(pin.token,&weak.token);if(status!=EHR_RUNTIME_OK)return status;if(!ensureTimer())return EHR_RUNTIME_NOT_READY;
    entry->source=source;entry->identity=identity;entry->callbacks=*callbacks;entry->weak=weak.take();
    try{std::lock_guard<std::mutex>g(s.mutex);if(s.identities.count(identity)){release(entry->weak);return EHR_RUNTIME_BAD_ARGUMENT;}
        entry->registration=s.next;if(!s.entries.emplace(entry->registration,entry).second){release(entry->weak);return EHR_RUNTIME_BAD_ARGUMENT;}
        try{if(!s.identities.emplace(identity,entry).second){s.entries.erase(entry->registration);release(entry->weak);return EHR_RUNTIME_BAD_ARGUMENT;}}catch(...){s.entries.erase(entry->registration);throw;}
        // Commit only after both indexes succeed. The issued range has no gaps,
        // including allocation/validation failures, and needs no history map.
        ++s.next;}
    catch(...){release(entry->weak);EHRDiagnosticLimit(ehr_diagnostics::IteratorAllocation,0,0);return EHR_RUNTIME_LIMIT;}
    ++s.created;*registration=entry->registration;publishDiagnostics();return EHR_RUNTIME_OK;
}
int32_t acquire(uint64_t id,EHRRuntimeToken *owned){if(!owned)return EHR_RUNTIME_BAD_ARGUMENT;*owned=0;if(!main())return EHR_RUNTIME_WRONG_THREAD;auto e=byId(id);if(!e)return issued(id)?EHR_RUNTIME_UNSUPPORTED:EHR_RUNTIME_INVALID_TOKEN;
    if(state().failureSealed)return EHR_RUNTIME_NOT_READY;
    Lease pin;auto status=pin.pin(*e);if(status!=EHR_RUNTIME_OK){if(status==EHR_RUNTIME_INVALID_TOKEN&&!e->executing){erase(e);return EHR_RUNTIME_UNSUPPORTED;}return status;}
    if(e->terminal)return EHR_RUNTIME_UNSUPPORTED;*owned=pin.root.take();return EHR_RUNTIME_OK;
}
int32_t close(uint64_t id){if(!main())return EHR_RUNTIME_WRONG_THREAD;auto e=byId(id);if(!e)return issued(id)?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;if(e->executing){e->cancelRequested=true;return EHR_RUNTIME_OK;}return terminal(*e);}
int32_t associate(uint64_t id,EHRRuntimeToken owner,EHRRuntimeToken coroutine){if(!main())return EHR_RUNTIME_WRONG_THREAD;if(!owner||!coroutine)return EHR_RUNTIME_BAD_ARGUMENT;
    if(state().failureSealed)return EHR_RUNTIME_NOT_READY;
    auto e=byId(id);if(!e)return issued(id)?EHR_RUNTIME_UNSUPPORTED:EHR_RUNTIME_INVALID_TOKEN;if(e->terminal)return EHR_RUNTIME_UNSUPPORTED;
    Lease carrier;auto status=carrier.pin(*e);if(status!=EHR_RUNTIME_OK)return status;status=validateAssociation(owner,coroutine);if(status!=EHR_RUNTIME_OK)return status;
    if(e->owner||e->coroutine){int32_t sameOwner=0,sameCoroutine=0;status=ehr_runtime_object_same(e->owner,owner,&sameOwner);if(status==EHR_RUNTIME_OK)status=ehr_runtime_object_same(e->coroutine,coroutine,&sameCoroutine);return status!=EHR_RUNTIME_OK?status:sameOwner&&sameCoroutine?EHR_RUNTIME_OK:EHR_RUNTIME_BAD_ARGUMENT;}
    Root ownerWeak,coroutineWeak;status=ehr_runtime_object_weak(owner,&ownerWeak.token);if(status==EHR_RUNTIME_OK)status=ehr_runtime_object_weak(coroutine,&coroutineWeak.token);
    if(status==EHR_RUNTIME_OK){e->owner=ownerWeak.take();e->coroutine=coroutineWeak.take();}return status;
}
int32_t closeMatching(uint32_t kind,EHRRuntimeToken object,uint32_t *closed){if(!closed)return EHR_RUNTIME_BAD_ARGUMENT;*closed=0;if(!main())return EHR_RUNTIME_WRONG_THREAD;
    if(kind<1||kind>3||!object)return EHR_RUNTIME_BAD_ARGUMENT;Root pin;void *identity=nullptr;auto status=EHRRuntimeIteratorPin(object,&pin.token,&identity);if(status!=EHR_RUNTIME_OK)return status;
    std::vector<std::shared_ptr<Entry>>entries;{auto&s=state();std::lock_guard<std::mutex>g(s.mutex);for(auto&item:s.entries)entries.push_back(item.second);}
    int32_t first=EHR_RUNTIME_OK;for(auto&e:entries){if(e->terminal)continue;EHRRuntimeToken key=kind==1?e->weak:kind==2?e->coroutine:e->owner;if(!key)continue;
        int32_t alive=0;status=ehr_runtime_object_weak_alive(key,&alive);if(status!=EHR_RUNTIME_OK){if(first==0)first=status;continue;}if(!alive)continue;
        Root keyPin;void *keyIdentity=nullptr;status=EHRRuntimeIteratorPin(key,&keyPin.token,&keyIdentity);if(status!=EHR_RUNTIME_OK){if(first==0)first=status;continue;}if(keyIdentity!=identity)continue;
        status=static_cast<EHRRuntimeStatus>(close(e->registration));if(status==EHR_RUNTIME_OK)++*closed;else if(first==0)first=status;
    }return first;
}
int32_t sweep(uint32_t maximum,uint32_t *scanned,uint32_t *pruned){if(!scanned||!pruned||scanned==pruned)return EHR_RUNTIME_BAD_ARGUMENT;*scanned=*pruned=0;if(!main())return EHR_RUNTIME_WRONG_THREAD;if(!maximum||maximum>256)return EHR_RUNTIME_BAD_ARGUMENT;
    auto&s=state();std::vector<std::shared_ptr<Entry>>batch;{std::lock_guard<std::mutex>g(s.mutex);if(s.entries.empty())return EHR_RUNTIME_OK;auto i=s.entries.upper_bound(s.cursor);if(i==s.entries.end())i=s.entries.begin();const auto count=std::min<size_t>(maximum,s.entries.size());for(size_t n=0;n<count;++n){batch.push_back(i->second);if(++i==s.entries.end())i=s.entries.begin();}s.cursor=batch.back()->registration;}
    int32_t first=0;for(auto&e:batch){++*scanned;if(e->executing)continue;int32_t alive=0;auto status=ehr_runtime_object_weak_alive(e->weak,&alive);if(status!=EHR_RUNTIME_OK){if(!first)first=status;continue;}if(!alive){erase(e);++*pruned;}else if(e->terminal&&retire(*e))++*pruned;}
    return first;
}
int32_t copyStatus(EHRProductionIteratorStatusV1 *output,size_t bytes){if(!output||bytes!=sizeof(*output))return EHR_RUNTIME_BAD_ARGUMENT;*output={};if(!main())return EHR_RUNTIME_WRONG_THREAD;
    auto&s=state();std::lock_guard<std::mutex>g(s.mutex);*output={1,sizeof(*output),s.entries.size(),0,0,0,0,0,s.temporaryPins,s.created,s.swept,s.closed,s.callbackFailures,s.rejectedThreads.load()};
    for(auto&item:s.entries){const auto&e=*item.second;output->active_sources+=!e.sourceClosed;output->terminal_tombstones+=e.terminal;output->current_roots+=e.current!=0;output->carrier_weak_roots+=e.weak!=0;output->association_weak_roots+=(e.owner!=0)+(e.coroutine!=0);}return EHR_RUNTIME_OK;
}
void failureRecord(int32_t status){if(status!=EHR_RUNTIME_OK&&state().failureStatus==EHR_RUNTIME_OK)state().failureStatus=status;}
// Stop only the actual returned Coroutine associated with this registration.
// A shared native MonoBehaviour may also own unrelated vanilla coroutines.
int32_t failureStop(Entry&e){
    if(e.failureStopAttempted||e.sourceClosed||!e.owner||!e.coroutine)return EHR_RUNTIME_OK;
    e.failureStopAttempted=true;auto&s=state();++s.failureStopAttempts;
    Root owner,coroutine,result,exception;void *ignored=nullptr;
    int32_t ownerAlive=0,coroutineAlive=0;auto status=ehr_runtime_object_weak_alive(e.owner,&ownerAlive);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_object_weak_alive(e.coroutine,&coroutineAlive);
    if(status==EHR_RUNTIME_OK&&(!ownerAlive||!coroutineAlive))return EHR_RUNTIME_OK;
    if(status==EHR_RUNTIME_OK)status=EHRRuntimeIteratorPin(e.owner,&owner.token,&ignored);
    if(status==EHR_RUNTIME_OK)status=EHRRuntimeIteratorPin(e.coroutine,&coroutine.token,&ignored);
    if(status==EHR_RUNTIME_OK)status=validateAssociation(owner.token,coroutine.token);
    EHRRuntimeToken mono=0,ownerClass=0,baseMethod=0,ownerMethod=0;
    const char *parameters[]={"UnityEngine.Coroutine"};
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","MonoBehaviour",&mono);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_object_class(owner.token,&ownerClass);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(mono,"StopCoroutine",parameters,1,"System.Void",0,&baseMethod);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(ownerClass,"StopCoroutine",parameters,1,"System.Void",0,&ownerMethod);
    if(status==EHR_RUNTIME_OK&&baseMethod!=ownerMethod)status=EHR_RUNTIME_TYPE_MISMATCH;
    const EHRRuntimeArgument argument{EHR_RUNTIME_REFERENCE,0,coroutine.token,nullptr,0};
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_invoke(baseMethod,owner.token,&argument,1,&result.token,&exception.token);
    if(status!=EHR_RUNTIME_OK)++s.failureStopFailures;return status;
}
int32_t failureFinish(Entry&e,bool stopEngine){
    e.failureRetire=true;e.terminal=true;e.cancelRequested=true;
    if(e.executing)return EHR_RUNTIME_OK;
    if(stopEngine){int32_t stopped=EHR_RUNTIME_MANAGED_EXCEPTION;
        @try{try{stopped=failureStop(e);}catch(...){++state().failureStopFailures;}}@catch(__unused NSException*error){++state().failureStopFailures;}
        failureRecord(stopped);}
    const auto status=terminal(e);if(status!=EHR_RUNTIME_OK)++state().failureCancelFailures;failureRecord(status);
    release(e.owner);release(e.coroutine);return status;
}
int32_t failureCloseAll(EHRProductionIteratorFailureV1 *output,size_t bytes){
    if(!output||bytes!=sizeof(*output))return EHR_RUNTIME_BAD_ARGUMENT;*output={};
    if(!main())return EHR_RUNTIME_WRONG_THREAD;auto&s=state();s.failureSealed=true;
    if(!s.failureCleaning){s.failureCleaning=true;
        struct Cleaning{State&s;~Cleaning(){s.failureCleaning=false;}}guard{s};
        std::array<std::shared_ptr<Entry>,256>batch{};size_t count=0;
        {std::lock_guard<std::mutex>lock(s.mutex);for(auto&item:s.entries){if(count==batch.size()){failureRecord(EHR_RUNTIME_LIMIT);break;}batch[count++]=item.second;}}
        for(size_t n=0;n<count;++n){auto&e=*batch[n];e.failureRetire=true;e.terminal=true;e.cancelRequested=true;}
        for(size_t n=0;n<count;++n)failureFinish(*batch[n],true);
    }
    *output={1,sizeof(*output),s.failureStatus,1,0,0,s.failureStopAttempts,s.failureStopFailures,s.failureCancelFailures,0,0,0,0};
    {std::lock_guard<std::mutex>lock(s.mutex);for(auto&item:s.entries){const auto&e=*item.second;++output->entries;output->deferred+=e.failureRetire&&e.executing;output->active_sources+=!e.sourceClosed;output->current_roots+=e.current!=0;output->carrier_weak_roots+=e.weak!=0;output->association_weak_roots+=(e.owner!=0)+(e.coroutine!=0);}}
    return s.failureStatus;
}
template<class F>int32_t contained(F action){@try{try{return action();}catch(...){EHRDiagnosticLimit(ehr_diagnostics::NativeIteratorException,0,0);return EHR_RUNTIME_LIMIT;}}@catch(__unused NSException*e){return EHR_RUNTIME_MANAGED_EXCEPTION;}}
struct Executing{Entry&e;explicit Executing(Entry&value):e(value){e.executing=true;}~Executing(){e.executing=false;}};
// Null means an old collected registration was discarded, so the address now
// belongs to an ordinary native enumerator and MUST pass through unchanged.
std::shared_ptr<Entry> routed(void *identity,Lease &pin){auto e=byIdentity(identity);if(!e)return nullptr;auto status=pin.pin(*e);if(status==EHR_RUNTIME_INVALID_TOKEN){if(!e->executing)erase(e);return nullptr;}if(status!=EHR_RUNTIME_OK)EHRRuntimeIteratorRaise(status);return e;}
bool createsCurrentRootCycle(const Entry &source,void *value){
    // Registered native carriers yielded through RuntimeObject also need this
    // check; managed CLR nested-source ancestry checks alone cannot see them.
    for(unsigned depth=0;value&&depth<256;++depth){if(value==source.identity)return true;auto next=byIdentity(value);if(!next||!next->hasCurrent)return false;value=next->currentIdentity;}
    return value!=nullptr;
}
}
extern "C" void EHRManagedIteratorProductionMakeTable(EHRManagedIteratorProductionV1 *output){using namespace ehr_production_iterators;if(!output)return;*output={1,sizeof(*output),
    [](EHRRuntimeToken c,uint64_t s,const EHRManagedIteratorCallbacksV1*b,uint64_t*r)->int32_t{return contained([&]{return registerCarrier(c,s,b,r);});},
    [](uint64_t id,EHRRuntimeToken*r)->int32_t{return contained([&]{return acquire(id,r);});},
    [](uint64_t id)->int32_t{return contained([&]{return close(id);});},
    [](uint64_t id,EHRRuntimeToken o,EHRRuntimeToken c)->int32_t{return contained([&]{return associate(id,o,c);});},
    [](uint32_t k,EHRRuntimeToken o,uint32_t*n)->int32_t{return contained([&]{return closeMatching(k,o,n);});},
    [](uint32_t m,uint32_t*s,uint32_t*p)->int32_t{return contained([&]{return sweep(m,s,p);});},
    []()->int32_t{return NSThread.isMainThread?1:0;},
    [](EHRProductionIteratorStatusV1*s,size_t b)->int32_t{return contained([&]{return copyStatus(s,b);});}};}
extern "C" EHRRuntimeStatus EHRManagedIteratorProductionFailClosed(EHRProductionIteratorFailureV1 *output,size_t bytes){return static_cast<EHRRuntimeStatus>(ehr_production_iterators::contained([&]{return ehr_production_iterators::failureCloseAll(output,bytes);}));}
bool EHRProductionIteratorOwnsIdentity(void *identity){return ehr_production_iterators::ownedIdentity(identity);}
bool EHRProductionIteratorHasActiveIdentity(void *identity){using namespace ehr_production_iterators;
    if(!NSThread.isMainThread||!identity)return false;
    auto&s=state();std::lock_guard<std::mutex>lock(s.mutex);auto found=s.identities.find(identity);
    if(s.failureSealed||found==s.identities.end()||!found->second)return false;
    const auto&e=*found->second;auto registration=s.entries.find(e.registration);
    return registration!=s.entries.end()&&registration->second==found->second&&e.identity==identity&&e.weak&&
        !e.terminal&&!e.sourceClosed&&!e.failureRetire&&!e.cancelRequested&&!e.executing;
}
bool EHRProductionIteratorMoveNext(void *identity,bool *result){using namespace ehr_production_iterators;if(!result)abort();*result=false;
    if(!NSThread.isMainThread){if(!ownedIdentity(identity))return false;++state().rejectedThreads;return true;}
    Lease pin;auto e=routed(identity,pin);if(!e)return terminalIdentity(identity);if(e->executing){e->cancelRequested=true;EHRRuntimeIteratorRaise(EHR_RUNTIME_BAD_ARGUMENT);}if(e->terminal)return true;
    releaseCurrent(*e);int32_t next=0,status=EHR_RUNTIME_MANAGED_EXCEPTION;EHRRuntimeToken current=0;
    {EHRDiagnosticIteratorScope trace(e->registration,1);Executing guard(*e);@try{try{status=e->callbacks.step(e->source,&next,&current);}catch(...){status=EHR_RUNTIME_MANAGED_EXCEPTION;}}@catch(__unused NSException*error){status=EHR_RUNTIME_MANAGED_EXCEPTION;}trace.status=status;if(status!=EHR_RUNTIME_OK)publishDiagnostics();if(status==EHR_RUNTIME_LIMIT)EHRDiagnosticLimit(ehr_diagnostics::CallbackReturnedLimit,0,0);}
    if(e->failureRetire){release(current);failureFinish(*e,false);return true;}
    if(status!=EHR_RUNTIME_OK||e->cancelRequested||(next!=0&&next!=1)||(!next&&current)){
        release(current);terminal(*e);++state().callbackFailures;EHRRuntimeIteratorRaise(status==EHR_RUNTIME_UNSUPPORTED?EHR_RUNTIME_UNSUPPORTED:EHR_RUNTIME_BAD_ARGUMENT);}
    if(!next){terminal(*e);return true;}
    if(current){void *value=nullptr;status=EHRRuntimeIteratorBorrow(current,&value);if(status!=EHR_RUNTIME_OK||!value){release(current);terminal(*e);EHRRuntimeIteratorRaise(EHR_RUNTIME_INVALID_TOKEN);}
        if(createsCurrentRootCycle(*e,value)){release(current);terminal(*e);EHRRuntimeIteratorRaise(EHR_RUNTIME_UNSUPPORTED);}e->currentIdentity=value;}
    e->current=current;e->hasCurrent=true;*result=true;return true;
}
bool EHRProductionIteratorCurrent(void *identity,void **result){using namespace ehr_production_iterators;if(!result)abort();*result=nullptr;
    if(!NSThread.isMainThread){if(!ownedIdentity(identity))return false;++state().rejectedThreads;return true;}
    Lease pin;auto e=routed(identity,pin);if(!e){if(terminalIdentity(identity))EHRRuntimeIteratorRaise(EHR_RUNTIME_BAD_ARGUMENT);return false;}if(e->executing){e->cancelRequested=true;EHRRuntimeIteratorRaise(EHR_RUNTIME_BAD_ARGUMENT);}if(!e->hasCurrent)EHRRuntimeIteratorRaise(EHR_RUNTIME_BAD_ARGUMENT);
    if(EHRRuntimeIteratorBorrow(e->current,result)!=EHR_RUNTIME_OK)EHRRuntimeIteratorRaise(EHR_RUNTIME_INVALID_TOKEN);return true;
}
bool EHRProductionIteratorReset(void *identity){using namespace ehr_production_iterators;
    if(!NSThread.isMainThread){if(!ownedIdentity(identity))return false;++state().rejectedThreads;return true;}
    Lease pin;auto e=routed(identity,pin);if(!e){if(terminalIdentity(identity))EHRRuntimeIteratorRaise(EHR_RUNTIME_UNSUPPORTED);return false;}if(e->executing){e->cancelRequested=true;EHRRuntimeIteratorRaise(EHR_RUNTIME_BAD_ARGUMENT);}if(e->terminal)EHRRuntimeIteratorRaise(EHR_RUNTIME_UNSUPPORTED);
    int32_t status=EHR_RUNTIME_MANAGED_EXCEPTION;{EHRDiagnosticIteratorScope trace(e->registration,2);Executing guard(*e);@try{try{status=e->callbacks.reset(e->source);}catch(...){status=EHR_RUNTIME_MANAGED_EXCEPTION;}}@catch(__unused NSException*error){status=EHR_RUNTIME_MANAGED_EXCEPTION;}trace.status=status;}
    if(e->failureRetire){failureFinish(*e,true);return true;}
    if(e->cancelRequested){terminal(*e);EHRRuntimeIteratorRaise(EHR_RUNTIME_BAD_ARGUMENT);}if(status!=0)EHRRuntimeIteratorRaise(status==EHR_RUNTIME_UNSUPPORTED?EHR_RUNTIME_UNSUPPORTED:EHR_RUNTIME_BAD_ARGUMENT);releaseCurrent(*e);return true;
}
