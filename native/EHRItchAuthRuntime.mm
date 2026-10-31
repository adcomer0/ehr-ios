#import "EHRItchAuthRuntime.h"
#include "EHRItchSDKABI.hpp"
#include "EHRRuntimeGateway.h"
#include "EHRRuntimeMetadataPrivate.h"
#include "EHRRuntimeActionPrivate.h"
#include "EHRRuntimeIteratorPrivate.h"
#include "EHRRuntimePinnedAssociation.h"
#include <CommonCrypto/CommonDigest.h>
#include <mach-o/loader.h>
#include <atomic>
#include <cstring>
#include <dlfcn.h>
#include <memory>
#include <vector>
#if __has_include("EHRItchAuthBinding.generated.h")
#include "EHRItchAuthBinding.generated.h"
#define EHR_ITCH_BINDING_AVAILABLE 1
#else
#define EHR_ITCH_BINDING_AVAILABLE 0
#endif

namespace {
struct Root {
    EHRRuntimeToken token=0;
    Root()=default; Root(const Root&)=delete; Root& operator=(const Root&)=delete;
    Root(Root&& other) noexcept:token(other.token){other.token=0;}
    Root& operator=(Root&& other) noexcept { if(this!=&other){reset();token=other.token;other.token=0;}return *this; }
    void reset(){if(token){ehr_runtime_object_release(token);token=0;}}
    ~Root(){reset();}
};
struct API {
    const void *(*object_get_class)(void *);
    void *(*object_new)(const void *);
    void *(*object_unbox)(void *);
    bool (*class_is_valuetype)(const void *);
    bool (*class_has_references)(const void *);
    bool (*class_is_inited)(const void *);
    uint32_t (*class_instance_size)(const void *);
    int32_t (*class_value_size)(const void *,uint32_t *);
    const void *(*class_get_parent)(const void *);
    const void *(*class_get_type)(const void *);
    const void *(*class_from_type)(const void *);
    const void *(*class_get_methods)(const void *,void **);
    const char *(*method_get_name)(const void *);
    void *(*class_get_fields)(const void *,void **);
    const char *(*field_get_name)(void *);
    const void *(*field_get_type)(void *);
    uint32_t (*field_get_flags)(void *);
    size_t (*field_get_offset)(void *);
    void (*field_static_get_value)(void *,void *);
    void (*field_get_value)(void *,void *,void *);
    char *(*type_get_name)(const void *);
    void (*runtime_free)(void *);
    void *(*runtime_invoke)(const void *,void *,void **,void **);
    uintptr_t (*array_length)(void *);
    int32_t (*string_length)(void *);
    uint32_t (*gchandle_new_weakref)(void *,bool);
    void *(*gchandle_get_target)(uint32_t);
    void (*gchandle_free)(uint32_t);
} api{};
struct Metadata {
    EHRRuntimeToken manager=0, callback=0, action=0, internal=0, info=0;
    EHRRuntimeToken getPlatform=0,getConnect=0,getHandle=0,initialize=0,normalLogin=0;
    EHRRuntimeToken successField=0,failureField=0,actionInvoke=0,resultGetter=0;
    EHRRuntimeToken delegateMethod=0,delegateTarget=0,delegateList=0;
    EHRRuntimeToken tryingField=0,continuanceField=0,account=0,errorEnum=0,signInFail=0;
    EHRRuntimeToken delegateFactory=0,silentMethod=0,loginStatus=0,deviceProductUser=0;
    uint64_t normalCallbackRVA=0,silentCallbackRVA=0;
    const void *managerClass=nullptr,*callbackClass=nullptr,*actionClass=nullptr;
    const void *internalClass=nullptr,*infoClass=nullptr,*parentClass=nullptr;
    const void *marshalMethod=nullptr,*invokeMethod=nullptr;
    const void *accountClass=nullptr,*accountParent=nullptr;
    const void *dataManagerClass=nullptr,*playerClass=nullptr,*playerAccountClass=nullptr;
    void *instanceField=nullptr;
    void *accountInstanceField=nullptr;
    void *playerStorage=nullptr,*playerAccountField=nullptr;
} meta{};
struct Context { Root manager,success,failure; bool failureDelivered=false,normalFlow=true,priorFull=false,originalEntered=false; };
struct Request { std::unique_ptr<Context> context; Root platform,connect; uintptr_t cookie=0; bool cancelled=false,resultOnly=false;uint8_t credentialDigest[32]{};~Request(){volatile uint8_t *p=credentialDigest;for(size_t i=0;i<sizeof(credentialDigest);++i)p[i]=0;} };
struct NewUserCandidate {std::unique_ptr<Request> request;ehr_itch::LoginInfo actual{};};
std::unique_ptr<Context> captured;
std::unique_ptr<Request> request;
std::unique_ptr<NewUserCandidate> newUserCandidate;
Root completionOwner;
uint32_t lastFullOwnerWeak=0;
uint8_t lastFullCredentialDigest[32]{},completionCredentialDigest[32]{};
bool lastFullCredentialKnown=false;
bool completionFence=false,awaitingFull=false,completionFromNewUser=false;
bool delivering=false;
uintptr_t nextCookie=1;
uint64_t notifyGeneration=0;
ehr_itch::Login sdkLogin=nullptr;
EHRItchAuthResultHandler resultHandler=nil;
std::atomic<int32_t> prepared{EHR_RUNTIME_NOT_READY},localStatus{EHR_RUNTIME_NOT_READY},lastEOS{0};
std::atomic<bool> enabled{false},hasCaptured{false},pending{false},knownResult{false},successDelivered{false},fullCompleted{false};
std::atomic<bool> fenceStatus{false},awaitingStatus{false};
std::atomic<bool> awaitingNewUser{false},continuityAvailable{false},callbackDelivered{false},continuedNewUser{false},newUserMigrationValidated{false};
std::atomic<int32_t> newUserMigrationStatus{EHR_RUNTIME_NOT_READY};
std::atomic<uint64_t> newUserMigrationChecks{0},newUserMigrationRejections{0};
int32_t completionGuardFailure=EHR_RUNTIME_OK;
std::atomic<uint64_t> completions{0},sdkCalls{0},failureCalls{0},lateCallbacks{0},cancelCount{0},marshalCalls{0},successCalls{0};
std::atomic<uint64_t> silentFailureCalls{0};

bool mainThread(){return NSThread.isMainThread;}
void notify(){
    auto handler=resultHandler;
    if(!handler)return;
    const auto generation=++notifyGeneration;
    const auto status=localStatus.load();const auto result=lastEOS.load();const bool known=knownResult.load(),delivered=successDelivered.load();
    dispatch_async(dispatch_get_main_queue(),^{if(generation!=notifyGeneration)return;@try{try{handler(status,result,known,delivered);}catch(...){}}@catch(__unused NSException *e){}});
}
bool typeIs(const void *type,const char *expected){
    char *name=type?api.type_get_name(type):nullptr;
    const bool same=name&&!strcmp(name,expected);if(name)api.runtime_free(name);return same;
}
bool noInitializer(const void *klass){
    void *cursor=nullptr;
    for(size_t i=0;i<4096;++i){const void *method=api.class_get_methods(klass,&cursor);if(!method)return true;const char *name=api.method_get_name(method);if(!name||!strcmp(name,".cctor"))return false;}return false;
}
struct FieldFact {const char *name,*type;size_t offset;};
[[maybe_unused]] bool exactValue(const void *klass,size_t bytes,bool references,const FieldFact *facts,size_t count){
    uint32_t align=0;
    if(!klass||!api.class_is_valuetype(klass)||api.class_has_references(klass)!=references||!noInitializer(klass)||
       api.class_value_size(klass,&align)!=static_cast<int32_t>(bytes)||align>8||api.class_instance_size(klass)!=bytes+16)return false;
    void *cursor=nullptr;size_t seen=0;
    for(size_t i=0;i<=count;++i){
        void *field=api.class_get_fields(klass,&cursor);if(!field)return seen==count;
        const char *name=api.field_get_name(field);if(!name||seen>=count||(api.field_get_flags(field)&16))return false;
        bool match=false;
        for(size_t j=0;j<count;++j)if(!strcmp(name,facts[j].name)){match=typeIs(api.field_get_type(field),facts[j].type)&&api.field_get_offset(field)==16+facts[j].offset;break;}
        if(!match)return false;++seen;
    }return false;
}
[[maybe_unused]] void *ownField(const void *klass,const char *name,const char *type,bool isStatic){
    void *cursor=nullptr,*found=nullptr;
    for(size_t i=0;i<4096;++i){void *field=api.class_get_fields(klass,&cursor);if(!field)return found;const char *n=api.field_get_name(field);if(!n||strcmp(n,name))continue;if(found||bool(api.field_get_flags(field)&16)!=isStatic||!typeIs(api.field_get_type(field),type))return nullptr;found=field;}return nullptr;
}
int32_t pin(EHRRuntimeToken token,Root &owned,void **object){return EHRRuntimeIteratorPin(token,&owned.token,object);}
int32_t existingManager(Root &owner){
    if(!api.class_is_inited(meta.parentClass))return EHR_RUNTIME_NOT_READY;
    void *object=nullptr;api.field_static_get_value(meta.instanceField,&object);
    if(!object)return EHR_RUNTIME_NOT_READY;
    if(api.object_get_class(object)!=meta.managerClass)return EHR_RUNTIME_TYPE_MISMATCH;
    return EHRRuntimeActionRootBorrowed(object,&owner.token);
}
int32_t sameCurrentOwner(EHRRuntimeToken owner){
    Root current;auto status=existingManager(current);int32_t same=0;
    if(!status)status=ehr_runtime_object_same(current.token,owner,&same);
    return status?status:same?EHR_RUNTIME_OK:EHR_RUNTIME_NOT_READY;
}
void forgetFullOwner(){if(lastFullOwnerWeak){api.gchandle_free(lastFullOwnerWeak);lastFullOwnerWeak=0;}memset(lastFullCredentialDigest,0,sizeof(lastFullCredentialDigest));lastFullCredentialKnown=false;}
void retireForeignFence(){
    if(!completionFence||!completionOwner.token)return;
    // A previously entered new-profile callback can still reach native
    // migration after owner replacement. Preserve its one bounded guard until
    // its genuine final endpoint retires it, or until this process exits.
    if(completionFromNewUser)return;
    Root current;int32_t same=1;
    if(!existingManager(current)&&!ehr_runtime_object_same(current.token,completionOwner.token,&same)&&!same){
        completionFence=false;fenceStatus.store(false);completionOwner.reset();completionFromNewUser=false;
    }
}
int32_t invoke(EHRRuntimeToken method,EHRRuntimeToken self,Root &result){Root exception;return ehr_runtime_invoke(method,self,nullptr,0,&result.token,&exception.token);}
int32_t makeSilentDelegate(EHRRuntimeToken owner,Root &callback){
    Root type,method,exception;
    auto status=ehr_runtime_class_type_object(meta.callback,&type.token);
    if(!status)status=ehr_runtime_method_object(meta.silentMethod,&method.token);
    if(status)return status;
    const EHRRuntimeArgument args[]={{EHR_RUNTIME_REFERENCE,0,type.token,nullptr,0},{EHR_RUNTIME_REFERENCE,0,owner,nullptr,0},{EHR_RUNTIME_REFERENCE,0,method.token,nullptr,0}};
    return ehr_runtime_invoke(meta.delegateFactory,0,args,3,&callback.token,&exception.token);
}
int32_t acquisitionPending(Context &context){
    if(!context.normalFlow||context.originalEntered)return EHR_RUNTIME_NOT_READY;
    auto status=sameCurrentOwner(context.manager.token);Root callback,failure,trying;
    if(!status)status=ehr_runtime_read_field(meta.successField,context.manager.token,&callback.token);
    if(!status)status=ehr_runtime_read_field(meta.failureField,context.manager.token,&failure.token);
    int32_t same=0;if(!status)status=ehr_runtime_object_same(callback.token,context.success.token,&same);
    if(!status&&!same)status=EHR_RUNTIME_NOT_READY;
    if(!status)status=ehr_runtime_object_same(failure.token,context.failure.token,&same);
    if(!status&&!same)status=EHR_RUNTIME_NOT_READY;
    if(!status)status=ehr_runtime_read_field(meta.tryingField,context.manager.token,&trying.token);
    uint8_t value=0;size_t count=0;if(!status)status=ehr_runtime_copy_value(trying.token,&value,sizeof(value),&count);
    if(!status&&(count!=1||value!=1))status=EHR_RUNTIME_NOT_READY;
    return status;
}
int32_t newUserContinuity(Context &context,const ehr_itch::LoginInfo &actual){
    if(actual.result!=3||!actual.continuanceToken||!context.normalFlow||context.originalEntered)return EHR_RUNTIME_NOT_READY;
    auto status=acquisitionPending(context);Root current,handle;
    if(!status)status=ehr_runtime_read_field(meta.continuanceField,context.manager.token,&current.token);
    if(status||!current.token)return status;
    // The original callback retains a non-null existing continuance instead of
    // replacing it. Reject any stale/foreign token before entering that body.
    if(!status)status=invoke(meta.getHandle,current.token,handle);
    uintptr_t pointer=0;size_t count=0;
    if(!status)status=ehr_runtime_copy_value(handle.token,&pointer,sizeof(pointer),&count);
    if(!status&&(count!=sizeof(pointer)||pointer!=reinterpret_cast<uintptr_t>(actual.continuanceToken)))status=EHR_RUNTIME_NOT_READY;
    return status;
}
int32_t standaloneNewUser(EHRRuntimeToken owner){
    Root value,valuePin;void *string=nullptr;auto status=sameCurrentOwner(owner);
    if(!status)status=invoke(meta.deviceProductUser,owner,value);
    if(!status&&value.token){status=pin(value.token,valuePin,&string);if(!status&&(!string||api.string_length(string)!=0))status=EHR_RUNTIME_UNSUPPORTED;}
    return status;
}
void preserveAcquisition(std::unique_ptr<Context> &context) noexcept{
    @try{try{if(context&&!captured&&enabled.load()&&acquisitionPending(*context)==EHR_RUNTIME_OK){captured=std::move(context);hasCaptured.store(true);}}catch(...){}}
    @catch(__unused NSException *e){}
}
int32_t classifyCallback(Context &context,void *pinnedManager){
    Root reflected,target,list,listPin;void *array=nullptr;EHRRuntimeToken method=0;uint64_t observed=0;int32_t same=0;const void *nativeMethod=nullptr,*declaring=nullptr;
    auto status=invoke(meta.delegateMethod,context.success.token,reflected);
    if(!status)status=ehr_runtime_method_from_object(reflected.token,&method);
    if(!status)status=EHRRuntimeBorrowMethod(method,&nativeMethod,&declaring);
    if(!status&&(!nativeMethod||declaring!=meta.managerClass))status=EHR_RUNTIME_TYPE_MISMATCH;
    if(!status){
        const auto normal=ehr_runtime_validate_native_method(method,meta.normalCallbackRVA,&observed);
        if(normal==EHR_RUNTIME_OK)context.normalFlow=true;
        else if(normal==EHR_RUNTIME_TYPE_MISMATCH&&ehr_runtime_validate_native_method(method,meta.silentCallbackRVA,&observed)==EHR_RUNTIME_OK)context.normalFlow=false;
        else status=EHR_RUNTIME_UNSUPPORTED;
    }
    if(!status)status=invoke(meta.delegateTarget,context.success.token,target);
    if(!status)status=ehr_runtime_object_same(target.token,context.manager.token,&same);
    if(!status&&!same)status=EHR_RUNTIME_TYPE_MISMATCH;
    if(!status)status=invoke(meta.delegateList,context.success.token,list);
    if(!status)status=pin(list.token,listPin,&array);
    if(!status&&(!array||api.array_length(array)!=1))status=EHR_RUNTIME_UNSUPPORTED;
    if(!status)context.priorFull=lastFullOwnerWeak&&api.gchandle_get_target(lastFullOwnerWeak)==pinnedManager;
    return status;
}
int32_t callFailure(Context &context){
    if(context.failureDelivered)return EHR_RUNTIME_OK;
    context.failureDelivered=true;
    Root result;
    if(context.failure.token){failureCalls.fetch_add(1);return invoke(meta.actionInvoke,context.failure.token,result);}
    if(!context.normalFlow)return EHR_RUNTIME_OK;
    auto status=sameCurrentOwner(context.manager.token);Root account,exception;
    if(status)return status;
    // The normal outer intentionally passes no failure Action. Use only the
    // game's UI-only provider error path, never PlatformSignInFail's automatic
    // temporary-guest branch or any account creation/link/permission operation.
    if(!api.class_is_inited(meta.accountParent))return EHR_RUNTIME_NOT_READY;
    void *owner=nullptr;api.field_static_get_value(meta.accountInstanceField,&owner);
    if(!owner||api.object_get_class(owner)!=meta.accountClass)return EHR_RUNTIME_NOT_READY;
    status=EHRRuntimeActionRootBorrowed(owner,&account.token);if(status)return status;
    const int32_t error=22;
    const EHRRuntimeArgument args[]={{EHR_RUNTIME_VALUE,0,meta.errorEnum,&error,sizeof(error)},{EHR_RUNTIME_REFERENCE,0,0,nullptr,0}};
    failureCalls.fetch_add(1);return ehr_runtime_invoke(meta.signInFail,account.token,args,2,&result.token,&exception.token);
}
int32_t failureSafely(Context &context) noexcept{
    @try{try{return callFailure(context);}catch(...){return EHR_RUNTIME_LIMIT;}}
    @catch(__unused NSException *e){return EHR_RUNTIME_NOT_READY;}
}
void abandonCompletion() noexcept{
    awaitingFull=false;awaitingStatus.store(false);fullCompleted.store(false);newUserMigrationValidated.store(false);
    forgetFullOwner();
    memset(completionCredentialDigest,0,sizeof(completionCredentialDigest));
    completionFence=completionOwner.token!=0;fenceStatus.store(completionFence);
    if(!completionFence)completionFromNewUser=false;
}
int32_t directRef(const void *method,EHRRuntimeToken receiver,EHRRuntimeToken value,bool valueReceiver){
    Root receiverPin,valuePin,exceptionRoot;void *target=nullptr,*boxed=nullptr;
    auto status=pin(receiver,receiverPin,&target);if(!status)status=pin(value,valuePin,&boxed);
    if(status||!target||!boxed)return status?status:EHR_RUNTIME_NOT_READY;
    if(api.object_get_class(boxed)!=meta.infoClass)return EHR_RUNTIME_TYPE_MISMATCH;
    if(api.object_get_class(target)!=(valueReceiver?meta.internalClass:meta.callbackClass))return EHR_RUNTIME_TYPE_MISMATCH;
    void *output=api.object_unbox(boxed);void *self=valueReceiver?api.object_unbox(target):target;
    if(!self||!output)return EHR_RUNTIME_NOT_READY;
    void *args[]={output};void *exception=nullptr;
    api.runtime_invoke(method,self,args,&exception);
    if(exception){status=EHRRuntimeActionRootBorrowed(exception,&exceptionRoot.token);return status?status:EHR_RUNTIME_MANAGED_EXCEPTION;}
    return EHR_RUNTIME_OK;
}
int32_t marshal(const ehr_itch::LoginInfo &actual,Root &managed,bool record=true){
    // ClientData is our native opaque correlation cookie, NOT a managed GCHandle.
    // Never pass it to Helper's managed ClientData decoder. The game callbacks
    // receive null ClientData, matching their ordinary unused clientData input.
    ehr_itch::LoginInfo input=actual;input.clientData=nullptr;
    Root internal;auto status=ehr_runtime_box(meta.internal,&input,sizeof(input),&internal.token);
    if(status)return status;
    void *object=api.object_new(meta.infoClass);if(!object)return EHR_RUNTIME_NOT_READY;
    status=EHRRuntimeActionRootBorrowed(object,&managed.token);if(status)return status;
    if(record)marshalCalls.fetch_add(1);return directRef(meta.marshalMethod,internal.token,managed.token,true);
}
[[maybe_unused]] bool sdkPin(){
    void *symbol=dlsym(RTLD_DEFAULT,"EOS_Connect_Login");Dl_info info{};
    if(!symbol||!dladdr(symbol,&info)||!info.dli_fbase||!info.dli_fname)return false;
    NSString *actual=[NSString stringWithUTF8String:info.dli_fname];
    NSString *expected=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"EOSSDK.framework/EOSSDK"];
    if(!actual||!expected||![actual.stringByResolvingSymlinksInPath isEqualToString:expected.stringByResolvingSymlinksInPath])return false;
    const auto *header=static_cast<const mach_header_64 *>(info.dli_fbase);
    if(header->magic!=MH_MAGIC_64||header->cputype!=CPU_TYPE_ARM64||header->filetype!=MH_DYLIB||header->ncmds>4096||header->sizeofcmds>1024*1024)return false;
    const uint8_t *cursor=reinterpret_cast<const uint8_t *>(header)+sizeof(*header),*end=cursor+header->sizeofcmds;
    bool uuid=false,text=false;
    for(uint32_t i=0;i<header->ncmds;++i){
        if(end-cursor<static_cast<ptrdiff_t>(sizeof(load_command)))return false;
        const auto *command=reinterpret_cast<const load_command *>(cursor);
        if(command->cmdsize<sizeof(load_command)||command->cmdsize%8||command->cmdsize>static_cast<size_t>(end-cursor))return false;
        if(command->cmd==LC_UUID){if(uuid||command->cmdsize!=sizeof(uuid_command))return false;uuid=!memcmp(reinterpret_cast<const uuid_command *>(command)->uuid,ehr_itch::sdkUUID,16);if(!uuid)return false;}
        if(command->cmd==LC_SEGMENT_64){
            if(command->cmdsize<sizeof(segment_command_64))return false;
            const auto *segment=reinterpret_cast<const segment_command_64 *>(command);
            if(segment->nsects>(command->cmdsize-sizeof(*segment))/sizeof(section_64))return false;
            const auto *sections=reinterpret_cast<const section_64 *>(segment+1);
            for(uint32_t j=0;j<segment->nsects;++j)if(!strncmp(sections[j].segname,"__TEXT",16)&&!strncmp(sections[j].sectname,"__text",16)){
                if(text||sections[j].addr!=ehr_itch::sdkTextRVA||sections[j].size!=ehr_itch::sdkTextBytes)return false;
                uint8_t digest[CC_SHA256_DIGEST_LENGTH];
                CC_SHA256(reinterpret_cast<const uint8_t *>(header)+sections[j].addr,static_cast<CC_LONG>(sections[j].size),digest);
                text=!memcmp(digest,ehr_itch::sdkTextSHA,sizeof(digest));if(!text)return false;
            }
        }cursor+=command->cmdsize;
    }
    if(cursor!=end||!uuid||!text||reinterpret_cast<uintptr_t>(symbol)!=reinterpret_cast<uintptr_t>(header)+ehr_itch::sdkLoginRVA)return false;
    sdkLogin=reinterpret_cast<ehr_itch::Login>(symbol);return true;
}
[[maybe_unused]] bool classInitPin(){
    void *entry=dlsym(RTLD_DEFAULT,"il2cpp_runtime_class_init");Dl_info image{};
    if(!entry||ehr_pinned::validate_engine_entry(entry)!=EHR_RUNTIME_OK||!dladdr(entry,&image)||!image.dli_fbase)return false;
    const auto base=reinterpret_cast<uintptr_t>(image.dli_fbase);
    if(reinterpret_cast<uintptr_t>(entry)!=base+ehr_itch::classInitExportRVA)return false;
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(entry,4,digest);
    if(memcmp(digest,ehr_itch::classInitExportSHA,sizeof(digest)))return false;
    CC_SHA256(reinterpret_cast<const void *>(base+ehr_itch::classInitImplRVA),60,digest);
    return !memcmp(digest,ehr_itch::classInitFastPathSHA,sizeof(digest));
}
[[maybe_unused]] int32_t find(EHRRuntimeToken owner,const char *name,const char *const *params,size_t count,const char *result,uint64_t rva,EHRRuntimeToken &token){
    auto status=ehr_runtime_find_method(owner,name,params,count,result,0,&token);uint64_t observed=0;
    if(!status&&rva)status=ehr_runtime_validate_native_method(token,rva,&observed);return status;
}
int32_t prepare(){
    if(!mainThread())return EHR_RUNTIME_WRONG_THREAD;
    if(prepared.load()==EHR_RUNTIME_OK)return EHR_RUNTIME_OK;
#if !EHR_ITCH_BINDING_AVAILABLE
    return EHR_RUNTIME_UNSUPPORTED;
#else
#define LOAD(field,symbol) do{void *p=dlsym(RTLD_DEFAULT,symbol);if(!p||ehr_pinned::validate_engine_entry(p)!=EHR_RUNTIME_OK)return EHR_RUNTIME_NOT_READY;api.field=reinterpret_cast<decltype(api.field)>(p);}while(0)
    LOAD(object_get_class,"il2cpp_object_get_class");LOAD(object_new,"il2cpp_object_new");LOAD(object_unbox,"il2cpp_object_unbox");
    LOAD(class_is_valuetype,"il2cpp_class_is_valuetype");LOAD(class_has_references,"il2cpp_class_has_references");LOAD(class_is_inited,"il2cpp_class_is_inited");
    LOAD(class_instance_size,"il2cpp_class_instance_size");LOAD(class_value_size,"il2cpp_class_value_size");LOAD(class_get_parent,"il2cpp_class_get_parent");
    LOAD(class_get_type,"il2cpp_class_get_type");LOAD(class_from_type,"il2cpp_class_from_type");LOAD(class_get_methods,"il2cpp_class_get_methods");LOAD(method_get_name,"il2cpp_method_get_name");
    LOAD(class_get_fields,"il2cpp_class_get_fields");LOAD(field_get_name,"il2cpp_field_get_name");LOAD(field_get_type,"il2cpp_field_get_type");LOAD(field_get_flags,"il2cpp_field_get_flags");LOAD(field_get_offset,"il2cpp_field_get_offset");
    LOAD(field_static_get_value,"il2cpp_field_static_get_value");LOAD(field_get_value,"il2cpp_field_get_value");LOAD(type_get_name,"il2cpp_type_get_name");LOAD(runtime_free,"il2cpp_free");LOAD(runtime_invoke,"il2cpp_runtime_invoke");
    LOAD(array_length,"il2cpp_array_length");LOAD(string_length,"il2cpp_string_length");LOAD(gchandle_new_weakref,"il2cpp_gchandle_new_weakref");LOAD(gchandle_get_target,"il2cpp_gchandle_get_target");LOAD(gchandle_free,"il2cpp_gchandle_free");
#undef LOAD
    int32_t status=ehr_runtime_find_class("Assembly-CSharp.dll","","EOSManager",&meta.manager);
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp-firstpass.dll","Epic.OnlineServices.Connect","OnLoginCallback",&meta.callback);
    if(!status)status=ehr_runtime_find_class("mscorlib.dll","System","Action",&meta.action);
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp-firstpass.dll","Epic.OnlineServices.Connect","LoginCallbackInfoInternal",&meta.internal);
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp-firstpass.dll","Epic.OnlineServices.Connect","LoginCallbackInfo",&meta.info);
    EHRRuntimeToken platform=0,handle=0,credentials=0,options=0,method=0,delegate=0,data=0,player=0,playerAccount=0,statusEnum=0;
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp-firstpass.dll","Epic.OnlineServices.Platform","PlatformInterface",&platform);
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp-firstpass.dll","Epic.OnlineServices","Handle",&handle);
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp-firstpass.dll","Epic.OnlineServices.Connect","CredentialsInternal",&credentials);
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp-firstpass.dll","Epic.OnlineServices.Connect","LoginOptionsInternal",&options);
    if(!status)status=ehr_runtime_find_class("mscorlib.dll","System","Delegate",&delegate);
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp.dll","","AccountManager",&meta.account);
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp.dll","","EOSManager+EOS_ERRORS",&meta.errorEnum);
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp.dll","AmongUs.Data","DataManager",&data);
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp.dll","AmongUs.Data.Player","PlayerData",&player);
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp.dll","AmongUs.Data.Player","PlayerAccountData",&playerAccount);
    if(!status)status=ehr_runtime_find_class("Assembly-CSharp.dll","","EOSManager+AccountLoginStatus",&statusEnum);
    if(!status)status=find(meta.manager,"get_PlatformInterface",nullptr,0,"Epic.OnlineServices.Platform.PlatformInterface",EHRItchGetPlatformRVA,meta.getPlatform);
    if(!status)status=find(platform,"GetConnectInterface",nullptr,0,"Epic.OnlineServices.Connect.ConnectInterface",EHRItchGetConnectRVA,meta.getConnect);
    if(!status)status=find(handle,"get_InnerHandle",nullptr,0,"System.IntPtr",EHRItchGetHandleRVA,meta.getHandle);
    if(!status)status=find(meta.manager,"InitializeHelper",nullptr,0,"System.Void",EHRItchInitializeHelperRVA,meta.initialize);
    if(!status)status=find(meta.manager,"LoginWithCorrectPlatform",nullptr,0,"System.Void",EHRItchAuthLoginRVA,meta.normalLogin);
    if(!status)status=find(meta.manager,"get_DeviceIDProductUserId",nullptr,0,"System.String",EHRItchAuthDeviceIDProductUserIdRVA,meta.deviceProductUser);
    if(!status)status=find(meta.action,"Invoke",nullptr,0,"System.Void",0,meta.actionInvoke);
    if(!status)status=find(meta.info,"get_ResultCode",nullptr,0,"Epic.OnlineServices.Result",0x1aae088,meta.resultGetter);
    if(!status)status=find(delegate,"get_Method",nullptr,0,"System.Reflection.MethodInfo",0,meta.delegateMethod);
    if(!status)status=find(delegate,"get_Target",nullptr,0,"System.Object",0,meta.delegateTarget);
    if(!status)status=find(delegate,"GetInvocationList",nullptr,0,"System.Delegate[]",0,meta.delegateList);
    if(!status){const char *params[]={"System.Type","System.Object","System.Reflection.MethodInfo"};status=ehr_runtime_find_method(delegate,"CreateDelegate",params,3,"System.Delegate",1,&meta.delegateFactory);}
    meta.normalCallbackRVA=EHRItchAuthNormalCallbackRVA;meta.silentCallbackRVA=EHRItchAuthSilentCallbackRVA;
    const char *callbackParam[]={"Epic.OnlineServices.Connect.LoginCallbackInfo&"};const void *declaring=nullptr;
    if(!status)status=find(meta.internal,"Get",callbackParam,1,"System.Void",EHRItchMarshalCallbackRVA,method);
    if(!status)status=EHRRuntimeBorrowMethod(method,&meta.marshalMethod,&declaring);
    if(!status)status=find(meta.callback,"Invoke",callbackParam,1,"System.Void",EHRItchInvokeCallbackRVA,method);
    if(!status)status=EHRRuntimeBorrowMethod(method,&meta.invokeMethod,&declaring);
    if(!status)status=find(meta.manager,"EOSConnectPlatformSilentLoginCallback",callbackParam,1,"System.Void",EHRItchAuthSilentCallbackRVA,meta.silentMethod);
    if(!status)status=EHRRuntimeBorrowClass(meta.manager,&meta.managerClass);
    if(!status)status=EHRRuntimeBorrowClass(meta.callback,&meta.callbackClass);
    if(!status)status=EHRRuntimeBorrowClass(meta.action,&meta.actionClass);
    if(!status)status=EHRRuntimeBorrowClass(meta.internal,&meta.internalClass);
    if(!status)status=EHRRuntimeBorrowClass(meta.info,&meta.infoClass);
    if(!status)status=EHRRuntimeBorrowClass(meta.account,&meta.accountClass);
    if(!status)status=EHRRuntimeBorrowClass(data,&meta.dataManagerClass);
    if(!status)status=EHRRuntimeBorrowClass(player,&meta.playerClass);
    if(!status)status=EHRRuntimeBorrowClass(playerAccount,&meta.playerAccountClass);
    if(!status){
        meta.parentClass=api.class_get_parent(meta.managerClass);
        if(!meta.parentClass||!typeIs(api.class_get_type(meta.parentClass),"DestroyableSingleton<EOSManager>")||!noInitializer(meta.parentClass)||!noInitializer(meta.managerClass))status=EHR_RUNTIME_UNSUPPORTED;
        else meta.instanceField=ownField(meta.parentClass,"_instance","EOSManager",true);
        if(!meta.instanceField)status=EHR_RUNTIME_TYPE_MISMATCH;
    }
    if(!status&&(!ownField(meta.managerClass,"successCallback","Epic.OnlineServices.Connect.OnLoginCallback",false)||!ownField(meta.managerClass,"onLoginFailedCallback","System.Action",false)))status=EHR_RUNTIME_TYPE_MISMATCH;
    if(!status)status=ehr_runtime_find_field(meta.manager,"successCallback","Epic.OnlineServices.Connect.OnLoginCallback",0,&meta.successField);
    if(!status)status=ehr_runtime_find_field(meta.manager,"onLoginFailedCallback","System.Action",0,&meta.failureField);
    if(!status)status=ehr_runtime_find_field(meta.manager,"tryingToLogin","System.Boolean",0,&meta.tryingField);
    if(!status&&!ownField(meta.managerClass,"continuanceToken","Epic.OnlineServices.ContinuanceToken",false))status=EHR_RUNTIME_TYPE_MISMATCH;
    if(!status)status=ehr_runtime_find_field(meta.manager,"continuanceToken","Epic.OnlineServices.ContinuanceToken",0,&meta.continuanceField);
    if(!status){
        meta.accountParent=api.class_get_parent(meta.accountClass);
        if(!meta.accountParent||!typeIs(api.class_get_type(meta.accountParent),"DestroyableSingleton<AccountManager>")||!noInitializer(meta.accountParent))status=EHR_RUNTIME_UNSUPPORTED;
        else meta.accountInstanceField=ownField(meta.accountParent,"_instance","AccountManager",true);
        if(!meta.accountInstanceField)status=EHR_RUNTIME_TYPE_MISMATCH;
    }
    if(!status){
        const void *errorClass=nullptr;status=EHRRuntimeBorrowClass(meta.errorEnum,&errorClass);
        char *name=!status?api.type_get_name(api.class_get_type(errorClass)):nullptr;
        if(!status&&!name)status=EHR_RUNTIME_NOT_READY;
        if(!status){const char *parameters[]={name,"System.Action"};status=find(meta.account,"SignInFail",parameters,2,"System.Void",EHRItchAuthFailureUIRVA,meta.signInFail);}
        if(name)api.runtime_free(name);
    }
    if(!status){
        meta.playerStorage=ownField(meta.dataManagerClass,"player","AmongUs.Data.Player.PlayerData",true);
        meta.playerAccountField=ownField(meta.playerClass,"account","AmongUs.Data.Player.PlayerAccountData",false);
        if(!meta.playerStorage||!meta.playerAccountField)status=EHR_RUNTIME_TYPE_MISMATCH;
        const void *enumClass=nullptr;if(!status)status=EHRRuntimeBorrowClass(statusEnum,&enumClass);
        char *name=!status?api.type_get_name(api.class_get_type(enumClass)):nullptr;
        if(!status&&!name)status=EHR_RUNTIME_NOT_READY;
        if(!status)status=find(playerAccount,"get_LoginStatus",nullptr,0,name,0x1e49774,meta.loginStatus);
        if(name)api.runtime_free(name);
    }
    const FieldFact ci[]={{"m_ApiVersion","System.Int32",0},{"m_Token","System.IntPtr",8},{"m_Type","Epic.OnlineServices.ExternalCredentialType",16}};
    const FieldFact op[]={{"m_ApiVersion","System.Int32",0},{"m_Credentials","System.IntPtr",8},{"m_UserLoginInfo","System.IntPtr",16}};
    const FieldFact in[]={{"m_ResultCode","Epic.OnlineServices.Result",0},{"m_ClientData","System.IntPtr",8},{"m_LocalUserId","System.IntPtr",16},{"m_ContinuanceToken","System.IntPtr",24}};
    const FieldFact out[]={{"<ResultCode>k__BackingField","Epic.OnlineServices.Result",0},{"<ClientData>k__BackingField","System.Object",8},{"<LocalUserId>k__BackingField","Epic.OnlineServices.ProductUserId",16},{"<ContinuanceToken>k__BackingField","Epic.OnlineServices.ContinuanceToken",24}};
    const void *c=nullptr,*o=nullptr;
    if(!status)status=EHRRuntimeBorrowClass(credentials,&c);if(!status)status=EHRRuntimeBorrowClass(options,&o);
    if(!status&&(!exactValue(c,sizeof(ehr_itch::Credentials),false,ci,3)||!exactValue(o,sizeof(ehr_itch::LoginOptions),false,op,3)||!exactValue(meta.internalClass,sizeof(ehr_itch::LoginInfo),false,in,4)||!exactValue(meta.infoClass,32,true,out,4)))status=EHR_RUNTIME_TYPE_MISMATCH;
    if(!status&&(!sdkPin()||!classInitPin()))status=EHR_RUNTIME_TYPE_MISMATCH;
    return status;
#endif
}
int32_t deliverOriginal(Request &active,const ehr_itch::LoginInfo &data,bool confirmedNewUser){
    Root info;auto status=marshal(data,info);
    if(!status&&active.context->normalFlow)status=ehr_runtime_object_retain(active.context->manager.token,&completionOwner.token);
    if(!status){
        awaitingFull=active.context->normalFlow;awaitingStatus.store(awaitingFull);
        completionFromNewUser=confirmedNewUser;newUserMigrationValidated.store(false);
        completionGuardFailure=EHR_RUNTIME_OK;
        if(data.result==0)successCalls.fetch_add(1);else if(!active.context->normalFlow)silentFailureCalls.fetch_add(1);
        if(awaitingFull)memcpy(completionCredentialDigest,active.credentialDigest,sizeof(completionCredentialDigest));
        active.context->originalEntered=true;
        status=directRef(meta.invokeMethod,active.context->success.token,info.token,false);
        if(!status&&completionGuardFailure)status=completionGuardFailure;
        if(!status){
            callbackDelivered.store(true);successDelivered.store(data.result==0);
            if(!active.context->normalFlow){
                Root pinOwner;void *owner=nullptr;const auto ownerStatus=pin(active.context->manager.token,pinOwner,&owner);
                fullCompleted.store(data.result==0&&!ownerStatus&&active.context->priorFull&&lastFullOwnerWeak&&api.gchandle_get_target(lastFullOwnerWeak)==owner);
                completionOwner.reset();
            }
        }else abandonCompletion();
    }
    if(awaitingFull){
        const auto completedCount=completions.load();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,90*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if(awaitingFull&&completions.load()==completedCount)EHRItchAuthCancel();
        });
    }
    return status;
}
void expireNewUserCandidate(uintptr_t cookie){
    if(newUserCandidate&&newUserCandidate->request->cookie==cookie)EHRItchAuthCancel();
}
void receive(ehr_itch::LoginInfo data){
    if(!mainThread())return;
    const auto cookie=reinterpret_cast<uintptr_t>(data.clientData);
    if(!request||request->cookie!=cookie){lateCallbacks.fetch_add(1);return;}
    auto active=std::move(request);completions.fetch_add(1);delivering=true;
    struct DeliveryEnd {
        std::unique_ptr<Request> &active;bool finished=false;
        ~DeliveryEnd(){
            if(!finished){if(active&&active->context){failureSafely(*active->context);preserveAcquisition(active->context);}abandonCompletion();}
            pending.store(false);delivering=false;
        }
    } end{active};
    if(active->cancelled||!enabled.load()){lateCallbacks.fetch_add(1);return;}
    knownResult.store(true);lastEOS.store(data.result);int32_t status=sameCurrentOwner(active->context->manager.token);
    if(!status&&data.result==0&&!data.localUserId)status=EHR_RUNTIME_TYPE_MISMATCH;
    const bool silentFlow=!active->context->normalFlow;
    if(!status&&data.result==3&&!silentFlow&&!active->resultOnly&&data.continuanceToken){
        status=newUserContinuity(*active->context,data);
        if(!status){
            auto candidate=std::make_unique<NewUserCandidate>();candidate->actual=data;candidate->request=std::move(active);
            newUserCandidate=std::move(candidate);awaitingNewUser.store(true);continuityAvailable.store(true);
            const auto candidateCookie=newUserCandidate->request->cookie;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,90*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                expireNewUserCandidate(candidateCookie);
            });
            end.finished=true;localStatus.store(EHR_RUNTIME_OK);notify();return;
        }
    }
    if(!status&&(data.result==0||silentFlow)&&!active->resultOnly)status=deliverOriginal(*active,data,false);
    if(status||(!silentFlow&&data.result!=0)||active->resultOnly){const auto cleanup=callFailure(*active->context);if(!status)status=cleanup;}
    if(status||data.result!=0||active->resultOnly)preserveAcquisition(active->context);
    end.finished=true;localStatus.store(status);notify();
}
void sdkCallback(const ehr_itch::LoginInfo *info){
    if(!info)return;
    // The actual SDK callback owns this native POD for callback duration. Copy
    // only its fixed fields; never dereference or serialize any opaque handle.
    const ehr_itch::LoginInfo copy=*info;
    dispatch_async(dispatch_get_main_queue(),^{
        @try{try{receive(copy);}catch(...){localStatus.store(EHR_RUNTIME_LIMIT);notify();}}
        @catch(__unused NSException *exception){localStatus.store(EHR_RUNTIME_NOT_READY);notify();}
    });
}
int32_t retireNewUserCandidate(){
    auto old=std::move(newUserCandidate);awaitingNewUser.store(false);continuityAvailable.store(false);
    if(!old||!old->request->context)return EHR_RUNTIME_OK;
    const auto status=failureSafely(*old->request->context);preserveAcquisition(old->request->context);return status;
}
int32_t capture(void *manager,void *success,void *failure,bool impl=true){
    if(!mainThread())return EHR_RUNTIME_WRONG_THREAD;
    if(prepared.load()||!enabled.load())return EHR_RUNTIME_NOT_READY;
    retireForeignFence();
    if(request||captured||newUserCandidate||awaitingFull||completionFence||delivering)return EHR_RUNTIME_LIMIT;
    auto next=std::make_unique<Context>();
    struct CaptureEnd {Context &context;bool armed=false,finished=false;~CaptureEnd(){if(armed&&!finished)failureSafely(context);}} end{*next};
    int32_t status=EHRRuntimeActionRootBorrowed(manager,&next->manager.token);
    if(!status)status=EHRRuntimeActionRootBorrowed(success,&next->success.token);
    if(!status)status=EHRRuntimeActionRootBorrowed(failure,&next->failure.token);
    Root ownerPin,callbackPin,actionPin;void *owner=nullptr,*cb=nullptr,*action=nullptr;
    if(!status)status=pin(next->manager.token,ownerPin,&owner);
    if(!status)status=pin(next->success.token,callbackPin,&cb);
    if(!status&&next->failure.token)status=pin(next->failure.token,actionPin,&action);
    if(!status&&(!owner||!cb||api.object_get_class(owner)!=meta.managerClass||api.object_get_class(cb)!=meta.callbackClass||(action&&api.object_get_class(action)!=meta.actionClass)))status=EHR_RUNTIME_TYPE_MISMATCH;
    if(!status)status=sameCurrentOwner(next->manager.token);
    if(!status)status=classifyCallback(*next,owner);
    if(!status&&!impl&&(next->normalFlow||!next->priorFull))status=EHR_RUNTIME_NOT_READY;
    end.armed=!status;
    const EHRRuntimeArgument a{EHR_RUNTIME_REFERENCE,0,next->success.token,nullptr,0},b{EHR_RUNTIME_REFERENCE,0,next->failure.token,nullptr,0};
    if(!status&&impl)status=ehr_runtime_write_field(meta.successField,next->manager.token,&a);
    if(!status&&impl)status=ehr_runtime_write_field(meta.failureField,next->manager.token,&b);
    if(!status&&impl){Root result;status=invoke(meta.initialize,next->manager.token,result);}
    if(status){failureSafely(*next);return status;}
    knownResult.store(false);lastEOS.store(0);successDelivered.store(false);callbackDelivered.store(false);continuedNewUser.store(false);newUserMigrationValidated.store(false);fullCompleted.store(false);completionFromNewUser=false;completionGuardFailure=EHR_RUNTIME_OK;newUserMigrationStatus.store(EHR_RUNTIME_NOT_READY);localStatus.store(EHR_RUNTIME_OK);
    end.finished=true;captured=std::move(next);hasCaptured.store(true);notify();return EHR_RUNTIME_OK;
}
int32_t begin(NSData *key,bool resultOnly){
    if(!mainThread())return EHR_RUNTIME_WRONG_THREAD;
    if(newUserCandidate){const auto retired=retireNewUserCandidate();if(retired)return retired;}
    if(prepared.load()||!enabled.load()||!sdkLogin||!captured)return EHR_RUNTIME_NOT_READY;
    if(request||awaitingFull||completionFence||delivering)return EHR_RUNTIME_LIMIT;
    if(captured->normalFlow&&acquisitionPending(*captured)!=EHR_RUNTIME_OK)return EHR_RUNTIME_NOT_READY;
    if(!key||key.length==0||key.length>ehr_itch::maxKeyBytes)return EHR_RUNTIME_BAD_ARGUMENT;
    const auto *bytes=static_cast<const uint8_t *>(key.bytes);if(!bytes)return EHR_RUNTIME_BAD_ARGUMENT;
    for(NSUInteger i=0;i<key.length;++i)if(bytes[i]<0x21||bytes[i]>0x7e)return EHR_RUNTIME_BAD_ARGUMENT;
    struct Secret { std::vector<char> bytes;~Secret(){volatile char *p=bytes.data();for(size_t i=0;i<bytes.size();++i)p[i]=0;} } secret;
    secret.bytes.resize(key.length+1);memcpy(secret.bytes.data(),bytes,key.length);secret.bytes.back()=0;
    auto next=std::make_unique<Request>();auto status=sameCurrentOwner(captured->manager.token);
    CC_SHA256(secret.bytes.data(),static_cast<CC_LONG>(key.length),next->credentialDigest);
    if(!status&&!captured->normalFlow&&!resultOnly){
        uint8_t difference=0;for(size_t i=0;i<sizeof(lastFullCredentialDigest);++i)difference|=lastFullCredentialDigest[i]^next->credentialDigest[i];
        // Silent callbacks do not redo storage/age/full-account initialization.
        // They may renew ONLY this process's prior fully completed same-owner,
        // same-credential session; a different key requires normal login flow.
        if(!captured->priorFull||!lastFullCredentialKnown||difference)status=EHR_RUNTIME_UNSUPPORTED;
    }
    if(!status)status=invoke(meta.getPlatform,captured->manager.token,next->platform);
    if(!status&&!next->platform.token)status=EHR_RUNTIME_NOT_READY;
    if(!status)status=invoke(meta.getConnect,next->platform.token,next->connect);
    if(!status&&!next->connect.token)status=EHR_RUNTIME_NOT_READY;
    Root handle;uintptr_t pointer=0;size_t copied=0;
    if(!status)status=invoke(meta.getHandle,next->connect.token,handle);
    if(!status)status=ehr_runtime_copy_value(handle.token,&pointer,sizeof(pointer),&copied);
    if(!status&&(!pointer||copied!=sizeof(pointer)))status=EHR_RUNTIME_TYPE_MISMATCH;
    if(status)return status;
    if(nextCookie==UINTPTR_MAX)return EHR_RUNTIME_LIMIT;
    next->cookie=nextCookie++;next->context=std::move(captured);next->context->failureDelivered=false;next->resultOnly=resultOnly;
    const auto cookie=next->cookie;request=std::move(next);hasCaptured.store(false);pending.store(true);
    const ehr_itch::Credentials credentials{ehr_itch::credentialsVersion,secret.bytes.data(),ehr_itch::keyCredentialType};
    const ehr_itch::LoginOptions options{ehr_itch::loginVersion,&credentials,nullptr};
    sdkCalls.fetch_add(1);sdkLogin(reinterpret_cast<void *>(pointer),&options,reinterpret_cast<void *>(cookie),sdkCallback);
    // The original SDK C# marshaler disposes these option/string buffers after
    // the same synchronous C call. No borrowed key remains after this return.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,90*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(request&&request->cookie==cookie&&!request->cancelled)EHRItchAuthCancel();
    });
    return EHR_RUNTIME_OK;
}
int32_t confirmNewUser(){
    if(!mainThread())return EHR_RUNTIME_WRONG_THREAD;
    if(prepared.load()||!enabled.load()||!newUserCandidate)return EHR_RUNTIME_NOT_READY;
    if(request||captured||awaitingFull||completionFence||delivering)return EHR_RUNTIME_LIMIT;
    auto candidate=std::move(newUserCandidate);awaitingNewUser.store(false);continuityAvailable.store(false);delivering=true;
    struct ConfirmEnd {
        NewUserCandidate &candidate;bool finished=false;
        ~ConfirmEnd(){if(!finished){failureSafely(*candidate.request->context);preserveAcquisition(candidate.request->context);abandonCompletion();}delivering=false;}
    } end{*candidate};
    auto status=newUserContinuity(*candidate->request->context,candidate->actual);
    if(!status)status=standaloneNewUser(candidate->request->context->manager.token);
    if(!status){continuedNewUser.store(true);status=deliverOriginal(*candidate->request,candidate->actual,true);}
    if(status){const auto cleanup=failureSafely(*candidate->request->context);(void)cleanup;preserveAcquisition(candidate->request->context);}
    end.finished=true;localStatus.store(status);notify();return status;
}
int32_t cancel(){
    if(!mainThread())return EHR_RUNTIME_WRONG_THREAD;
    int32_t status=EHR_RUNTIME_OK;cancelCount.fetch_add(1);
    if(newUserCandidate)status=retireNewUserCandidate();
    if(captured){auto context=std::move(captured);hasCaptured.store(false);status=failureSafely(*context);preserveAcquisition(context);}
    if(request&&!request->cancelled){request->cancelled=true;const auto cleanup=request->context?failureSafely(*request->context):EHR_RUNTIME_OK;if(!status)status=cleanup;preserveAcquisition(request->context);request->context.reset();}
    if(awaitingFull){awaitingFull=false;awaitingStatus.store(false);completionFence=true;fenceStatus.store(true);}
    memset(completionCredentialDigest,0,sizeof(completionCredentialDigest));newUserMigrationValidated.store(false);
    forgetFullOwner();fullCompleted.store(false);localStatus.store(status?status:EHR_RUNTIME_NOT_READY);notify();return status;
}
}

extern "C" int32_t EHRItchAuthPrepare(void){
    if(!mainThread())return EHR_RUNTIME_WRONG_THREAD;
    int32_t status=EHR_RUNTIME_NOT_READY;@try{try{status=prepare();}catch(...){status=EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *e){status=EHR_RUNTIME_NOT_READY;}
    prepared.store(status);localStatus.store(status);return status;
}
extern "C" int32_t EHRItchAuthSetEnabled(int32_t value){
    if(!mainThread())return EHR_RUNTIME_WRONG_THREAD;if(value!=0&&value!=1)return EHR_RUNTIME_BAD_ARGUMENT;
    if(value&&prepared.load())return EHR_RUNTIME_NOT_READY;
    enabled.store(value!=0);if(!value)EHRItchAuthCancel();return EHR_RUNTIME_OK;
}
extern "C" int32_t EHRItchAuthCapture(void *owner,void *success,void *failure){
    @try{try{return capture(owner,success,failure);}catch(...){localStatus.store(EHR_RUNTIME_LIMIT);return EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *e){localStatus.store(EHR_RUNTIME_NOT_READY);return EHR_RUNTIME_NOT_READY;}
}
extern "C" int32_t EHRItchAuthCaptureSilent(void *manager){
    if(!mainThread())return EHR_RUNTIME_WRONG_THREAD;
    if(prepared.load()||!enabled.load())return EHR_RUNTIME_NOT_READY;
    @try{try{
        Root owner,ownerPin,callback,callbackPin;void *pinnedOwner=nullptr,*pinnedCallback=nullptr;
        int32_t status=EHRRuntimeActionRootBorrowed(manager,&owner.token);
        if(!status)status=pin(owner.token,ownerPin,&pinnedOwner);
        if(!status&&(!pinnedOwner||api.object_get_class(pinnedOwner)!=meta.managerClass))status=EHR_RUNTIME_TYPE_MISMATCH;
        if(!status)status=sameCurrentOwner(owner.token);
        if(!status&&(!lastFullOwnerWeak||!lastFullCredentialKnown||api.gchandle_get_target(lastFullOwnerWeak)!=pinnedOwner))status=EHR_RUNTIME_NOT_READY;
        if(!status)status=makeSilentDelegate(owner.token,callback);
        if(!status)status=pin(callback.token,callbackPin,&pinnedCallback);
        if(!status)status=capture(pinnedOwner,pinnedCallback,nullptr,false);
        localStatus.store(status);return status;
    }catch(...){localStatus.store(EHR_RUNTIME_LIMIT);return EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *e){localStatus.store(EHR_RUNTIME_NOT_READY);return EHR_RUNTIME_NOT_READY;}
}
extern "C" int32_t EHRItchAuthIsGuestSilentPath(void *manager,bool *isGuest){
    if(!isGuest)return EHR_RUNTIME_BAD_ARGUMENT;*isGuest=false;
    if(!mainThread())return EHR_RUNTIME_WRONG_THREAD;if(prepared.load())return EHR_RUNTIME_NOT_READY;
    @try{try{
        Root owner,player,playerPin,account,result;void *playerObject=nullptr,*accountObject=nullptr;
        int32_t status=EHRRuntimeActionRootBorrowed(manager,&owner.token);
        if(!status)status=sameCurrentOwner(owner.token);
        // class_is_inited is metadata readiness, NOT .cctor completion. The
        // signed-pinned public Runtime::ClassInit fast path independently proves
        // this additional flag. Refuse unknown/in-progress initialization.
        if(!status&&!api.class_is_inited(meta.dataManagerClass))status=EHR_RUNTIME_NOT_READY;
        if(!status){const auto *flag=reinterpret_cast<const uint32_t *>(static_cast<const uint8_t *>(meta.dataManagerClass)+ehr_itch::classCtorCompleteOffset);if(__atomic_load_n(flag,__ATOMIC_ACQUIRE)!=1)status=EHR_RUNTIME_NOT_READY;}
        if(!status){api.field_static_get_value(meta.playerStorage,&playerObject);if(!playerObject||api.object_get_class(playerObject)!=meta.playerClass)status=EHR_RUNTIME_NOT_READY;}
        if(!status)status=EHRRuntimeActionRootBorrowed(playerObject,&player.token);
        if(!status)status=pin(player.token,playerPin,&playerObject);
        if(!status&&(!playerObject||api.object_get_class(playerObject)!=meta.playerClass))status=EHR_RUNTIME_TYPE_MISMATCH;
        if(!status){api.field_get_value(playerObject,meta.playerAccountField,&accountObject);if(!accountObject||api.object_get_class(accountObject)!=meta.playerAccountClass)status=EHR_RUNTIME_NOT_READY;}
        if(!status)status=EHRRuntimeActionRootBorrowed(accountObject,&account.token);
        if(!status)status=invoke(meta.loginStatus,account.token,result);
        int32_t value=-1;size_t count=0;if(!status)status=ehr_runtime_copy_value(result.token,&value,sizeof(value),&count);
        if(!status&&(count!=sizeof(value)||value<0||value>3))status=EHR_RUNTIME_UNSUPPORTED;
        if(!status)*isGuest=value==3;return status;
    }catch(...){return EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *e){return EHR_RUNTIME_NOT_READY;}
}
extern "C" int32_t EHRItchAuthBegin(NSData *key,bool resultOnly){
    @try{try{const auto status=begin(key,resultOnly);localStatus.store(status);return status;}catch(...){cancel();localStatus.store(EHR_RUNTIME_LIMIT);return EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *e){cancel();localStatus.store(EHR_RUNTIME_NOT_READY);return EHR_RUNTIME_NOT_READY;}
}
extern "C" int32_t EHRItchAuthConfirmNewUser(void){
    @try{try{return confirmNewUser();}catch(...){localStatus.store(EHR_RUNTIME_LIMIT);notify();return EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *e){localStatus.store(EHR_RUNTIME_NOT_READY);notify();return EHR_RUNTIME_NOT_READY;}
}
extern "C" int32_t EHRItchAuthCheckNewUserMigration(void *manager){
    if(!mainThread())return EHR_RUNTIME_WRONG_THREAD;
    if(!completionFromNewUser)return EHR_RUNTIME_OK;
    int32_t status=EHR_RUNTIME_NOT_READY;
    @try{try{
        Root current;int32_t same=0;status=EHRRuntimeActionRootBorrowed(manager,&current.token);
        if(!status)status=ehr_runtime_object_same(current.token,completionOwner.token,&same);
        if(!status&&!same)return EHR_RUNTIME_OK;
        newUserMigrationChecks.fetch_add(1);
        if(!status&&(prepared.load()||!enabled.load()||!awaitingFull||completionFence||!completionOwner.token))status=EHR_RUNTIME_NOT_READY;
        if(!status)status=standaloneNewUser(completionOwner.token);
    }catch(...){status=EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *e){status=EHR_RUNTIME_NOT_READY;}
    newUserMigrationStatus.store(status);newUserMigrationValidated.store(status==EHR_RUNTIME_OK);
    if(status){newUserMigrationRejections.fetch_add(1);completionGuardFailure=status;abandonCompletion();localStatus.store(status);notify();}
    return status;
}
extern "C" int32_t EHRItchAuthCancel(void){@try{try{return cancel();}catch(...){localStatus.store(EHR_RUNTIME_LIMIT);return EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *e){localStatus.store(EHR_RUNTIME_NOT_READY);return EHR_RUNTIME_NOT_READY;}}
extern "C" int32_t EHRItchAuthRequestPlatformLogin(void){
    if(!mainThread())return EHR_RUNTIME_WRONG_THREAD;if(prepared.load()||!enabled.load())return EHR_RUNTIME_NOT_READY;
    retireForeignFence();if(request||awaitingFull||completionFence||delivering)return EHR_RUNTIME_LIMIT;
    if(newUserCandidate){if(newUserContinuity(*newUserCandidate->request->context,newUserCandidate->actual)==EHR_RUNTIME_OK)return EHR_RUNTIME_OK;(void)retireNewUserCandidate();}
    if(captured){if(acquisitionPending(*captured)==EHR_RUNTIME_OK)return EHR_RUNTIME_OK;captured.reset();hasCaptured.store(false);}
    @try{try{Root owner,result;int32_t status=existingManager(owner);if(!status)status=invoke(meta.normalLogin,owner.token,result);if(!status&&!captured&&!request&&!awaitingFull)status=EHR_RUNTIME_NOT_READY;localStatus.store(status);return status;}catch(...){return EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *e){return EHR_RUNTIME_NOT_READY;}
}
extern "C" void EHRItchAuthSetResultHandler(EHRItchAuthResultHandler handler){if(mainThread())resultHandler=[handler copy];}
extern "C" void EHRItchAuthObserveFullCompletion(void *manager){
    if(!mainThread()||prepared.load()||!completionOwner.token)return;
    @try{try{
        Root current;int32_t same=0;auto status=EHRRuntimeActionRootBorrowed(manager,&current.token);
        if(!status)status=ehr_runtime_object_same(current.token,completionOwner.token,&same);
        if(status||!same)return;
        if(completionFence){completionFence=false;fenceStatus.store(false);completionOwner.reset();completionFromNewUser=false;return;}
        if(!awaitingFull||!knownResult.load()||(lastEOS.load()!=0&&!(lastEOS.load()==3&&completionFromNewUser)))return;
        if(lastEOS.load()==3&&!newUserMigrationValidated.load())return;
        if(sameCurrentOwner(completionOwner.token)!=EHR_RUNTIME_OK){
            awaitingFull=false;awaitingStatus.store(false);completionOwner.reset();completionFromNewUser=false;forgetFullOwner();fullCompleted.store(false);localStatus.store(EHR_RUNTIME_NOT_READY);notify();return;
        }
        awaitingFull=false;awaitingStatus.store(false);fullCompleted.store(true);forgetFullOwner();
        lastFullOwnerWeak=api.gchandle_new_weakref(manager,false);
        memcpy(lastFullCredentialDigest,completionCredentialDigest,sizeof(lastFullCredentialDigest));lastFullCredentialKnown=lastFullOwnerWeak!=0;
        memset(completionCredentialDigest,0,sizeof(completionCredentialDigest));completionOwner.reset();completionFromNewUser=false;notify();
    }catch(...){localStatus.store(EHR_RUNTIME_LIMIT);}}@catch(__unused NSException *e){localStatus.store(EHR_RUNTIME_NOT_READY);}
}
extern "C" NSDictionary<NSString *,id> *EHRItchAuthCopyStatus(void){
    return @{@"preparedStatus":@(prepared.load()),@"enabled":@(enabled.load()),@"captured":@(hasCaptured.load()),@"pending":@(pending.load()),@"awaitingNewUserConfirmation":@(awaitingNewUser.load()),@"continuityAvailable":@(continuityAvailable.load()),@"originalCallbackDelivered":@(callbackDelivered.load()),@"continuedNewUser":@(continuedNewUser.load()),@"newUserMigrationValidated":@(newUserMigrationValidated.load()),@"newUserMigrationStatus":@(newUserMigrationStatus.load()),@"newUserMigrationChecks":@(newUserMigrationChecks.load()),@"newUserMigrationRejections":@(newUserMigrationRejections.load()),@"completionCount":@(completions.load()),@"localStatus":@(localStatus.load()),@"eosResult":@(lastEOS.load()),@"resultKnown":@(knownResult.load()),@"originalSuccessDelivered":@(successDelivered.load()),@"fullGameCompleted":@(fullCompleted.load()),@"awaitingFullCompletion":@(awaitingStatus.load()),@"staleCompletionFence":@(fenceStatus.load()),@"sdkLoginCalls":@(sdkCalls.load()),@"originalFailureCalls":@(failureCalls.load()),@"ignoredCallbacks":@(lateCallbacks.load()),@"cancelCount":@(cancelCount.load()),@"originalMarshalCalls":@(marshalCalls.load()),@"originalSuccessCalls":@(successCalls.load()),@"originalSilentFailureCalls":@(silentFailureCalls.load())};
}
extern "C" NSDictionary<NSString *,id> *EHRItchAuthSelfTest(void){
    int32_t status=EHR_RUNTIME_NOT_READY;size_t before=0,after=0;int32_t scalar=-1,factoryStatus=EHR_RUNTIME_NOT_READY;bool copied=false,managerAvailable=false,factoryPassed=false;
    if(mainThread()&&!prepared.load()){@try{try{
        status=ehr_runtime_object_root_count(&before);
        {Root managed,result;const ehr_itch::LoginInfo own{10,nullptr,nullptr,nullptr};
        if(!status)status=marshal(own,managed,false);if(!status)status=invoke(meta.resultGetter,managed.token,result);
        size_t bytes=0;if(!status)status=ehr_runtime_copy_value(result.token,&scalar,sizeof(scalar),&bytes);copied=!status&&bytes==sizeof(scalar)&&scalar==10;}
        {Context own;Root ownerPin;void *owner=nullptr;factoryStatus=existingManager(own.manager);managerAvailable=factoryStatus==EHR_RUNTIME_OK;
        if(managerAvailable){factoryStatus=makeSilentDelegate(own.manager.token,own.success);if(!factoryStatus)factoryStatus=pin(own.manager.token,ownerPin,&owner);if(!factoryStatus)factoryStatus=classifyCallback(own,owner);factoryPassed=!factoryStatus&&!own.normalFlow;}}
        const auto countStatus=ehr_runtime_object_root_count(&after);if(!status)status=countStatus;
    }catch(...){status=EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *e){status=EHR_RUNTIME_NOT_READY;}}
    return @{@"schema":@"ehr.itch-auth-marshal-proof.v1",@"success":@(!status&&copied&&before==after&&(!managerAvailable||factoryPassed)),@"status":@(status?status:managerAvailable&&!factoryPassed?factoryStatus:EHR_RUNTIME_OK),@"ownResultPreserved":@(copied),@"rootsBefore":@(before),@"rootsAfter":@(after),@"existingManagerAvailable":@(managerAvailable),@"originalSilentDelegateFactoryPassed":@(factoryPassed),@"delegateFactoryStatus":@(factoryStatus),@"realLoginInvoked":@NO,@"gameCallbackInvoked":@NO,@"credentialRead":@NO,@"accountCreation":@NO,@"accountLinking":@NO,@"gameOwnerConstructed":@NO};
}
