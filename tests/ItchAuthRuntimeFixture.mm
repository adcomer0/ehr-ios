// Own fixture. Compile with EHR_ITCH_RUNTIME_SOURCE naming the current adapter.
// All SDK/runtime objects, handles and callbacks below are owned sentinels.
#ifndef EHR_ITCH_RUNTIME_SOURCE
#error EHR_ITCH_RUNTIME_SOURCE must identify the source under test
#endif
#include EHR_ITCH_RUNTIME_SOURCE
#include <unordered_map>
#include <thread>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>

namespace fixture {
int managerClass,callbackClass,actionClass,internalClass,infoClass,parentClass,platformClass,connectClass,scalarClass,accountClass;
struct Object {const void *klass;alignas(8) uint8_t payload[64]{};};
Object manager{&managerClass},otherManager{&managerClass},success{&callbackClass},failure{&actionClass},platform{&platformClass},connect{&connectClass},exception{&scalarClass};
Object account{&accountClass};
Object *current=&manager;
std::vector<std::unique_ptr<Object>> objects;
std::unordered_map<uint64_t,Object*> roots;
std::unordered_map<uint32_t,Object*> weak;
uint32_t nextWeak=1;
uint64_t next=1000;
size_t checks=0,failures=0,helperCalls=0,writes=0,gameCalls=0,failCalls=0,sdkEntries=0;
bool marshalThrow=false,gameThrow=false,syncFinal=false,reenter=false,syncMigration=false,deviceIdPresent=false,changeDeviceOnCallback=false;
int sdkFault=0,marshalFault=0,successFault=0;
bool silent=false;
bool nativeTrying=true;
Object *storedSuccess=nullptr,*storedFailure=nullptr,*storedContinuance=nullptr;
Object continuation{&scalarClass},deviceString{&scalarClass};uintptr_t continuationPointer=0x2222;
size_t failureUI=0;
alignas(8) uint8_t dataClass[312]{};
int playerClass,playerAccountClass;
Object player{&playerClass},playerAccount{&playerAccountClass};
int32_t loginState=3;
uintptr_t listCount=1;
Object *delegateTarget=&manager;
int32_t reentryStatus=-1,lastMarshaledResult=-1;
uintptr_t cookie=0;ehr_itch::Callback savedCallback=nullptr;
void check(bool value,const char *name){++checks;if(!value){++failures;std::fprintf(stderr,"FAIL %s\n",name);}}
Object *make(const void *klass){auto p=std::make_unique<Object>();p->klass=klass;auto raw=p.get();objects.push_back(std::move(p));return raw;}
uint64_t root(Object *value){if(!value)return 0;const auto id=next++;roots.emplace(id,value);return id;}
Object *get(uint64_t token){auto it=roots.find(token);return it==roots.end()?nullptr:it->second;}
const void *klass(void *object){return static_cast<Object *>(object)->klass;}
void *unbox(void *object){return static_cast<Object *>(object)->payload;}
void *allocate(const void *type){return make(type);}
bool initialized(const void *){return true;}
uintptr_t length(void *){return listCount;}
int32_t stringLength(void *){return deviceIdPresent?12:0;}
uint32_t weakNew(void *object,bool){const auto id=nextWeak++;weak.emplace(id,static_cast<Object*>(object));return id;}
void *weakTarget(uint32_t id){auto it=weak.find(id);return it==weak.end()?nullptr:it->second;}
void weakFree(uint32_t id){weak.erase(id);}
void staticGet(void *field,void *out){*static_cast<void **>(out)=field==reinterpret_cast<void*>(2)?&account:field==reinterpret_cast<void*>(3)?&player:current;}
void fieldGet(void *,void *field,void *out){check(field==reinterpret_cast<void*>(4),"exact existing account reference field");*static_cast<void **>(out)=&playerAccount;}
void *runtimeInvoke(const void *method,void *receiver,void **args,void **raised){
    *raised=nullptr;
    if(method==reinterpret_cast<void*>(11)){
        auto *input=static_cast<ehr_itch::LoginInfo *>(receiver);
        check(input->clientData==nullptr,"own native ClientData never reaches managed decoder");
        if(marshalFault==1)throw std::runtime_error("owned marshal fault");
        if(marshalFault==2)@throw [NSException exceptionWithName:@"OwnMarshalFault" reason:nil userInfo:nil];
        if(marshalThrow){*raised=&exception;return nullptr;}
        std::memcpy(args[0],input,sizeof(*input));lastMarshaledResult=input->result;
    }else if(method==reinterpret_cast<void*>(12)){
        check(static_cast<Object *>(receiver)==&success,"captured original delegate used");
        auto *actual=static_cast<ehr_itch::LoginInfo *>(args[0]);
        check((actual->result==0&&actual->localUserId==reinterpret_cast<void*>(0x1111))||((silent||continuedNewUser.load())&&actual->result!=0&&actual->localUserId==nullptr),"genuine result and opaque user handle preserved");
        ++gameCalls;
        if(reenter)reentryStatus=EHRItchAuthCapture(&manager,&success,&failure);
        if(changeDeviceOnCallback)deviceIdPresent=true;
        const bool migrationOK=!syncMigration||EHRItchAuthCheckNewUserMigration(&manager)==0;
        if(syncFinal&&migrationOK)EHRItchAuthObserveFullCompletion(&manager);
        if(successFault==1)throw std::runtime_error("owned success fault");
        if(successFault==2)@throw [NSException exceptionWithName:@"OwnSuccessFault" reason:nil userInfo:nil];
        if(gameThrow)*raised=&exception;
    }else check(false,"unknown direct runtime method");
    return nullptr;
}
void login(void *handle,const ehr_itch::LoginOptions *options,void *clientData,ehr_itch::Callback callback){
    ++sdkEntries;check(handle==reinterpret_cast<void*>(0x1234),"existing platform handle used");
    check(options&&options->apiVersion==2&&options->credentials&&options->credentials->apiVersion==1,"exact SDK API versions");
    check(options->credentials->type==15&&options->userLoginInfo==nullptr,"real ItchioKey provider, no spoofed Apple profile");
    check(!std::strcmp(options->credentials->token,"owned-test-key"),"key supplied to SDK only during synchronous call");
    cookie=reinterpret_cast<uintptr_t>(clientData);savedCallback=callback;check(cookie!=0&&callback!=nullptr,"bounded opaque native request context");
    if(sdkFault==1)throw std::runtime_error("owned SDK entry fault");
    if(sdkFault==2)@throw [NSException exceptionWithName:@"OwnSDKFault" reason:nil userInfo:nil];
}
void reset(){
    request.reset();captured.reset();newUserCandidate.reset();completionOwner.reset();forgetFullOwner();check(roots.empty()&&weak.empty(),"all owned strong/weak roots returned to baseline");
    completionFence=false;awaitingFull=false;completionFromNewUser=false;completionGuardFailure=0;delivering=false;awaitingNewUser.store(false);continuityAvailable.store(false);callbackDelivered.store(false);continuedNewUser.store(false);newUserMigrationValidated.store(false);newUserMigrationStatus.store(1);newUserMigrationChecks.store(0);newUserMigrationRejections.store(0);resultHandler=nil;
    prepared.store(0);enabled.store(true);pending.store(false);hasCaptured.store(false);knownResult.store(false);successDelivered.store(false);fullCompleted.store(false);fenceStatus.store(false);awaitingStatus.store(false);
    localStatus.store(0);lastEOS.store(0);completions.store(0);sdkCalls.store(0);failureCalls.store(0);lateCallbacks.store(0);cancelCount.store(0);marshalCalls.store(0);successCalls.store(0);
    current=&manager;helperCalls=writes=gameCalls=failCalls=sdkEntries=0;marshalThrow=gameThrow=syncFinal=reenter=false;reentryStatus=-1;cookie=0;savedCallback=nullptr;
    sdkFault=marshalFault=successFault=0;syncMigration=changeDeviceOnCallback=deviceIdPresent=false;storedContinuance=nullptr;continuationPointer=0x2222;
    silent=false;listCount=1;delegateTarget=&manager;
    nativeTrying=true;storedSuccess=storedFailure=nullptr;failureUI=0;
    memset(dataClass,0,sizeof(dataClass));loginState=3;
    api.object_get_class=klass;api.object_new=allocate;api.object_unbox=unbox;api.class_is_inited=initialized;api.field_static_get_value=staticGet;api.runtime_invoke=runtimeInvoke;
    api.array_length=length;api.string_length=stringLength;api.gchandle_new_weakref=weakNew;api.gchandle_get_target=weakTarget;api.gchandle_free=weakFree;
    api.field_get_value=fieldGet;
    meta.managerClass=&managerClass;meta.callbackClass=&callbackClass;meta.actionClass=&actionClass;meta.internalClass=&internalClass;meta.infoClass=&infoClass;meta.parentClass=&parentClass;
    meta.instanceField=reinterpret_cast<void*>(1);meta.internal=4;meta.getPlatform=101;meta.getConnect=102;meta.getHandle=103;meta.initialize=104;meta.normalLogin=105;meta.actionInvoke=106;meta.resultGetter=107;meta.successField=201;meta.failureField=202;meta.marshalMethod=reinterpret_cast<void*>(11);meta.invokeMethod=reinterpret_cast<void*>(12);sdkLogin=login;
    meta.delegateMethod=108;meta.delegateTarget=109;meta.delegateList=110;meta.normalCallbackRVA=100;meta.silentCallbackRVA=200;
    meta.tryingField=203;meta.errorEnum=600;meta.signInFail=111;meta.accountClass=&accountClass;meta.accountParent=&parentClass;meta.accountInstanceField=reinterpret_cast<void*>(2);
    meta.continuanceField=204;meta.deviceProductUser=114;meta.delegateFactory=112;meta.silentMethod=200;meta.loginStatus=113;meta.dataManagerClass=dataClass;meta.playerClass=&playerClass;meta.playerAccountClass=&playerAccountClass;meta.playerStorage=reinterpret_cast<void*>(3);meta.playerAccountField=reinterpret_cast<void*>(4);
}
NSData *key(){return [@"owned-test-key" dataUsingEncoding:NSUTF8StringEncoding];}
void start(bool resultOnly=false){
    nativeTrying=true;
    const auto beforeWrites=writes,beforeHelpers=helperCalls,beforeSDK=sdkEntries;
    check(EHRItchAuthCapture(&manager,&success,&failure)==0,"capture original owner and delegates");
    check(writes==beforeWrites+2&&helperCalls==beforeHelpers+1&&hasCaptured.load(),"preserve original delegate stores and passive helper once");
    check(EHRItchAuthBegin(key(),resultOnly)==0,"begin real provider route");
    check(sdkEntries==beforeSDK+1&&pending.load()&&!hasCaptured.load(),"exactly one SDK call and pending ownership");
}
ehr_itch::LoginInfo result(int32_t code,uintptr_t id=0){return {code,reinterpret_cast<void*>(id?id:cookie),code==0?reinterpret_cast<void*>(0x1111):nullptr,code==3?reinterpret_cast<void*>(0x2222):nullptr};}
void run(){
    reset();start();receive(result(0));
    check(gameCalls==1&&failCalls==0&&marshalCalls.load()==1,"success marshaled and original delegate once");
    check(successDelivered.load()&&!fullCompleted.load()&&awaitingFull&&roots.size()==1,"callback return not fabricated full completion");
    check(EHRItchAuthCapture(&manager,&success,&failure)==8,"new attempt blocked while full completion pending");
    EHRItchAuthObserveFullCompletion(&otherManager);check(!fullCompleted.load(),"foreign completion rejected");
    EHRItchAuthObserveFullCompletion(&manager);check(fullCompleted.load()&&roots.empty(),"genuine same-owner endpoint releases root");
    EHRItchAuthObserveFullCompletion(&manager);check(roots.empty()&&gameCalls==1,"duplicate final endpoint harmless");
    receive(result(0));check(gameCalls==1&&lateCallbacks.load()==1,"duplicate SDK callback rejected");
    reset();syncFinal=true;start();receive(result(0));check(fullCompleted.load()&&successDelivered.load()&&roots.empty(),"nested genuine final endpoint is observed");
    silent=true;syncFinal=false;start();receive(result(0));check(fullCompleted.load()&&!awaitingFull&&successDelivered.load()&&roots.empty(),"same-owner same-key original silent renewal preserves actual prior full completion");
    check(EHRItchAuthCaptureSilent(&manager)==0,"early renewal uses original public delegate factory");check(EHRItchAuthBegin(key(),false)==0,"same successful credential renews through genuine SDK");receive(result(7000));check(gameCalls==3&&silentFailureCalls.load()==1&&!fullCompleted.load()&&!awaitingFull&&roots.empty(),"actual silent failure reaches original flags-only callback without full account/UI/create flow");
    reset();silent=true;check(EHRItchAuthCapture(&manager,&success,&failure)==0,"capture silent without prior proof");check(EHRItchAuthBegin(key(),false)==7&&sdkEntries==0,"silent callback cannot invent an initial full account login");EHRItchAuthCancel();
    reset();delegateTarget=&otherManager;check(EHRItchAuthCapture(&manager,&success,&failure)==5&&roots.empty()&&writes==0,"foreign delegate target rejected before field writes");
    reset();listCount=2;check(EHRItchAuthCapture(&manager,&success,&failure)==7&&roots.empty()&&writes==0,"multicast callback rejected before field writes");
    reset();reenter=true;start();receive(result(0));check(reentryStatus==8,"source callback cannot replace active delivery");EHRItchAuthObserveFullCompletion(&manager);
    for(int32_t code:{7000,5}){reset();start();receive(result(code));check(knownResult.load()&&lastEOS.load()==code&&gameCalls==0&&marshalCalls.load()==0,"failed result never reaches game success/create/link path");check(failCalls==1&&roots.empty(),"original failure cleanup once and roots released");receive(result(code));check(failCalls==1,"failed duplicate no cleanup retry");}
    reset();start();receive(result(3));check(newUserCandidate&&awaitingNewUser.load()&&continuityAvailable.load()&&gameCalls==0&&failCalls==0&&marshalCalls.load()==0&&!pending.load(),"genuine InvalidUser waits keyless for explicit human action");check(!callbackDelivered.load()&&!continuedNewUser.load()&&!successDelivered.load(),"candidate is not fabricated SDK or game success");check(EHRItchAuthConfirmNewUser()==0&&gameCalls==1&&lastMarshaledResult==3&&callbackDelivered.load()&&continuedNewUser.load()&&!successDelivered.load()&&!fullCompleted.load(),"explicit consent delivers exact genuine result3 once without changing EOS");check(EHRItchAuthConfirmNewUser()==1&&gameCalls==1,"confirmation cannot deliver twice");EHRItchAuthObserveFullCompletion(&manager);check(!fullCompleted.load()&&awaitingFull,"new-user completion cannot bypass real migration boundary");check(EHRItchAuthCheckNewUserMigration(&manager)==0,"genuine new-user no-migration boundary passes");EHRItchAuthObserveFullCompletion(&manager);check(fullCompleted.load()&&lastEOS.load()==3&&roots.empty(),"genuine final endpoint proves completion while EOS3 remains unchanged");
    reset();syncFinal=syncMigration=true;start();receive(result(3));check(EHRItchAuthConfirmNewUser()==0&&fullCompleted.load()&&newUserMigrationChecks.load()==1&&newUserMigrationStatus.load()==0&&roots.empty(),"original no-guest migration boundary and nested final preserve proof");
    reset();start();receive(result(3));deviceIdPresent=true;check(EHRItchAuthConfirmNewUser()==7&&gameCalls==0&&failCalls==1&&roots.empty(),"preexisting guest product identity blocks standalone creation before original callback");
    reset();syncFinal=syncMigration=changeDeviceOnCallback=true;start();receive(result(3));check(EHRItchAuthConfirmNewUser()==7&&!fullCompleted.load()&&newUserMigrationRejections.load()==1&&completionFence&&localStatus.load()==7,"late guest identity is rejected at real boundary without false final");check(EHRItchAuthCheckNewUserMigration(&manager)==1&&completionFence,"failed continuation cannot later bypass migration guard");EHRItchAuthObserveFullCompletion(&manager);check(!fullCompleted.load()&&!completionFence&&roots.empty(),"late final after migration rejection cannot authenticate");
    reset();start();receive(result(3));storedContinuance=&continuation;continuationPointer=0x3333;check(EHRItchAuthConfirmNewUser()==1&&gameCalls==0&&roots.empty(),"foreign preexisting continuance cannot substitute for actual SDK token");
    reset();start();receive(result(3));storedContinuance=&continuation;check(EHRItchAuthConfirmNewUser()==0&&gameCalls==1,"exact existing actual continuance identity is permitted");EHRItchAuthCancel();EHRItchAuthObserveFullCompletion(&manager);
    reset();start();receive(result(3));current=&otherManager;check(EHRItchAuthConfirmNewUser()==1&&gameCalls==0&&roots.empty(),"owner replacement invalidates confirmation before account effects");
    reset();start();receive(result(3));check(EHRItchAuthConfirmNewUser()==0,"enter real new-profile callback before delayed cancel");EHRItchAuthCancel();current=&otherManager;check(EHRItchAuthRequestPlatformLogin()==8&&completionFence&&completionFromNewUser,"new manager cannot retire a cancelled entered new-profile fence");check(EHRItchAuthCapture(&otherManager,&success,&failure)==8&&completionFence,"new capture remains bounded-not-ready while old native continuation exists");check(EHRItchAuthCheckNewUserMigration(&manager)==1&&completionFence&&newUserMigrationRejections.load()==1,"old manager late migration remains blocked after replacement");EHRItchAuthObserveFullCompletion(&manager);check(!fullCompleted.load()&&!completionFence&&roots.empty(),"only genuine old-owner final retires canceled new-profile fence without authenticating");
    reset();start();auto missing=result(3);missing.continuanceToken=nullptr;receive(missing);check(!newUserCandidate&&failCalls==1&&gameCalls==0&&roots.empty(),"InvalidUser without real continuance cannot offer creation");
    reset();start();receive(result(3));const auto expiryCookie=cookie;expireNewUserCandidate(expiryCookie+1);check(newUserCandidate&&gameCalls==0,"foreign or stale deadline cannot cancel current confirmation");expireNewUserCandidate(expiryCookie);check(!newUserCandidate&&gameCalls==0&&failCalls==1&&roots.empty(),"receipt-anchored candidate timeout cancels once without account callback");
    reset();start();receive(result(3));int32_t confirmationWorker=-1;std::thread confirmThread([&]{confirmationWorker=EHRItchAuthConfirmNewUser();});confirmThread.join();check(confirmationWorker==2&&newUserCandidate&&gameCalls==0,"worker cannot confirm a pending profile");EHRItchAuthCancel();
    for(int fault:{1,2}){reset();start();receive(result(3));marshalFault=fault;check(EHRItchAuthConfirmNewUser()!=0&&!newUserCandidate&&!delivering&&failCalls==1&&gameCalls==0&&roots.empty(),"confirmation marshal exception cleans all retained request roots once");reset();start();receive(result(3));successFault=fault;check(EHRItchAuthConfirmNewUser()!=0&&gameCalls==1&&failCalls==1&&completionFence&&!fullCompleted.load(),"confirmation original callback exception is once-only and fenced");EHRItchAuthObserveFullCompletion(&manager);check(roots.empty()&&!fullCompleted.load(),"late confirmation final after exception cannot authenticate");}
    reset();start();receive(result(3));check(EHRItchAuthCancel()==0&&!newUserCandidate&&!awaitingNewUser.load()&&gameCalls==0&&roots.empty(),"cancel destroys retained candidate and never invokes original account callback");
    reset();start();receive(result(3));check(EHRItchAuthSetEnabled(0)==0&&!newUserCandidate&&roots.empty(),"disable invalidates unconfirmed candidate");
    reset();start();receive(result(3));check(EHRItchAuthBegin(key(),false)==1&&!newUserCandidate&&sdkEntries==1&&roots.empty(),"new Begin invalidates old pending confirmation without replaying request");
    reset();start(true);receive(result(3));check(!newUserCandidate&&gameCalls==0&&failCalls==1&&roots.empty(),"result-only InvalidUser never offers new-profile creation");
    reset();start(true);receive(result(0));check(gameCalls==0&&failCalls==1&&!fullCompleted.load()&&roots.empty(),"result-only probe never changes game account state");
    reset();check(EHRItchAuthCapture(&manager,&success,&failure)==0,"capture for cancel");check(EHRItchAuthCancel()==0&&failCalls==1&&roots.empty(),"pre-login cancel cleanup once");EHRItchAuthCancel();check(failCalls==1,"repeated cancel no duplicate failure");
    reset();start();const auto oldCookie=cookie;EHRItchAuthCancel();check(failCalls==1&&request&&request->cancelled&&roots.size()==2,"inflight cancellation retains only callback-lifetime handles");check(EHRItchAuthCapture(&manager,&success,&failure)==8,"pending native callback prevents overlap");receive(result(0));check(gameCalls==0&&roots.empty(),"late cancelled success cannot log in");start();const auto newCookie=cookie;receive(result(0,oldCookie));check(pending.load()&&request&&request->cookie==newCookie&&gameCalls==0,"stale cookie cannot complete new attempt");receive(result(7000));
    reset();marshalThrow=true;start();receive(result(0));check(gameCalls==0&&failCalls==1&&localStatus.load()==6&&roots.empty(),"original SDK marshal exception contained and cleaned up");
    reset();gameThrow=true;start();receive(result(0));check(gameCalls==1&&failCalls==1&&localStatus.load()==6&&completionFence&&!fullCompleted.load(),"partial original success exception never retried or falsely completed");check(EHRItchAuthCapture(&manager,&success,&failure)==8,"partial source failure fenced");EHRItchAuthObserveFullCompletion(&manager);check(!fullCompleted.load()&&!completionFence&&roots.empty(),"late old final clears fence without authenticating");
    reset();syncFinal=true;gameThrow=true;start();receive(result(0));check(!fullCompleted.load()&&!completionFence&&failCalls==1&&roots.empty(),"final followed by callback exception is not false completion or orphan fence");check(!lastFullOwnerWeak&&!lastFullCredentialKnown&&EHRItchAuthCaptureSilent(&manager)==1,"failed post-final callback cannot retain prior-full silent-renewal proof");
    for(int fault:{1,2}){
        reset();sdkFault=fault;check(EHRItchAuthCapture(&manager,&success,&failure)==0,"capture for throwing SDK");const auto code=EHRItchAuthBegin(key(),false);check(code!=0&&sdkEntries==1&&request&&request->cancelled&&failCalls==1&&roots.size()==2,"SDK C++/ObjC fault runs ordinary failure cleanup once");EHRItchAuthCancel();check(failCalls==1,"throwing SDK cancel does not retry failure");receive(result(0));check(roots.empty()&&gameCalls==0,"late throwing-SDK callback releases bounded lifetime roots without success");
        reset();marshalFault=fault;start();bool caught=false;@try{try{receive(result(0));}catch(...){caught=true;}}@catch(__unused NSException *e){caught=true;}check(caught&&failCalls==1&&!pending.load()&&!delivering&&roots.empty(),"unexpected SDK marshal unwind cleans failure and every root");
        reset();successFault=fault;start();caught=false;@try{try{receive(result(0));}catch(...){caught=true;}}@catch(__unused NSException *e){caught=true;}check(caught&&gameCalls==1&&failCalls==1&&!pending.load()&&completionFence&&!fullCompleted.load(),"unexpected original success unwind cleans once and fences stale final");EHRItchAuthObserveFullCompletion(&manager);check(roots.empty()&&!fullCompleted.load(),"unexpected success fault final never authenticates");
    }
    reset();start();receive(result(0));EHRItchAuthCancel();check(completionFence&&!fullCompleted.load(),"cancel awaiting final fences late completion");check(EHRItchAuthCapture(&manager,&success,&failure)==8,"same-owner new attempt blocked under stale fence");EHRItchAuthObserveFullCompletion(&manager);check(!fullCompleted.load()&&roots.empty(),"cancelled final is ignored");
    reset();start();current=&otherManager;receive(result(0));check(gameCalls==0&&failCalls==1&&roots.empty(),"owner replacement rejects true result delivery");
    reset();check(EHRItchAuthCapture(&manager,&success,&failure)==0,"capture before input validation");for(NSData *bad in @[[NSData data],[@"bad key" dataUsingEncoding:NSUTF8StringEncoding],[@"a\nb" dataUsingEncoding:NSUTF8StringEncoding]])check(EHRItchAuthBegin(bad,false)==4&&sdkEntries==0,"invalid input creates no SDK request");EHRItchAuthCancel();
    reset();start();check(EHRItchAuthSetEnabled(0)==0&&!enabled.load(),"disable cancels before native callback");receive(result(0));check(gameCalls==0&&failCalls==1&&roots.empty(),"disabled late callback cannot deliver success");
    reset();check(EHRItchAuthCapture(&manager,&success,nullptr)==0,"normal native nil failure Action supported");check(EHRItchAuthBegin(key(),false)==0,"nil Action first request");receive(result(7000));check(failureUI==1&&failCalls==0&&captured&&roots.size()==2&&nativeTrying,"reject retains only keyless exact native acquisition, no flags reset");check(EHRItchAuthRequestPlatformLogin()==0&&captured,"retry resumes existing approved acquisition despite native outer latch");check(EHRItchAuthBegin(key(),false)==0,"user retry can issue a second legitimate request");receive(result(0));EHRItchAuthObserveFullCompletion(&manager);check(gameCalls==1&&fullCompleted.load()&&roots.empty(),"rejected-key retry can genuinely finish normal account flow");
    reset();check(EHRItchAuthCapture(&manager,&success,nullptr)==0,"nil cancel capture");check(EHRItchAuthCancel()==0&&captured&&nativeTrying&&roots.size()==2,"cancel retains no key, only guarded resumption roots");check(EHRItchAuthRequestPlatformLogin()==0&&EHRItchAuthBegin(key(),false)==0,"cancelled acquisition can be resumed without changing native latch");receive(result(7000));check(failureUI==2,"native error UI at most once per real attempt");check(EHRItchAuthSetEnabled(0)==0&&roots.empty(),"terminal disable releases resumable keyless roots");
    reset();check(EHRItchAuthCapture(&manager,&success,nullptr)==0,"resumption binding capture");EHRItchAuthCancel();storedSuccess=&failure;check(EHRItchAuthBegin(key(),false)==1&&sdkEntries==0,"changed original callback fields cannot resume an old acquisition");EHRItchAuthSetEnabled(0);
    reset();bool guest=true;check(EHRItchAuthIsGuestSilentPath(&manager,&guest)==1&&!guest,"unknown cctor completion never initializes or reads account data");*reinterpret_cast<uint32_t*>(dataClass+224)=1;check(EHRItchAuthIsGuestSilentPath(&manager,&guest)==0&&guest,"only existing initialized TempAccount is native guest path");loginState=1;check(EHRItchAuthIsGuestSilentPath(&manager,&guest)==0&&!guest,"existing full account cannot fall back to Apple under guest policy");loginState=19;check(EHRItchAuthIsGuestSilentPath(&manager,&guest)==7&&!guest,"unknown account state fails closed");
    reset();int32_t worker=-1;std::thread t([&]{worker=EHRItchAuthCapture(&manager,&success,&failure);});t.join();check(worker==2&&roots.empty(),"worker entry rejected before gateway access");std::thread p([&]{worker=EHRItchAuthPrepare();});p.join();check(worker==2&&prepared.load()==0,"worker Prepare cannot revoke prepared metadata");
    reset();start();auto actual=result(7000);std::thread cb([&]{savedCallback(&actual);});cb.join();const auto deadline=[NSDate dateWithTimeIntervalSinceNow:0.5];while(pending.load()&&deadline.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];check(!pending.load()&&lastEOS.load()==7000&&failCalls==1&&roots.empty(),"real adapter callback queues worker payload to main before touching roots");
    NSDictionary *snapshot=EHRItchAuthCopyStatus();check(![[snapshot description] containsString:@"owned-test-key"],"status contains no credential");check([snapshot[@"fullGameCompleted"] boolValue]==NO,"status not fake successful");
    reset();check(EHRItchAuthSelfTest()[@"success"]!=nil,"owned marshal selftest returns structured result");reset();
}
}

EHRRuntimeStatus EHRRuntimeActionRootBorrowed(void *object,EHRRuntimeToken *out){*out=fixture::root(static_cast<fixture::Object*>(object));return EHR_RUNTIME_OK;}
EHRRuntimeStatus EHRRuntimeIteratorPin(EHRRuntimeToken token,EHRRuntimeToken *out,void **identity){auto value=fixture::get(token);if(!value)return EHR_RUNTIME_INVALID_TOKEN;*out=fixture::root(value);*identity=value;return EHR_RUNTIME_OK;}
EHRRuntimeStatus EHRRuntimeBorrowClass(EHRRuntimeToken,const void **){return EHR_RUNTIME_UNSUPPORTED;}
EHRRuntimeStatus EHRRuntimeBorrowMethod(EHRRuntimeToken token,const void **method,const void **owner){if(token!=100&&token!=200)return EHR_RUNTIME_UNSUPPORTED;*method=reinterpret_cast<void*>(token);*owner=&fixture::managerClass;return EHR_RUNTIME_OK;}
namespace ehr_pinned {EHRRuntimeStatus validate_engine_entry(const void *){return EHR_RUNTIME_OK;}}
extern "C" EHRRuntimeStatus ehr_runtime_object_release(EHRRuntimeToken token){return fixture::roots.erase(token)?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;}
extern "C" EHRRuntimeStatus ehr_runtime_object_retain(EHRRuntimeToken token,EHRRuntimeToken *out){auto object=fixture::get(token);if(!object)return EHR_RUNTIME_INVALID_TOKEN;*out=fixture::root(object);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_same(EHRRuntimeToken a,EHRRuntimeToken b,int32_t *same){*same=fixture::get(a)==fixture::get(b);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_root_count(size_t *out){*out=fixture::roots.size();return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_method_from_object(EHRRuntimeToken token,EHRRuntimeToken *method){auto box=fixture::get(token);if(!box)return EHR_RUNTIME_INVALID_TOKEN;memcpy(method,box->payload,8);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_class_type_object(EHRRuntimeToken,EHRRuntimeToken *out){*out=fixture::root(fixture::make(&fixture::scalarClass));return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_method_object(EHRRuntimeToken method,EHRRuntimeToken *out){auto box=fixture::make(&fixture::scalarClass);memcpy(box->payload,&method,8);*out=fixture::root(box);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_validate_native_method(EHRRuntimeToken method,uint64_t expected,uint64_t *observed){*observed=method;return method==expected?EHR_RUNTIME_OK:EHR_RUNTIME_TYPE_MISMATCH;}
extern "C" EHRRuntimeStatus ehr_runtime_write_field(EHRRuntimeToken field,EHRRuntimeToken owner,const EHRRuntimeArgument *arg){fixture::check(fixture::get(owner)==&fixture::manager,"barrier receiver is captured manager");auto value=fixture::get(arg->token);fixture::check(arg->kind==EHR_RUNTIME_REFERENCE&&(field==201?value==&fixture::success:!value||value==&fixture::failure),"original callback reference preserved");if(field==201)fixture::storedSuccess=value;else fixture::storedFailure=value;++fixture::writes;return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_read_field(EHRRuntimeToken field,EHRRuntimeToken,EHRRuntimeToken *out){if(field==201)*out=fixture::root(fixture::storedSuccess);else if(field==202)*out=fixture::root(fixture::storedFailure);else if(field==204)*out=fixture::root(fixture::storedContinuance);else if(field==203){auto box=fixture::make(&fixture::scalarClass);box->payload[0]=fixture::nativeTrying?1:0;*out=fixture::root(box);}else return EHR_RUNTIME_UNSUPPORTED;return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_invoke(EHRRuntimeToken method,EHRRuntimeToken owner,const EHRRuntimeArgument *arguments,size_t count,EHRRuntimeToken *out,EHRRuntimeToken *raised){
    *out=0;*raised=0;using namespace fixture;
    if(method==101)*out=root(&platform);else if(method==102)*out=root(&connect);else if(method==103){auto box=make(&scalarClass);const uintptr_t v=get(owner)==&continuation?continuationPointer:0x1234;memcpy(box->payload,&v,8);*out=root(box);}else if(method==104)++helperCalls;else if(method==106){check(get(owner)==&failure,"original failure Action used");++failCalls;nativeTrying=false;}else if(method==107){auto box=make(&scalarClass);memcpy(box->payload,get(owner)->payload,4);*out=root(box);}else if(method==108){auto box=make(&scalarClass);const uint64_t value=silent?200:100;memcpy(box->payload,&value,8);*out=root(box);}else if(method==109)*out=root(delegateTarget);else if(method==110)*out=root(make(&scalarClass));else if(method==111){check(get(owner)==&account&&count==2&&arguments[0].kind==EHR_RUNTIME_VALUE&&arguments[0].token==600&&*static_cast<const int32_t*>(arguments[0].bytes)==22&&arguments[1].token==0,"UI-only original Itch failure path receives no fake EOS result/account action");++failureUI;}else if(method==112){check(count==3&&arguments[0].kind==EHR_RUNTIME_REFERENCE&&get(arguments[1].token)==&manager,"public AOT delegate factory bound to existing owner");silent=true;delegateTarget=&manager;*out=root(&success);}else if(method==113){auto box=make(&scalarClass);memcpy(box->payload,&loginState,4);*out=root(box);}else if(method==114){if(deviceIdPresent)*out=root(&deviceString);}else return EHR_RUNTIME_UNSUPPORTED;return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_box(EHRRuntimeToken,const void *bytes,size_t count,EHRRuntimeToken *out){auto box=fixture::make(&fixture::internalClass);memcpy(box->payload,bytes,count);*out=fixture::root(box);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_copy_value(EHRRuntimeToken token,void *bytes,size_t capacity,size_t *out){auto box=fixture::get(token);if(!box)return EHR_RUNTIME_INVALID_TOKEN;memcpy(bytes,box->payload,capacity);*out=capacity;return EHR_RUNTIME_OK;}
int main(){@autoreleasepool{fixture::run();std::printf("{\"schema\":\"ehr.itch-auth-owned-fixture.v1\",\"checks\":%zu,\"failures\":%zu,\"actualSDKRequests\":0,\"accountOperations\":0}\n",fixture::checks,fixture::failures);return fixture::failures?1:0;}}
