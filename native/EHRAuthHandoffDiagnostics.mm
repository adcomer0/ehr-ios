#include "EHRAuthHandoffDiagnostics.h"
#include "EHRAuthHandoffBinding.generated.h"
#include "EHRNativeHooks.h"
#include "EHRRuntimeGateway.h"
#include "EHRRuntimeMetadataPrivate.h"
#include <array>
#include <atomic>
#include <limits>
#include <mutex>
#include <time.h>

namespace {
using ScalarGetter = int32_t (*)(const void *, const void *);
using CredentialsCallback = void (*)(void *, void *, const void *);
using LoginCallback = void (*)(void *, void *, void *, void *, const void *);
constexpr uint64_t counterLimit = 1000000;
constexpr size_t eventCapacity = 32;
enum Phase : size_t { AppleSuccess, ManagedEnter, ManagedReturn, LoginEnter,
    CredentialType, LoginReturn, EOSNormal, EOSSilent, PhaseCount };
struct Event {
    uint64_t sequence=0,monotonicNs=0,loginScopeSerial=0;
    uint32_t phase=0;
    int32_t status=0,scalarValue=0;
};
struct State {
    uint64_t sequence=0, activeLogins=0, outOfScope=0, unknownTypes=0;
    uint64_t nextScopeSerial=0,eventOverwrites=0;
    size_t eventCount=0,eventWrite=0;
    std::array<Event,eventCapacity> events{};
    std::array<uint64_t,PhaseCount> counts{}, sequences{};
    int32_t lastType=0,lastTypeStatus=EHR_RUNTIME_NOT_READY;
    std::array<int32_t,2> eosResults{},eosStatuses{EHR_RUNTIME_NOT_READY,EHR_RUNTIME_NOT_READY};
};
State state;
std::mutex stateMutex;
std::atomic<uint64_t> faults{0};
std::atomic<int32_t> prepared{EHR_RUNTIME_NOT_READY};
std::atomic<ScalarGetter> typeGetter{nullptr};
std::atomic<const void *> getterMetadata{nullptr};
thread_local unsigned loginDepth=0;
thread_local uint64_t loginScopeSerial=0;
void increment(uint64_t &count) noexcept { if (count<counterLimit) ++count; }
void fault() noexcept {
    auto value=faults.load(std::memory_order_relaxed);
    while (value<counterLimit && !faults.compare_exchange_weak(value,value+1,std::memory_order_relaxed)) {}
}
void event(State &s,Phase phase,int32_t status=0,int32_t value=0,uint64_t monotonicNs=0,uint64_t scope=0) noexcept {
    if (s.sequence<std::numeric_limits<uint64_t>::max()) ++s.sequence;
    increment(s.counts[phase]); s.sequences[phase]=s.sequence;
    if (phase==CredentialType) {
        s.lastTypeStatus=status; s.lastType=status==EHR_RUNTIME_OK?value:0;
        if (status!=EHR_RUNTIME_OK) increment(s.unknownTypes);
    }
    if (phase==EOSNormal || phase==EOSSilent) {
        const size_t index=phase==EOSNormal?0:1;
        s.eosStatuses[index]=status; s.eosResults[index]=status==EHR_RUNTIME_OK?value:0;
    }
    // Only these public scalar observations have a value. An unavailable read
    // must never turn a supplied placeholder into an apparently known result.
    const bool scalar=phase==CredentialType || phase==EOSNormal || phase==EOSSilent;
    s.events[s.eventWrite]={s.sequence,monotonicNs,scope,static_cast<uint32_t>(phase),
        status,scalar && status==EHR_RUNTIME_OK?value:0};
    s.eventWrite=(s.eventWrite+1)%eventCapacity;
    if(s.eventCount<eventCapacity) ++s.eventCount;
    else increment(s.eventOverwrites);
}
const Event &orderedEvent(const State &s,size_t index) noexcept {
    return s.events[(s.eventWrite+eventCapacity-s.eventCount+index)%eventCapacity];
}
uint64_t monotonicTimeNs() noexcept {
    timespec now{};
    if(clock_gettime(CLOCK_MONOTONIC,&now) || now.tv_sec<0 || now.tv_nsec<0 || now.tv_nsec>=1000000000 ||
        static_cast<uint64_t>(now.tv_sec)>(std::numeric_limits<uint64_t>::max()-static_cast<uint64_t>(now.tv_nsec))/1000000000) {
        fault();return 0; // Explicit unavailable timestamp, never wall-clock data.
    }
    return static_cast<uint64_t>(now.tv_sec)*1000000000+static_cast<uint64_t>(now.tv_nsec);
}
void record(Phase phase,int32_t status=0,int32_t value=0) noexcept {
    try {
        std::lock_guard<std::mutex> lock(stateMutex);
        // Timestamp under the same lock as sequence assignment, so concurrent
        // publishers cannot invert an otherwise monotonic event history.
        const auto scope=(phase==LoginEnter || phase==CredentialType || phase==LoginReturn)?loginScopeSerial:0;
        event(state,phase,status,value,monotonicTimeNs(),scope);
    }
    catch (...) { fault(); }
}
bool onMainThread() noexcept {
    @try { return NSThread.isMainThread; }
    @catch (__unused NSException *error) { fault(); return false; }
}
struct LoginScope {
    unsigned previous;
    uint64_t previousSerial;
    LoginScope() noexcept:previous(loginDepth),previousSerial(loginScopeSerial) {
        if (onMainThread() && loginDepth<std::numeric_limits<unsigned>::max()) ++loginDepth;
        loginScopeSerial=0;
        try {
            std::lock_guard<std::mutex> lock(stateMutex);increment(state.activeLogins);
            if(state.nextScopeSerial<std::numeric_limits<uint64_t>::max()) loginScopeSerial=++state.nextScopeSerial;
        }
        catch (...) { fault(); }
    }
    ~LoginScope() noexcept {
        loginDepth=previous;
        loginScopeSerial=previousSerial;
        try { std::lock_guard<std::mutex> lock(stateMutex); if(state.activeLogins) --state.activeLogins; }
        catch (...) { fault(); }
    }
};
void observeType(const void *credentials) noexcept {
    if (!onMainThread() || !loginDepth) {
        try { std::lock_guard<std::mutex> lock(stateMutex); increment(state.outOfScope); }
        catch (...) { fault(); }
        return;
    }
    int32_t status=prepared.load(std::memory_order_acquire),value=0;
    @try { try {
        const auto getter=typeGetter.load(std::memory_order_acquire);
        const auto metadata=getterMetadata.load(std::memory_order_acquire);
        if (!credentials) status=EHR_RUNTIME_BAD_ARGUMENT;
        else if (status==EHR_RUNTIME_OK && getter && metadata) value=getter(credentials,metadata);
        else if (status==EHR_RUNTIME_OK) status=EHR_RUNTIME_NOT_READY;
    } catch (...) { status=EHR_RUNTIME_UNSUPPORTED; fault(); } }
    @catch (__unused NSException *error) { status=EHR_RUNTIME_UNSUPPORTED; fault(); }
    record(CredentialType,status,value);
}
EHRRuntimeStatus validate(EHRRuntimeToken owner,const char *name,const char *const *parameters,
    size_t count,const char *returns,uint64_t rva,EHRRuntimeToken *method) {
    auto status=ehr_runtime_find_method(owner,name,parameters,count,returns,0,method);
    if(status!=EHR_RUNTIME_OK) return status;
    uint64_t observed=0;
    return ehr_runtime_validate_native_method(*method,rva,&observed);
}
int32_t prepare() {
    if(!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    if(prepared.load(std::memory_order_acquire)==EHR_RUNTIME_OK) return EHR_RUNTIME_OK;
    EHRRuntimeToken manager=0,connect=0,internal=0,credentials=0,method=0,getter=0;
    auto status=ehr_runtime_find_class("Assembly-CSharp.dll","","EOSManager",&manager);
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_find_class("Assembly-CSharp-firstpass.dll",
        "Epic.OnlineServices.Connect","ConnectInterface",&connect);
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_find_class("Assembly-CSharp-firstpass.dll",
        "Epic.OnlineServices.Connect","CredentialsInternal",&internal);
    if(status==EHR_RUNTIME_OK) status=ehr_runtime_find_class("Assembly-CSharp-firstpass.dll",
        "Epic.OnlineServices.Connect","Credentials",&credentials);
    const char *credentialParameters[]={"AppleAuth.Interfaces.ICredential"};
    const char *loginParameters[]={"Epic.OnlineServices.Connect.LoginOptions&","System.Object",
        "Epic.OnlineServices.Connect.OnLoginCallback"};
    const char *setParameters[]={"Epic.OnlineServices.Connect.Credentials&"};
    if(status==EHR_RUNTIME_OK) status=validate(manager,"OnGetCredentials",credentialParameters,1,"System.Void",0x1b15150,&method);
    if(status==EHR_RUNTIME_OK) status=validate(connect,"Login",loginParameters,3,"System.Void",0x1aab220,&method);
    if(status==EHR_RUNTIME_OK) status=validate(internal,"Set",setParameters,1,"System.Void",0x1aad608,&method);
    if(status==EHR_RUNTIME_OK) status=validate(credentials,"get_Type",nullptr,0,
        "Epic.OnlineServices.ExternalCredentialType",EHRAuthHandoffCredentialTypeGetterRVA,&getter);
    const void *metadata=nullptr,*owner=nullptr;
    if(status==EHR_RUNTIME_OK) status=EHRRuntimeBorrowMethod(getter,&metadata,&owner);
    if(status==EHR_RUNTIME_OK && (!metadata || !owner)) status=EHR_RUNTIME_NOT_READY;
    if(status==EHR_RUNTIME_OK) {
        // The exact getter is a pinned scalar leaf: no calls, class initialization,
        // allocations, token reads, mixed-reference copies or ownership transfer.
        getterMetadata.store(metadata,std::memory_order_release);
        typeGetter.store(reinterpret_cast<ScalarGetter>(EHRNativeHooksImageBaseForDiagnostics()+
            EHRAuthHandoffCredentialTypeGetterRVA),std::memory_order_release);
    }
    prepared.store(status,std::memory_order_release); return status;
}
}

extern "C" int32_t EHRAuthHandoffDiagnosticsPrepare(void) {
    @try { try { return prepare(); } catch (...) { fault(); prepared.store(EHR_RUNTIME_UNSUPPORTED); } }
    @catch (__unused NSException *error) { fault(); prepared.store(EHR_RUNTIME_UNSUPPORTED); }
    return EHR_RUNTIME_UNSUPPORTED;
}
extern "C" void EHRAuthHandoffDiagnosticsRecordAppleSuccess(void) { record(AppleSuccess); }
extern "C" void EHRAuthHandoffDiagnosticsRecordEOSResult(uint32_t channel,int32_t status,int32_t result) {
    if(channel!=1 && channel!=2) { fault(); return; }
    record(channel==1?EOSNormal:EOSSilent,status,result);
}
extern "C" NSDictionary<NSString *,id> *EHRAuthHandoffDiagnosticsCopyStatus(void) {
    State s; { std::lock_guard<std::mutex> lock(stateMutex); s=state; }
    NSMutableArray<NSDictionary *> *events=[NSMutableArray arrayWithCapacity:s.eventCount];
    for(size_t index=0;index<s.eventCount;++index) {
        const auto &e=orderedEvent(s,index);
        [events addObject:@{@"sequence":@(e.sequence),@"monotonicNs":@(e.monotonicNs),@"phase":@(e.phase),
            @"status":@(e.status),@"scalarValue":@(e.scalarValue),@"loginScopeSerial":@(e.loginScopeSerial)}];
    }
    return @{@"schemaVersion":@2,@"preparedStatus":@(prepared.load()),@"phaseSequence":@(s.sequence),
        @"eventCapacity":@(eventCapacity),@"eventCount":@(s.eventCount),@"eventOverwrites":@(s.eventOverwrites),@"events":[events copy],
        @"appleSuccesses":@(s.counts[AppleSuccess]),@"appleSuccessSequence":@(s.sequences[AppleSuccess]),
        @"managedCredentialEntries":@(s.counts[ManagedEnter]),@"managedCredentialEntrySequence":@(s.sequences[ManagedEnter]),
        @"managedCredentialReturns":@(s.counts[ManagedReturn]),@"managedCredentialReturnSequence":@(s.sequences[ManagedReturn]),
        @"loginEntries":@(s.counts[LoginEnter]),@"loginEntrySequence":@(s.sequences[LoginEnter]),
        @"loginReturns":@(s.counts[LoginReturn]),@"loginReturnSequence":@(s.sequences[LoginReturn]),
        @"typeObservations":@(s.counts[CredentialType]),@"typeSequence":@(s.sequences[CredentialType]),
        @"lastCredentialType":@(s.lastType),@"lastTypeStatus":@(s.lastTypeStatus),@"unknownTypeObservations":@(s.unknownTypes),
        @"normalEOSResults":@(s.counts[EOSNormal]),@"normalEOSSequence":@(s.sequences[EOSNormal]),
        @"normalEOSStatus":@(s.eosStatuses[0]),@"normalEOSResultCode":@(s.eosResults[0]),
        @"silentEOSResults":@(s.counts[EOSSilent]),@"silentEOSSequence":@(s.sequences[EOSSilent]),
        @"silentEOSStatus":@(s.eosStatuses[1]),@"silentEOSResultCode":@(s.eosResults[1]),
        @"activeLoginCalls":@(s.activeLogins),@"outOfScopeSetForwards":@(s.outOfScope),@"observerFaults":@(faults.load()),
        @"declaredCredentialsApiVersionStatic":@1,@"declaredLoginApiVersionStatic":@2};
}
extern "C" NSDictionary<NSString *,id> *EHRAuthHandoffDiagnosticsSelfTest(void) {
    State s; uint32_t checks=0,failures=0;
    auto check=[&](bool value){++checks;if(!value)++failures;};
    event(s,AppleSuccess);event(s,ManagedEnter);event(s,ManagedReturn);event(s,LoginEnter);
    event(s,CredentialType,0,11);event(s,LoginReturn);event(s,EOSNormal,0,7000);
    check(s.sequence==7);check(s.counts[AppleSuccess]==1);check(s.counts[ManagedEnter]==1);
    check(s.counts[ManagedReturn]==1);check(s.counts[LoginEnter]==1);check(s.counts[LoginReturn]==1);
    check(s.counts[CredentialType]==1);check(s.lastType==11);check(s.lastTypeStatus==0);
    check(s.sequences[AppleSuccess]<s.sequences[ManagedEnter]);check(s.sequences[ManagedReturn]<s.sequences[LoginEnter]);
    check(s.sequences[CredentialType]<s.sequences[EOSNormal]);check(s.eosResults[0]==7000);check(s.eosStatuses[0]==0);
    event(s,CredentialType,EHR_RUNTIME_NOT_READY,11);check(s.lastType==0);check(s.unknownTypes==1);
    event(s,EOSSilent,EHR_RUNTIME_UNSUPPORTED,7000);check(s.eosResults[1]==0);check(s.eosStatuses[1]==EHR_RUNTIME_UNSUPPORTED);
    s.counts[AppleSuccess]=counterLimit;event(s,AppleSuccess);check(s.counts[AppleSuccess]==counterLimit);
    s.sequence=std::numeric_limits<uint64_t>::max();event(s,AppleSuccess);check(s.sequence==std::numeric_limits<uint64_t>::max());
    State ring;
    event(ring,AppleSuccess,0,0,10);event(ring,ManagedEnter,0,0,20);event(ring,ManagedReturn,0,0,30);
    event(ring,LoginEnter,0,0,40,1);event(ring,CredentialType,0,11,50,1);event(ring,LoginReturn,0,0,60,1);
    event(ring,EOSNormal,0,7000,70);event(ring,LoginEnter,0,0,80,2);
    event(ring,CredentialType,0,10,90,2);event(ring,LoginReturn,0,0,100,2);
    check(ring.lastType==10);check(ring.eventCount==10);check(ring.eventWrite==10);
    check(orderedEvent(ring,4).scalarValue==11);check(orderedEvent(ring,4).phase==CredentialType);
    check(orderedEvent(ring,4).loginScopeSerial==1);check(orderedEvent(ring,8).scalarValue==10);
    check(orderedEvent(ring,8).loginScopeSerial==2);check(orderedEvent(ring,6).scalarValue==7000);
    for(size_t i=1;i<ring.eventCount;++i) {
        check(orderedEvent(ring,i).sequence==orderedEvent(ring,i-1).sequence+1);
        check(orderedEvent(ring,i).monotonicNs>orderedEvent(ring,i-1).monotonicNs);
    }
    event(ring,CredentialType,EHR_RUNTIME_NOT_READY,11,110,3);
    check(orderedEvent(ring,10).scalarValue==0);check(orderedEvent(ring,10).status==EHR_RUNTIME_NOT_READY);
    for(size_t i=0;i<eventCapacity+7;++i) event(ring,AppleSuccess,0,0,120+i);
    check(ring.eventCount==eventCapacity);check(ring.eventWrite<eventCapacity);check(ring.eventOverwrites==18);
    check(orderedEvent(ring,0).sequence==19);check(orderedEvent(ring,eventCapacity-1).sequence==50);
    check(ring.counts[CredentialType]==3);check(ring.unknownTypes==1);
    for(size_t i=1;i<eventCapacity;++i) check(orderedEvent(ring,i).sequence==orderedEvent(ring,i-1).sequence+1);
    const auto status=NSThread.isMainThread?prepared.load():EHR_RUNTIME_WRONG_THREAD;
    return @{@"schema":@"ehr.auth-handoff-proof.v1",@"success":@(failures==0 && status==0),
        @"status":@(status),@"preparedStatus":@(prepared.load()),@"checks":@(checks),@"failures":@(failures),@"isolatedRecorder":@YES,
        @"eventCapacity":@(eventCapacity),@"eventRingBounded":@YES,@"middleAppleTypePreserved":@YES,@"unknownScalarRedacted":@YES,
        @"actualCredentialReads":@0,@"originalAuthCalls":@0,@"networkRequests":@0,@"accountActions":@0,
        @"realAuthenticationInvoked":@NO,@"credentialsRead":@NO,@"networkOperations":@NO,
        @"runtimeExecutableWrites":@NO};
}
extern "C" __attribute__((visibility("default")))
void ehr_native_auth_handoff_credentials(void *self,void *credential,const void *method) {
    const auto original=reinterpret_cast<CredentialsCallback>(EHRNativeHooksImageBaseForDiagnostics()+EHRAuthHandoffCredentialsTrampolineRVA);
    record(ManagedEnter); original(self,credential,method); record(ManagedReturn);
}
extern "C" __attribute__((visibility("default")))
void ehr_native_auth_handoff_login(void *self,void *options,void *clientData,void *callback,const void *method) {
    const auto original=reinterpret_cast<LoginCallback>(EHRNativeHooksImageBaseForDiagnostics()+EHRAuthHandoffLoginTrampolineRVA);
    LoginScope scope; record(LoginEnter); original(self,options,clientData,callback,method); record(LoginReturn);
}
extern "C" __attribute__((visibility("default")))
void ehr_native_auth_handoff_set(void *self,void *credentials,const void *method) {
    const auto original=reinterpret_cast<CredentialsCallback>(EHRNativeHooksImageBaseForDiagnostics()+EHRAuthHandoffSetTrampolineRVA);
    observeType(credentials); original(self,credentials,method);
}
