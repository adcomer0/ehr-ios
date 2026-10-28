// Include after helperExport() is defined, before the XCTest @implementation.
// Own ArrayList objects only. No scene, scheduler, account, network or GC calls.
#include "native/EHRRuntimeReflection.h"
#include "native/include/EHRManagedIteratorProductionV1.h"
#include <array>
#include <cstdint>

namespace ehr_retirement_proof {
constexpr size_t Count=1024;
constexpr uint64_t SourceBase=UINT64_C(0x4558525400000000);
struct CallbackState {
    std::array<uint32_t,Count+2> steps{},cancels{};
    bool running=false,fault=false;
};
CallbackState callbacksState;
bool sourceIndex(uint64_t source,size_t &index) {
    if(!NSThread.isMainThread||source<SourceBase||source-SourceBase>=Count+2||!callbacksState.running){callbacksState.fault=true;return false;}
    index=static_cast<size_t>(source-SourceBase);return true;
}
int32_t step(uint64_t source,int32_t *next,EHRRuntimeToken *current) {
    if(!next||!current)return EHR_RUNTIME_BAD_ARGUMENT;*next=0;*current=0;
    size_t index=0;if(!sourceIndex(source,index))return EHR_RUNTIME_BAD_ARGUMENT;
    ++callbacksState.steps[index];return EHR_RUNTIME_OK;
}
int32_t reset(uint64_t) {return EHR_RUNTIME_UNSUPPORTED;}
int32_t cancel(uint64_t source) {
    size_t index=0;if(!sourceIndex(source,index))return EHR_RUNTIME_BAD_ARGUMENT;
    ++callbacksState.cancels[index];return EHR_RUNTIME_OK;
}
struct Failure {uint32_t stage;int32_t status;};
struct Probe {
    decltype(&ehr_runtime_find_class) findClass=nullptr;
    decltype(&ehr_runtime_find_method) findMethod=nullptr;
    decltype(&ehr_runtime_construct) construct=nullptr;
    decltype(&ehr_runtime_invoke) invoke=nullptr;
    decltype(&ehr_runtime_object_class) objectClass=nullptr;
    decltype(&ehr_runtime_copy_value) copyValue=nullptr;
    decltype(&ehr_runtime_object_release) release=nullptr;
    decltype(&ehr_runtime_object_root_count) rootCount=nullptr;
    NSDictionary *(*runtimeStatus)()=nullptr;
    EHRManagedIteratorProductionV1 host{};
    const EHRManagedIteratorCallbacksV1 callbacks{1,sizeof(EHRManagedIteratorCallbacksV1),step,reset,cancel};
    std::array<EHRRuntimeToken,Count+2> tokens{};
    std::array<uint64_t,Count+2> registrations{};
    EHRRuntimeToken listClass=0,simpleClass=0,booleanClass=0,invalidClass=0,unsupportedClass=0;
    EHRRuntimeToken getEnumerator=0,moveNext=0,current=0,resetMethod=0;
    size_t retained=0,lateFalse=0,sampled=0,released=0,releaseFailures=0;
    uint64_t maxEntries=0;bool cleaned=false;
    void require(bool ok,uint32_t stage,int32_t status=EHR_RUNTIME_TYPE_MISMATCH) {if(!ok)throw Failure{stage,status};}
    void drop(EHRRuntimeToken &token) noexcept {
        if(token){auto value=token;token=0;if(release&&release(value)==EHR_RUNTIME_OK)++released;else ++releaseFailures;}
    }
    ~Probe(){cleanup();}
    void cleanup() noexcept {
        if(cleaned)return;cleaned=true;
        for(auto &id:registrations)if(id){if(host.close&&host.close(id)!=EHR_RUNTIME_OK)++releaseFailures;id=0;}
        for(auto &token:tokens)drop(token);
    }
    void load() {
#define RETIRE_API(member,name) member=reinterpret_cast<decltype(member)>(helperExport(name));require(member!=nullptr,1,EHR_RUNTIME_NOT_FOUND)
        RETIRE_API(findClass,"ehr_runtime_find_class");RETIRE_API(findMethod,"ehr_runtime_find_method");
        RETIRE_API(construct,"ehr_runtime_construct");RETIRE_API(invoke,"ehr_runtime_invoke");
        RETIRE_API(objectClass,"ehr_runtime_object_class");RETIRE_API(copyValue,"ehr_runtime_copy_value");
        RETIRE_API(release,"ehr_runtime_object_release");RETIRE_API(rootCount,"ehr_runtime_object_root_count");
        RETIRE_API(runtimeStatus,"EHRFullSourceCopyRuntimeStatus");
#undef RETIRE_API
        auto make=reinterpret_cast<void(*)(EHRManagedIteratorProductionV1 *)>(helperExport("EHRManagedIteratorProductionMakeTable"));
        require(make!=nullptr,1,EHR_RUNTIME_NOT_FOUND);make(&host);
        require(host.abi_version==1&&host.byte_size==72&&host.register_carrier&&host.acquire&&host.close&&host.copy_status&&host.is_main&&host.is_main()==1,2);
        require(findClass("mscorlib.dll","System.Collections","ArrayList",&listClass)==0,3);
        require(findClass("mscorlib.dll","System.Collections","ArrayList+ArrayListEnumeratorSimple",&simpleClass)==0,3);
        EHRRuntimeToken enumerable=0;
        require(findClass("mscorlib.dll","System.Collections","IEnumerable",&enumerable)==0,3);
        require(findClass("mscorlib.dll","System","Boolean",&booleanClass)==0,3);
        require(findClass("mscorlib.dll","System","InvalidOperationException",&invalidClass)==0,3);
        require(findClass("mscorlib.dll","System","NotSupportedException",&unsupportedClass)==0,3);
        require(findMethod(enumerable,"GetEnumerator",nullptr,0,"System.Collections.IEnumerator",0,&getEnumerator)==0,4);
        require(findMethod(simpleClass,"MoveNext",nullptr,0,"System.Boolean",0,&moveNext)==0,4);
        require(findMethod(simpleClass,"get_Current",nullptr,0,"System.Object",0,&current)==0,4);
        require(findMethod(simpleClass,"Reset",nullptr,0,"System.Void",0,&resetMethod)==0,4);
    }
    void create(size_t index) {
        EHRRuntimeToken list=0,error=0;
        int32_t code=construct(listClass,nullptr,0,&list,&error);
        const bool made=code==0&&list&&!error;drop(error);
        if(!made){drop(list);require(false,5,code);}
        code=invoke(getEnumerator,list,nullptr,0,&tokens[index],&error);drop(list);
        const bool got=code==0&&tokens[index]&&!error;drop(error);require(got,6,code);
        EHRRuntimeToken actual=0;require(objectClass(tokens[index],&actual)==0&&actual==simpleClass,7);
        code=host.register_carrier(tokens[index],SourceBase+index,&callbacks,&registrations[index]);
        require(code==0&&registrations[index]!=0,8,code);
    }
    bool falseMove(EHRRuntimeToken carrier) {
        EHRRuntimeToken result=0,error=0,klass=0;uint8_t value=9;size_t size=0;
        const int32_t code=invoke(moveNext,carrier,nullptr,0,&result,&error);
        const bool ok=code==0&&!error&&result&&objectClass(result,&klass)==0&&klass==booleanClass&&
            copyValue(result,&value,sizeof(value),&size)==0&&size==1&&value==0;
        drop(result);drop(error);return ok;
    }
    bool nativeException(EHRRuntimeToken method,EHRRuntimeToken carrier,EHRRuntimeToken expected) {
        EHRRuntimeToken result=0,error=0,klass=0;
        const int32_t code=invoke(method,carrier,nullptr,0,&result,&error);
        const bool ok=code==EHR_RUNTIME_MANAGED_EXCEPTION&&!result&&error&&objectClass(error,&klass)==0&&klass==expected;
        drop(result);drop(error);return ok;
    }
    EHRProductionIteratorStatusV1 status() {
        EHRProductionIteratorStatusV1 value{};const auto code=host.copy_status(&value,sizeof(value));
        require(code==0&&value.abi_version==1&&value.byte_size==sizeof(value),9,code);return value;
    }
    NSDictionary *gateway() {return runtimeStatus()[@"numericDiagnostics"][@"gateway"];}
};
}

static NSDictionary *EHRRuntimeIteratorRetirementProof() {
    using namespace ehr_retirement_proof;
    if(!NSThread.isMainThread)return @{@"schema":@"ehr.actual-iterator-retirement-proof.v1",@"success":@NO,@"stage":@0,@"status":@(EHR_RUNTIME_WRONG_THREAD)};
    Probe p;callbacksState=CallbackState{};callbacksState.running=true;
    bool passed=false,rootBalanced=false,exactRoots=false,registryRestored=false,warmed=false;
    uint32_t stage=0;int32_t code=0;size_t rootsBefore=0,rootsAfter=0;
    uint64_t drainedBefore=0,drainedAfter=0,enqueuedBefore=0,enqueuedAfter=0,dequeuedBefore=0,dequeuedAfter=0;
    EHRProductionIteratorStatusV1 baseline{},after{};
    @try {try {
        p.load();
        // Prepare the single lazy fixed marker before taking leak baselines.
        p.create(Count+1);p.require(p.falseMove(p.tokens[Count+1]),10);
        p.require(callbacksState.steps[Count+1]==1&&callbacksState.cancels[Count+1]==1,10);
        p.require(p.host.close(p.registrations[Count+1])==0,10);p.registrations[Count+1]=0;p.drop(p.tokens[Count+1]);
        warmed=true;
        baseline=p.status();p.require(p.rootCount(&rootsBefore)==0,11);
        NSDictionary *before=p.gateway();p.require(before!=nil,11);
        drainedBefore=[before[@"deferredReleased"] unsignedLongLongValue];enqueuedBefore=[before[@"deferredEnqueued"] unsignedLongLongValue];dequeuedBefore=[before[@"deferredDequeued"] unsignedLongLongValue];
        p.create(Count); // One active own source remains throughout retention.
        for(size_t n=0;n<Count;++n){
            p.create(n);p.require(p.falseMove(p.tokens[n]),12);++p.retained;
            p.require(callbacksState.steps[n]==1&&callbacksState.cancels[n]==1,13);
            const auto now=p.status();p.maxEntries=now.entries>p.maxEntries?now.entries:p.maxEntries;
            p.require(now.entries==baseline.entries+1&&now.active_sources==baseline.active_sources+1&&
                now.terminal_tombstones==baseline.terminal_tombstones&&now.current_roots==baseline.current_roots&&
                now.carrier_weak_roots==baseline.carrier_weak_roots+1&&now.association_weak_roots==baseline.association_weak_roots&&
                now.temporary_pins==baseline.temporary_pins,14);
        }
        // Every completed receiver is still strongly retained here.
        for(size_t n=0;n<Count;++n){p.require(p.falseMove(p.tokens[n]),15);++p.lateFalse;
            p.require(callbacksState.steps[n]==1&&callbacksState.cancels[n]==1,16);}
        constexpr size_t samples[]={0,1,255,256,511,512,1022,1023};
        for(size_t n:samples){
            p.require(p.nativeException(p.current,p.tokens[n],p.invalidClass),17);
            p.require(p.nativeException(p.resetMethod,p.tokens[n],p.unsupportedClass),18);
            uint64_t duplicate=99;const auto duplicateStatus=p.host.register_carrier(p.tokens[n],SourceBase+n,&p.callbacks,&duplicate);
            p.require(duplicateStatus==EHR_RUNTIME_BAD_ARGUMENT&&duplicate==0,19,duplicateStatus);
            EHRRuntimeToken acquired=0;const auto acquiredStatus=p.host.acquire(p.registrations[n],&acquired);
            const bool hadAcquired=acquired!=0;if(acquired)p.drop(acquired);
            p.require(acquiredStatus==EHR_RUNTIME_UNSUPPORTED&&!hadAcquired&&p.host.close(p.registrations[n])==0,20,acquiredStatus);
            ++p.sampled;
        }
        p.cleanup();p.require(!callbacksState.fault&&p.releaseFailures==0&&callbacksState.cancels[Count]==1&&callbacksState.steps[Count]==0,21);
        after=p.status();registryRestored=after.entries==baseline.entries&&after.active_sources==baseline.active_sources&&
            after.terminal_tombstones==baseline.terminal_tombstones&&after.current_roots==baseline.current_roots&&
            after.carrier_weak_roots==baseline.carrier_weak_roots&&after.association_weak_roots==baseline.association_weak_roots&&after.temporary_pins==baseline.temporary_pins;
        p.require(registryRestored,22);p.require(p.rootCount(&rootsAfter)==0,23);
        NSDictionary *last=p.gateway();p.require(last!=nil,23);
        drainedAfter=[last[@"deferredReleased"] unsignedLongLongValue];enqueuedAfter=[last[@"deferredEnqueued"] unsignedLongLongValue];dequeuedAfter=[last[@"deferredDequeued"] unsignedLongLongValue];
        exactRoots=rootsAfter==rootsBefore;
        rootBalanced=drainedAfter>=drainedBefore&&rootsAfter<=SIZE_MAX-(drainedAfter-drainedBefore)&&rootsAfter+(drainedAfter-drainedBefore)==rootsBefore;
        p.require(rootBalanced,24);passed=true;
    }catch(const Failure &error){stage=error.stage;code=error.status;}catch(...){stage=25;code=EHR_RUNTIME_MANAGED_EXCEPTION;}}
    @catch(__unused NSException *error){stage=26;code=EHR_RUNTIME_MANAGED_EXCEPTION;}
    p.cleanup();callbacksState.running=false;
    return @{@"schema":@"ehr.actual-iterator-retirement-proof.v1",@"success":@(passed),@"stage":@(stage),@"status":@(code),
        @"retainedCompletedCarriers":@(p.retained),@"lateFalseReceivers":@(p.lateFalse),@"terminalExceptionAndDuplicateSamples":@(p.sampled),
        @"baselineEntries":@(baseline.entries),@"maximumEntriesAfterRetirement":@(p.maxEntries),@"finalEntries":@(after.entries),@"registryRestored":@(registryRestored),
        @"rootsBefore":@(rootsBefore),@"rootsAfter":@(rootsAfter),@"exactRootsEqual":@(exactRoots),@"rootAccountingBalanced":@(rootBalanced),
        @"deferredReleasedBefore":@(drainedBefore),@"deferredReleasedAfter":@(drainedAfter),@"deferredEnqueuedBefore":@(enqueuedBefore),@"deferredEnqueuedAfter":@(enqueuedAfter),
        @"deferredDequeuedBefore":@(dequeuedBefore),@"deferredDequeuedAfter":@(dequeuedAfter),
        @"fixedMarkerWarmedBeforeBaseline":@(warmed),@"releaseFailures":@(p.releaseFailures),@"callbackFault":@(callbacksState.fault),
        @"forcedGc":@NO,@"unitySchedulingPerformed":@NO,@"gameAccountNetworkActionsPerformed":@NO};
}
