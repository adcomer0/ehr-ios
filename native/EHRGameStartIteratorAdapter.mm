#include "EHRGameStartIteratorAdapter.h"
#include "EHRGameStartYieldPolicy.hpp"
#include "EHRGameStartBinding.generated.h"
#include "EHRRuntimeGateway.h"
#include "EHRRuntimeReflection.h"
#include "EHRRuntimeMetadataPrivate.h"
#include "EHRRuntimePinnedAssociation.h"
#include "EHRRuntimeActionPrivate.h"
#include "EHRRuntimeIteratorPrivate.h"
#include "EHRManagedIteratorProduction.h"
#include "EHRRuntimeDiagnostics.h"
#include <atomic>
#include <cstring>
#include <dlfcn.h>

namespace {
constexpr const char *ParentName="AmongUsClient+<CoStartGame>d__32";
constexpr const char *HostName="AmongUsClient+<CoStartGameHost>d__28";
struct Root {
    EHRRuntimeToken token=0;
    Root()=default;Root(const Root&)=delete;Root&operator=(const Root&)=delete;
    ~Root(){if(token)ehr_runtime_object_release(token);}
    EHRRuntimeToken take(){auto v=token;token=0;return v;}
};
struct Metadata {
    EHRRuntimeToken parent=0,host=0,owner=0,enumerator=0;
    EHRRuntimeToken move=0,factory=0,parentState=0,parentCurrent=0,parentOwner=0,hostState=0,hostOwner=0;
    const void *parentClass=nullptr,*hostClass=nullptr,*ownerClass=nullptr,*enumeratorClass=nullptr,*moveMethod=nullptr;
} metadata;
struct API {
    const void *(*class_get_methods)(const void*,void**)=nullptr;
    const char *(*method_get_name)(const void*)=nullptr;
    uint32_t (*method_get_token)(const void*)=nullptr;
    const void *(*object_get_class)(const void*)=nullptr;
    bool (*class_is_assignable_from)(const void*,const void*)=nullptr;
    const void *(*class_get_fields)(const void*,void**)=nullptr,*(*field_get_parent)(const void*)=nullptr,*(*field_get_type)(const void*)=nullptr;
    const char *(*field_get_name)(const void*)=nullptr;uint32_t (*field_get_flags)(const void*)=nullptr;
    char *(*type_get_name)(const void*)=nullptr;void (*free)(void*)=nullptr;
} api;
std::atomic<int32_t> preparation{EHR_RUNTIME_NOT_READY},lastStatus{EHR_RUNTIME_NOT_READY};
std::atomic<uint32_t> lastPhase{0};
std::atomic<bool> enabled{false};
std::atomic<uint64_t> activationGeneration{0};
std::atomic<uint64_t> calls{0},originalReturned{0},inactive{0},falseReturns{0},nonHost{0},rewrites{0},failures{0},factoryCalls{0},workerForwards{0};
thread_local bool applying=false;
using Factory=EHRRuntimeStatus(*)(EHRRuntimeToken,EHRRuntimeToken*,EHRRuntimeToken*,void*);
struct Result {EHRRuntimeStatus status=EHR_RUNTIME_OK;uint32_t phase=0;bool matched=false,rewritten=false;EHRRuntimeToken exception=0;};

template<class T> bool load(T &target,const char *name) {
    void *address=dlsym(RTLD_DEFAULT,name);
    if(!address||ehr_pinned::validate_engine_entry(address)!=EHR_RUNTIME_OK)return false;
    target=reinterpret_cast<T>(address);return true;
}
bool noClassConstructor(const void *klass) {
    void *cursor=nullptr;
    for(size_t i=0;i<4096;++i){const void *method=api.class_get_methods(klass,&cursor);if(!method)return true;
        const char *name=api.method_get_name(method);if(!name||!strcmp(name,".cctor"))return false;}
    return false;
}
bool exactFields(const void *klass,const char *const *names,const char *const *types,size_t expected) {
    bool found[3]={false,false,false};if(expected>3)return false;void *cursor=nullptr;
    for(size_t count=0;count<4096;++count){const void *field=api.class_get_fields(klass,&cursor);if(!field){for(size_t i=0;i<expected;++i)if(!found[i])return false;return true;}
        const char *name=api.field_get_name(field);if(!name)return false;
        for(size_t i=0;i<expected;++i)if(!strcmp(name,names[i])){
            if(found[i]||api.field_get_parent(field)!=klass||(api.field_get_flags(field)&0x70))return false;
            char *type=api.type_get_name(api.field_get_type(field));bool equal=type&&!strcmp(type,types[i]);if(type)api.free(type);
            if(!equal)return false;found[i]=true;}}
    return false;
}
EHRRuntimeStatus prepare() {
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    if(preparation.load(std::memory_order_acquire)==0)return EHR_RUNTIME_OK;
#define LOAD(name) if(!load(api.name,"il2cpp_" #name))return EHR_RUNTIME_NOT_READY
    LOAD(class_get_methods);LOAD(method_get_name);LOAD(method_get_token);LOAD(object_get_class);LOAD(class_is_assignable_from);
    LOAD(class_get_fields);LOAD(field_get_parent);LOAD(field_get_type);LOAD(field_get_name);LOAD(field_get_flags);LOAD(type_get_name);LOAD(free);
#undef LOAD
    Metadata next;
    auto status=ehr_runtime_find_class("Assembly-CSharp.dll","",ParentName,&next.parent);
#define STEP(call) if(!status)status=(call)
    STEP(ehr_runtime_find_class("Assembly-CSharp.dll","",HostName,&next.host));
    STEP(ehr_runtime_find_class("Assembly-CSharp.dll","","AmongUsClient",&next.owner));
    STEP(ehr_runtime_find_class("mscorlib.dll","System.Collections","IEnumerator",&next.enumerator));
    STEP(ehr_runtime_find_method(next.parent,"MoveNext",nullptr,0,"System.Boolean",0,&next.move));
    STEP(ehr_runtime_find_method(next.owner,"CoStartGameHost",nullptr,0,"System.Collections.IEnumerator",0,&next.factory));
    uint64_t observed=0;
    STEP(ehr_runtime_validate_native_method(next.move,EHRGameStartParentRVA,&observed));
    STEP(ehr_runtime_validate_native_method(next.factory,EHRGameStartFactoryRVA,&observed));
    STEP(EHRRuntimeBorrowClass(next.parent,&next.parentClass));STEP(EHRRuntimeBorrowClass(next.host,&next.hostClass));
    STEP(EHRRuntimeBorrowClass(next.owner,&next.ownerClass));STEP(EHRRuntimeBorrowClass(next.enumerator,&next.enumeratorClass));
    const void *declaring=nullptr;
    STEP(EHRRuntimeBorrowMethod(next.move,&next.moveMethod,&declaring));
    if(!status&&(declaring!=next.parentClass||api.method_get_token(next.moveMethod)!=0x6001ce5||
        !noClassConstructor(next.parentClass)||!noClassConstructor(next.hostClass)))status=EHR_RUNTIME_TYPE_MISMATCH;
    const char *parentNames[]={"<>1__state","<>2__current","<>4__this"},*parentTypes[]={"System.Int32","System.Object","AmongUsClient"};
    const char *hostNames[]={"<>1__state","<>4__this"},*hostTypes[]={"System.Int32","AmongUsClient"};
    if(!status&&(!exactFields(next.parentClass,parentNames,parentTypes,3)||!exactFields(next.hostClass,hostNames,hostTypes,2)))status=EHR_RUNTIME_TYPE_MISMATCH;
    const void *factory=nullptr;
    STEP(EHRRuntimeBorrowMethod(next.factory,&factory,&declaring));
    if(!status&&(declaring!=next.ownerClass||api.method_get_token(factory)!=0x6001c6b))status=EHR_RUNTIME_TYPE_MISMATCH;
    STEP(ehr_runtime_find_field(next.parent,"<>1__state","System.Int32",0,&next.parentState));
    STEP(ehr_runtime_find_field(next.parent,"<>2__current","System.Object",0,&next.parentCurrent));
    STEP(ehr_runtime_find_field(next.parent,"<>4__this","AmongUsClient",0,&next.parentOwner));
    STEP(ehr_runtime_find_field(next.host,"<>1__state","System.Int32",0,&next.hostState));
    STEP(ehr_runtime_find_field(next.host,"<>4__this","AmongUsClient",0,&next.hostOwner));
#undef STEP
    if(!status)metadata=next;
    return status;
}
EHRRuntimeStatus integer(EHRRuntimeToken field,EHRRuntimeToken object,int32_t &value) {
    Root box;auto status=ehr_runtime_read_field(field,object,&box.token);size_t count=0;
    if(!status)status=ehr_runtime_copy_value(box.token,&value,sizeof(value),&count);
    return !status&&count!=sizeof(value)?EHR_RUNTIME_TYPE_MISMATCH:status;
}
EHRRuntimeStatus realFactory(EHRRuntimeToken owner,EHRRuntimeToken *result,EHRRuntimeToken *exception,void*) {
    factoryCalls.fetch_add(1,std::memory_order_relaxed);
    return ehr_runtime_invoke(metadata.factory,owner,nullptr,0,result,exception);
}
Result apply(void *self,const void *methodInfo,Factory factory,void *context,bool fixtureNullOwner) {
    Result out;const uint64_t generation=activationGeneration.load(std::memory_order_acquire);Root parent,current,parentOwner,childOwner,replacement,exception,pin;void *identity=nullptr;
#define TRY(phaseValue,call) out.phase=phaseValue;out.status=(call);if(out.status)return out
    TRY(1,EHRRuntimeActionRootBorrowed(self,&parent.token));
    EHRRuntimeToken klass=0;TRY(2,ehr_runtime_object_class(parent.token,&klass));
    if(klass!=metadata.parent){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
    out.phase=3;if(methodInfo&&methodInfo!=metadata.moveMethod){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
    TRY(4,ehr_runtime_read_field(metadata.parentCurrent,parent.token,&current.token));
    if(!current.token)return out;
    TRY(4,ehr_runtime_object_class(current.token,&klass));if(klass!=metadata.host)return out;
    out.matched=true;int32_t parentState=0,childState=0;
    TRY(5,integer(metadata.parentState,parent.token,parentState));TRY(5,integer(metadata.hostState,current.token,childState));
    TRY(6,ehr_runtime_read_field(metadata.parentOwner,parent.token,&parentOwner.token));
    TRY(6,ehr_runtime_read_field(metadata.hostOwner,current.token,&childOwner.token));
    int32_t same=0;
    if(parentOwner.token&&childOwner.token){TRY(6,ehr_runtime_object_class(parentOwner.token,&klass));
        if(klass!=metadata.owner){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
        TRY(6,ehr_runtime_object_class(childOwner.token,&klass));if(klass!=metadata.owner){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
        TRY(6,ehr_runtime_object_same(parentOwner.token,childOwner.token,&same));}
    if(ehr_game_start::policy(true,parentState,childState,parentOwner.token!=0,childOwner.token!=0,same==1,fixtureNullOwner)!=ehr_game_start::Policy::Replace){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
    out.phase=7;if(!fixtureNullOwner&&(!enabled.load(std::memory_order_acquire)||activationGeneration.load(std::memory_order_acquire)!=generation)){out.status=EHR_RUNTIME_NOT_READY;return out;}
    out.status=factory(parentOwner.token,&replacement.token,&exception.token,context);
    if(out.status||exception.token){if(!out.status)out.status=EHR_RUNTIME_MANAGED_EXCEPTION;out.exception=exception.take();return out;}
    out.phase=8;if(!fixtureNullOwner&&(!enabled.load(std::memory_order_acquire)||activationGeneration.load(std::memory_order_acquire)!=generation)){out.status=EHR_RUNTIME_NOT_READY;return out;}
    if(!replacement.token){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
    TRY(8,EHRRuntimeIteratorPin(replacement.token,&pin.token,&identity));
    if(!identity||!api.class_is_assignable_from(metadata.enumeratorClass,api.object_get_class(identity))||!EHRProductionIteratorHasActiveIdentity(identity)){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
    // Source callbacks are reentrant. Do not overwrite a different yield even
    // when startup activation remained enabled throughout the factory call.
    int32_t checkedState=0;Root checkedCurrent,checkedParentOwner,checkedChildOwner;
    TRY(9,integer(metadata.parentState,parent.token,checkedState));
    if(checkedState!=parentState){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
    TRY(9,integer(metadata.hostState,current.token,checkedState));
    if(checkedState!=childState){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
    TRY(9,ehr_runtime_read_field(metadata.parentCurrent,parent.token,&checkedCurrent.token));
    TRY(9,ehr_runtime_object_same(checkedCurrent.token,current.token,&same));if(!same){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
    TRY(9,ehr_runtime_read_field(metadata.parentOwner,parent.token,&checkedParentOwner.token));
    TRY(9,ehr_runtime_object_same(checkedParentOwner.token,parentOwner.token,&same));if(!same){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
    TRY(9,ehr_runtime_read_field(metadata.hostOwner,current.token,&checkedChildOwner.token));
    TRY(9,ehr_runtime_object_same(checkedChildOwner.token,childOwner.token,&same));if(!same){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
    if(!fixtureNullOwner&&(!enabled.load(std::memory_order_acquire)||activationGeneration.load(std::memory_order_acquire)!=generation)){out.status=EHR_RUNTIME_NOT_READY;return out;}
    EHRRuntimeArgument argument{EHR_RUNTIME_REFERENCE,0,replacement.token,nullptr,0};
    TRY(9,ehr_runtime_write_field(metadata.parentCurrent,parent.token,&argument));
    // The public setter performs the actual GC reference write barrier. Read
    // back identity while all owned roots are still live before committing.
    Root read;TRY(9,ehr_runtime_read_field(metadata.parentCurrent,parent.token,&read.token));
    TRY(9,ehr_runtime_object_same(read.token,replacement.token,&same));
    if(!same){out.status=EHR_RUNTIME_TYPE_MISMATCH;return out;}
    out.rewritten=true;return out;
#undef TRY
}
Result containedApply(void *self,const void *methodInfo,Factory factory,void *context,bool fixtureNullOwner) noexcept {
    @try {try{return apply(self,methodInfo,factory,context,fixtureNullOwner);}catch(...){return {EHR_RUNTIME_LIMIT,11,false,false,0};}}
    @catch(__unused NSException *error){return {EHR_RUNTIME_MANAGED_EXCEPTION,11,false,false,0};}
}
}

extern "C" int32_t EHRGameStartIteratorPrepare(void) {
    int32_t status=EHR_RUNTIME_NOT_READY;
    @try {try{status=prepare();}catch(...){status=EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *error){status=EHR_RUNTIME_MANAGED_EXCEPTION;}
    if(NSThread.isMainThread){preparation.store(status,std::memory_order_release);lastStatus.store(status);}
    return status;
}
extern "C" int32_t EHRGameStartIteratorSetEnabled(int32_t value) {
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    if(value!=0&&value!=1)return EHR_RUNTIME_BAD_ARGUMENT;
    if(value&&preparation.load(std::memory_order_acquire)!=0)return EHR_RUNTIME_NOT_READY;
    activationGeneration.fetch_add(1,std::memory_order_acq_rel);enabled.store(value==1,std::memory_order_release);return EHR_RUNTIME_OK;
}
extern "C" NSDictionary *EHRGameStartIteratorCopyStatus(void) {
    return @{@"preparedStatus":@(preparation.load()),@"enabled":@(enabled.load()),@"activationGeneration":@(activationGeneration.load()),@"calls":@(calls.load()),
        @"originalReturned":@(originalReturned.load()),@"inactiveForwards":@(inactive.load()),@"falseReturns":@(falseReturns.load()),
        @"nonHostYields":@(nonHost.load()),@"rewrites":@(rewrites.load()),@"failures":@(failures.load()),
        @"factoryCalls":@(factoryCalls.load()),@"workerForwards":@(workerForwards.load()),@"lastStatus":@(lastStatus.load()),@"lastPhase":@(lastPhase.load())};
}
extern "C" __attribute__((visibility("default"))) bool ehr_native_game_start_move_next_hook(void *self,const void *methodInfo) {
    using Original=bool(*)(void*,const void*);
    auto original=reinterpret_cast<Original>(EHRNativePatchOriginal(EHRGameStartSite));
    calls.fetch_add(1,std::memory_order_relaxed);
    const bool moved=original(self,methodInfo); // Exactly once; native exceptions propagate unchanged.
    originalReturned.fetch_add(1,std::memory_order_relaxed);
    if(!enabled.load(std::memory_order_acquire)){inactive.fetch_add(1,std::memory_order_relaxed);return moved;}
    if(!moved){falseReturns.fetch_add(1,std::memory_order_relaxed);return false;}
    if(!NSThread.isMainThread){workerForwards.fetch_add(1,std::memory_order_relaxed);return moved;}
    Result result;
    if(applying)result={EHR_RUNTIME_BAD_ARGUMENT,10,false,false,0};
    else {struct Scope {Scope(){applying=true;}~Scope(){applying=false;}} scope;result=containedApply(self,methodInfo,realFactory,nullptr,false);}
    lastStatus.store(result.status,std::memory_order_relaxed);lastPhase.store(result.phase,std::memory_order_relaxed);
    if(result.status){failures.fetch_add(1,std::memory_order_relaxed);
        // No original/factory retry and no vanilla fallthrough after a failed
        // source rewrite. All temporary roots were closed before this rethrow.
        const auto exception=result.exception;result.exception=0;
        EHRNativeRaiseOwnedFailure(result.status,exception);return false;}
    if(result.rewritten)rewrites.fetch_add(1,std::memory_order_relaxed);else nonHost.fetch_add(1,std::memory_order_relaxed);
    return moved;
}

namespace {
struct FixtureContext {EHRRuntimeToken result=0,error=0;EHRRuntimeStatus status=EHR_RUNTIME_OK;uint32_t calls=0;};
EHRRuntimeStatus fixtureFactory(EHRRuntimeToken owner,EHRRuntimeToken *result,EHRRuntimeToken *error,void *opaque) {
    auto &context=*static_cast<FixtureContext*>(opaque);++context.calls;*result=*error=0;
    if(owner)return EHR_RUNTIME_BAD_ARGUMENT;
    if(context.result){void *object=nullptr;Root pin;auto status=EHRRuntimeIteratorPin(context.result,&pin.token,&object);
        if(status)return status;status=EHRRuntimeActionRootBorrowed(object,result);if(status)return status;}
    if(context.error){void *object=nullptr;Root pin;auto status=EHRRuntimeIteratorPin(context.error,&pin.token,&object);
        if(status)return status;status=EHRRuntimeActionRootBorrowed(object,error);if(status)return status;}
    return context.status;
}
std::atomic<uint64_t> fixtureCancels{0};
int32_t fixtureStep(uint64_t,int32_t *moved,EHRRuntimeToken *current){if(!moved||!current)return 4;*moved=0;*current=0;return 0;}
int32_t fixtureReset(uint64_t){return 7;}
int32_t fixtureCancel(uint64_t){fixtureCancels.fetch_add(1);return 0;}
struct FixtureFailure {uint32_t stage;int32_t status;};
struct Fixture {
    EHRManagedIteratorProductionV1 host{};uint64_t registration=0;
    Root parent,child,carrier,ordinary,exception,parentPin;void *parentPointer=nullptr;
    EHRRuntimeToken intClass=0,listClass=0,getEnumerator=0;
    uint32_t checks=0;
    ~Fixture(){if(registration)host.close(registration);}
    void check(bool valid,uint32_t stage,int32_t status=5){if(!valid)throw FixtureFailure{stage,status};++checks;}
    void ready(){EHRManagedIteratorProductionMakeTable(&host);check(host.abi_version==1&&host.byte_size==72&&host.register_carrier&&host.close,1);
        check(ehr_runtime_find_class("mscorlib.dll","System","Int32",&intClass)==0,1);
        check(ehr_runtime_find_class("mscorlib.dll","System.Collections","ArrayList",&listClass)==0,1);
        EHRRuntimeToken enumerable=0;check(ehr_runtime_find_class("mscorlib.dll","System.Collections","IEnumerable",&enumerable)==0,1);
        check(ehr_runtime_find_method(enumerable,"GetEnumerator",nullptr,0,"System.Collections.IEnumerator",0,&getEnumerator)==0,1);}
    void enumerator(Root &out){Root list,error;check(ehr_runtime_construct(listClass,nullptr,0,&list.token,&error.token)==0&&!error.token,2);
        check(ehr_runtime_invoke(getEnumerator,list.token,nullptr,0,&out.token,&error.token)==0&&out.token&&!error.token,2);}
    void registerCarrier(Root &value){const EHRManagedIteratorCallbacksV1 callbacks{1,sizeof(callbacks),fixtureStep,fixtureReset,fixtureCancel};
        check(host.register_carrier(value.token,UINT64_C(0x454852494e4c494e),&callbacks,&registration)==0&&registration,3);}
    void construct(EHRRuntimeToken klass,int32_t state,Root &out){Root error,box;
        check(ehr_runtime_box(intClass,&state,sizeof(state),&box.token)==0,4);
        check(ehr_runtime_construct(klass,&box.token,1,&out.token,&error.token)==0&&out.token&&!error.token,4);}
    void setInt(EHRRuntimeToken field,EHRRuntimeToken object,int32_t value){EHRRuntimeArgument arg{EHR_RUNTIME_VALUE,0,intClass,&value,sizeof(value)};check(ehr_runtime_write_field(field,object,&arg)==0,5);}
    void setCurrent(EHRRuntimeToken value){EHRRuntimeArgument arg{EHR_RUNTIME_REFERENCE,0,value,nullptr,0};check(ehr_runtime_write_field(metadata.parentCurrent,parent.token,&arg)==0,5);}
    void currentIs(EHRRuntimeToken value){Root read;int32_t same=0;check(ehr_runtime_read_field(metadata.parentCurrent,parent.token,&read.token)==0&&ehr_runtime_object_same(read.token,value,&same)==0&&same,6);}
};
}
extern "C" NSDictionary *EHRGameStartIteratorSelfTest(void) {
    if(!NSThread.isMainThread)return @{@"schema":@"ehr.game-start-iterator-proof.v1",@"success":@NO,@"stage":@0,@"status":@2};
    bool success=false,rootsBalanced=false;uint32_t stage=0,checks=0,factoryCount=0;int32_t status=0;size_t before=0,after=0;uint64_t cancelsBefore=0,cancelsAfter=0;ehr_diagnostics::Gateway gatewayBefore{},gatewayAfter{};
    @try {try{
        status=EHRGameStartIteratorPrepare();if(status)throw FixtureFailure{1,status};
        // Both exact iterator classes were scanned for .cctor in Prepare.
        // Warm the single lazy native marker before root-accounting baseline.
        {Fixture warm;warm.ready();warm.enumerator(warm.carrier);warm.registerCarrier(warm.carrier);}
        if(ehr_runtime_object_root_count(&before))throw FixtureFailure{1,1};
        EHRRuntimeGatewayPublishDiagnosticSnapshot();gatewayBefore=ehr_diagnostics::state().snapshot().gateway;
        cancelsBefore=fixtureCancels.load();
        {
            Fixture f;f.ready();f.construct(metadata.parent,5,f.parent);f.construct(metadata.host,0,f.child);
            f.enumerator(f.carrier);f.registerCarrier(f.carrier);f.enumerator(f.ordinary);
            f.check(EHRRuntimeIteratorPin(f.parent.token,&f.parentPin.token,&f.parentPointer)==0&&f.parentPointer,7);
            FixtureContext context{f.carrier.token,0,EHR_RUNTIME_OK,0};
            f.setCurrent(f.child.token);
            // Production strict policy must reject null owners BEFORE factory.
            auto rejected=containedApply(f.parentPointer,metadata.moveMethod,fixtureFactory,&context,false);
            f.check(rejected.status==5&&!rejected.exception&&context.calls==0,8);f.currentIs(f.child.token);
            auto first=containedApply(f.parentPointer,metadata.moveMethod,fixtureFactory,&context,true);
            f.check(first.status==0&&first.rewritten&&first.matched&&!first.exception&&context.calls==1,9);f.currentIs(f.carrier.token);
            auto repeat=containedApply(f.parentPointer,metadata.moveMethod,fixtureFactory,&context,true);
            f.check(repeat.status==0&&!repeat.rewritten&&!repeat.matched&&context.calls==1,10);f.currentIs(f.carrier.token);
            f.setInt(metadata.parentState,f.parent.token,7);f.setCurrent(f.child.token);
            auto second=containedApply(f.parentPointer,nullptr,fixtureFactory,&context,true);
            f.check(second.status==0&&second.rewritten&&context.calls==2,11);f.currentIs(f.carrier.token);
            f.setInt(metadata.parentState,f.parent.token,6);f.setCurrent(f.child.token);
            rejected=containedApply(f.parentPointer,nullptr,fixtureFactory,&context,true);
            f.check(rejected.status==5&&context.calls==2,12);f.currentIs(f.child.token);
            f.setInt(metadata.parentState,f.parent.token,5);f.setInt(metadata.hostState,f.child.token,1);
            rejected=containedApply(f.parentPointer,nullptr,fixtureFactory,&context,true);
            f.check(rejected.status==5&&context.calls==2,13);f.currentIs(f.child.token);
            f.setInt(metadata.hostState,f.child.token,0);context.result=f.ordinary.token;
            rejected=containedApply(f.parentPointer,nullptr,fixtureFactory,&context,true);
            f.check(rejected.status==5&&rejected.phase==8&&context.calls==3,14);f.currentIs(f.child.token);
            context.result=0;context.status=EHR_RUNTIME_BAD_ARGUMENT;
            rejected=containedApply(f.parentPointer,nullptr,fixtureFactory,&context,true);
            f.check(rejected.status==4&&rejected.phase==7&&context.calls==4,15);f.currentIs(f.child.token);
            EHRRuntimeToken exceptionClass=0;Root error;
            f.check(ehr_runtime_find_class("mscorlib.dll","System","InvalidOperationException",&exceptionClass)==0,16);
            f.check(ehr_runtime_construct(exceptionClass,nullptr,0,&f.exception.token,&error.token)==0&&!error.token,16);
            context.error=f.exception.token;context.status=EHR_RUNTIME_MANAGED_EXCEPTION;
            rejected=containedApply(f.parentPointer,nullptr,fixtureFactory,&context,true);
            Root returned;returned.token=rejected.exception;int32_t same=0;
            f.check(rejected.status==6&&rejected.phase==7&&context.calls==5&&returned.token&&
                ehr_runtime_object_same(returned.token,f.exception.token,&same)==0&&same,17);f.currentIs(f.child.token);
            f.check(f.host.close(f.registration)==0,18);
            context={f.carrier.token,0,EHR_RUNTIME_OK,context.calls};
            rejected=containedApply(f.parentPointer,nullptr,fixtureFactory,&context,true);
            f.check(rejected.status==5&&rejected.phase==8&&context.calls==6,18);f.currentIs(f.child.token);
            checks=f.checks;factoryCount=context.calls;
        }
        cancelsAfter=fixtureCancels.load();if(ehr_runtime_object_root_count(&after))throw FixtureFailure{18,1};
        EHRRuntimeGatewayPublishDiagnosticSnapshot();gatewayAfter=ehr_diagnostics::state().snapshot().gateway;
        const auto released=gatewayAfter.released-gatewayBefore.released;
        rootsBalanced=gatewayAfter.released>=gatewayBefore.released&&after<=SIZE_MAX-released&&after+released==before;
        if(!rootsBalanced||cancelsAfter!=cancelsBefore+1)throw FixtureFailure{18,5};
        success=true;
    }catch(const FixtureFailure &failure){stage=failure.stage;status=failure.status;}catch(...){stage=19;status=8;}}
    @catch(__unused NSException *error){stage=20;status=6;}
    return @{@"schema":@"ehr.game-start-iterator-proof.v1",@"success":@(success),@"stage":@(stage),@"status":@(status),
        @"checks":@(checks),@"factorySeamCalls":@(factoryCount),@"rootsBefore":@(before),@"rootsAfter":@(after),@"rootAccountingBalanced":@(rootsBalanced),
        @"deferredReleasedBefore":@(gatewayBefore.released),@"deferredReleasedAfter":@(gatewayAfter.released),
        @"deferredEnqueuedBefore":@(gatewayBefore.enqueued),@"deferredEnqueuedAfter":@(gatewayAfter.enqueued),
        @"deferredDequeuedBefore":@(gatewayBefore.dequeued),@"deferredDequeuedAfter":@(gatewayAfter.dequeued),
        @"cancelCallsBefore":@(cancelsBefore),@"cancelCallsAfter":@(cancelsAfter),@"fixtureNullOwner":@YES,@"realGameOwnerInvoked":@NO,
        @"originalMoveNextInvoked":@NO,@"realHostFactoryInvoked":@NO,@"unityObjectCreated":@NO,@"runtimeExecutableWrites":@NO};
}
