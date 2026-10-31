#import "EHRItchAuthProvider.h"
#import "EHRItchAuthRuntime.h"
#import "EHRItchSignInUI.h"
#import "EHRItchOwnership.h"
#import <UIKit/UIKit.h>
#include "EHRItchAuthBinding.generated.h"
#include "EHRNativeHooks.h"
#include "EHRRuntimeGateway.h"
#include "EHRRuntimeIteratorPrivate.h"
#include <atomic>
#include <cstring>
#include <cmath>

namespace {
struct State {
    __weak UIViewController *presenter=nil;
    NSMutableData *attemptKey=nil, *sessionKey=nil, *proofKey=nil;
    EHRItchOwnershipCheck *ownershipCheck=nil;
    NSLock *ownershipResponseLock=[NSLock new];
    NSDictionary<NSString *,NSNumber *> *ownershipResponse=@{};
    uint64_t ownershipGeneration=0, proofEpoch=0, authGeneration=0;
    std::atomic<int32_t> ownershipStatus{EHRItchOwnershipCancelled}, ownershipHTTPStatus{0};
    std::atomic<bool> ownershipVerified{false}, ownershipPending{false};
    std::atomic<uint64_t> ownershipChecks{0};
    bool initialCredentialChecked=false,savedBootstrapAttempt=false;
    std::atomic<bool> awaitingNativeLogin{false};
    std::atomic<double> nativeLoginDeadline{0};
    uint64_t nativeLoginEpoch=0,nativeLoginGeneration=0;
    __weak NSData *nativeLoginKey=nil;
    NSTimer *timer=nil;
    bool started=false, promptRequested=false, presenting=false, savedKeyAllowed=true;
    std::atomic<bool> clearedForRestart{false};
    std::atomic<uint64_t> credentialEpoch{0}, credentialClears{0};
    std::atomic<int32_t> prepared{EHR_RUNTIME_NOT_READY}, lastStatus{EHR_RUNTIME_NOT_READY};
    std::atomic<uint64_t> captures{0}, prompts{0}, submissions{0}, renewalAttempts{0}, faults{0};
};
State &state(){static State value;return value;}
void wipeBytes(void *buffer,size_t size){
    volatile uint8_t *bytes=static_cast<volatile uint8_t *>(buffer);
    for(size_t i=0;i<size;++i)bytes[i]=0;
}
void wipe(NSMutableData *__strong &data){
    if(data.length)wipeBytes(data.mutableBytes,data.length);
    data=nil;
}
bool selected(){
    NSDictionary *info=NSBundle.mainBundle.infoDictionary;
    id provider=info[@"EHRAuthProvider"];
    return [info[@"EHRItchAuthCompiled"] boolValue]&&[provider isKindOfClass:NSString.class]&&[provider isEqualToString:@"itchio"];
}
void pump();
NSDictionary *numericFields(NSDictionary *input,NSArray<NSString *> *keys){
    NSMutableDictionary *filtered=[NSMutableDictionary new];
    if(![input isKindOfClass:NSDictionary.class])return filtered;
    for(NSString *key in keys){id value=input[key];if([value isKindOfClass:NSNumber.class])filtered[key]=value;}
    return filtered;
}
NSArray<NSString *> *ownershipDiagnosticKeys(){return @[@"schemaVersion",@"parserStage",@"requestedPage",@"responseBytes",@"totalBytes",@"httpTyped",@"urlMatched",@"mimeJSON",@"lengthOK",@"rootKind",@"ownedKeysKind",@"ownedKeysCount",@"pageKind",@"returnedPage",@"perPageKind",@"returnedPerPage"];}
void setOwnershipResponse(NSDictionary *response){
    auto &s=state();NSDictionary *filtered=numericFields(response,ownershipDiagnosticKeys());
    [s.ownershipResponseLock lock];s.ownershipResponse=[filtered copy];[s.ownershipResponseLock unlock];
}
NSDictionary *ownershipResponseSnapshot(){auto &s=state();[s.ownershipResponseLock lock];NSDictionary *snapshot=s.ownershipResponse;[s.ownershipResponseLock unlock];return snapshot?:@{};}
void writeStatus(){
    if(![NSBundle.mainBundle.infoDictionary[@"EHRItchAuthDiagnosticsCacheEnabled"] boolValue])return;
    // CopyStatus is constructed exclusively from fixed numeric counters. Never
    // serialize inputs, callback payloads, objects, keys or exception text.
    @try {
        NSDictionary *raw=EHRItchAuthProviderCopyStatus();
        NSMutableDictionary *snapshot=[numericFields(raw,@[@"schemaVersion",@"selected",@"preparedStatus",@"lastStatus",@"captures",@"prompts",@"submissions",@"renewalAttempts",@"faults",@"clearedForRestart",@"credentialEpoch",@"credentialClears",@"ownershipStatus",@"ownershipHTTPStatus",@"ownershipVerified",@"ownershipPending",@"ownershipChecks",@"directoryAllowed",@"awaitingNativeLogin",@"nativeLoginWaitSeconds"]) mutableCopy];
        snapshot[@"runtime"]=numericFields(raw[@"runtime"],@[@"preparedStatus",@"enabled",@"captured",@"pending",@"completionCount",@"localStatus",@"eosResult",@"resultKnown",@"originalSuccessDelivered",@"fullGameCompleted",@"awaitingFullCompletion",@"staleCompletionFence",@"sdkLoginCalls",@"originalFailureCalls",@"ignoredCallbacks",@"cancelCount",@"originalMarshalCalls",@"originalSuccessCalls",@"awaitingNewUserConfirmation",@"continuityAvailable",@"originalCallbackDelivered",@"continuedNewUser",@"newUserMigrationStatus",@"newUserMigrationChecks",@"newUserMigrationRejections",@"newUserMigrationValidated"]);
        snapshot[@"ownershipResponse"]=numericFields(raw[@"ownershipResponse"],ownershipDiagnosticKeys());
        snapshot[@"interface"]=numericFields(raw[@"interface"],@[@"schemaVersion",@"presented",@"submissions",@"cancelled",@"oauthStarted",@"oauthFailures",@"saved",@"saveFailures",@"forgotten",@"rejected",@"visible",@"busy",@"oauthConfigured",@"localStatus",@"eosResult",@"fullGameCompleted",@"resultKnown",@"awaitingNewProfileConfirmation",@"newProfileConfirmed",@"ownershipStatus",@"ownershipHTTPStatus",@"ownershipPending",@"ownershipVerified"]);
        NSData *data=[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
        if(!data||data.length>16384)return;
        NSURL *cache=[NSFileManager.defaultManager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
        if(cache)[data writeToURL:[cache URLByAppendingPathComponent:@"EHRItchSignInStatus.json"] options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
    } @catch (__unused NSException *exception) {}
}
bool proofCurrent(){
    auto &s=state();return selected()&&!s.clearedForRestart.load()&&!s.ownershipPending.load()&&s.ownershipVerified.load()&&
        s.proofKey.length&&s.proofEpoch==s.credentialEpoch.load();
}
bool proofForAttempt(){auto &s=state();return proofCurrent()&&s.attemptKey.length&&[s.proofKey isEqualToData:s.attemptKey];}
constexpr NSTimeInterval nativeLoginWaitLimit=120;
void clearNativeLoginWait(){
    auto &s=state();s.awaitingNativeLogin.store(false);s.nativeLoginDeadline.store(0);
    s.nativeLoginEpoch=0;s.nativeLoginGeneration=0;s.nativeLoginKey=nil;
}
void retireDeferredAttempt(){
    auto &s=state();clearNativeLoginWait();s.savedBootstrapAttempt=false;s.authGeneration=0;
    wipe(s.attemptKey);s.savedKeyAllowed=false;
}
void refreshNativeLoginWait(){
    auto &s=state();if(!NSThread.isMainThread||!s.awaitingNativeLogin.load())return;
    if(NSProcessInfo.processInfo.systemUptime>=s.nativeLoginDeadline.load()||
       s.nativeLoginEpoch!=s.credentialEpoch.load()||s.nativeLoginGeneration!=s.ownershipGeneration||
       s.nativeLoginKey!=s.attemptKey||!proofForAttempt()){retireDeferredAttempt();writeStatus();}
}
int32_t nativeLoginWaitSeconds(){
    auto &s=state();if(!s.awaitingNativeLogin.load())return 0;
    const double remaining=s.nativeLoginDeadline.load()-NSProcessInfo.processInfo.systemUptime;
    return (int32_t)MAX(0.0,MIN(nativeLoginWaitLimit,std::ceil(remaining)));
}
bool authIdle(NSDictionary *runtime){
    return ![runtime[@"captured"] boolValue]&&![runtime[@"pending"] boolValue]&&
        ![runtime[@"awaitingFullCompletion"] boolValue]&&![runtime[@"awaitingNewUserConfirmation"] boolValue]&&
        ![runtime[@"fullGameCompleted"] boolValue]&&![runtime[@"resultKnown"] boolValue];
}
bool noSignInForm(){
    NSDictionary *ui=EHRItchSignInCopyStatus();return !state().presenting&&![ui[@"visible"] boolValue]&&![ui[@"busy"] boolValue];
}
void retireOwnership(){
    auto &s=state();clearNativeLoginWait();s.savedBootstrapAttempt=false;++s.ownershipGeneration;s.authGeneration=0;s.ownershipPending.store(false);s.ownershipVerified.store(false);
    s.ownershipStatus.store(EHRItchOwnershipCancelled);s.ownershipHTTPStatus.store(0);wipe(s.proofKey);setOwnershipResponse(@{});
    EHRItchOwnershipCheck *check=s.ownershipCheck;s.ownershipCheck=nil;[check cancel];
}
void beginAuth(){
    auto &s=state();if(!NSThread.isMainThread||!proofForAttempt()||s.authGeneration==s.ownershipGeneration)return;
    clearNativeLoginWait();s.savedBootstrapAttempt=false;s.authGeneration=s.ownershipGeneration;
    const int32_t status=EHRItchAuthBegin(s.attemptKey,false);s.lastStatus.store(status);
    if(status){
        s.authGeneration=0;wipe(s.attemptKey);s.savedKeyAllowed=false;
        EHRItchSignInUpdateResult(status,-1,false);EHRItchAuthCancel();
    }
}
void continueVerifiedAttempt(){
    auto &s=state();refreshNativeLoginWait();if(!proofForAttempt())return;
    NSDictionary *runtime=EHRItchAuthCopyStatus();
    if([runtime[@"captured"] boolValue]&&![runtime[@"pending"] boolValue]){beginAuth();return;}
    const auto epoch=s.credentialEpoch.load(),generation=s.ownershipGeneration,captureSerial=s.captures.load();
    const auto sdkCalls=[runtime[@"sdkLoginCalls"] unsignedLongLongValue],completions=[runtime[@"completionCount"] unsignedLongLongValue];
    NSData *checkedKey=s.attemptKey;
    const bool mayDefer=s.savedBootstrapAttempt&&s.savedKeyAllowed&&s.authGeneration==0&&authIdle(runtime)&&noSignInForm();
    // Ownership is established before entering any game-owned login checks.
    // Reentry captures the game's original success and failure delegates.
    const auto code=EHRItchAuthRequestPlatformLogin();s.lastStatus.store(code);
    if(code){
        if(s.credentialEpoch.load()!=epoch||s.ownershipGeneration!=generation||s.attemptKey!=checkedKey){writeStatus();return;}
        NSDictionary *after=EHRItchAuthCopyStatus();
        if(mayDefer&&s.savedBootstrapAttempt&&s.savedKeyAllowed&&proofForAttempt()&&s.authGeneration==0&&
           s.credentialEpoch.load()==epoch&&s.ownershipGeneration==generation&&s.attemptKey==checkedKey&&
           s.captures.load()==captureSerial&&[after[@"sdkLoginCalls"] unsignedLongLongValue]==sdkCalls&&
           [after[@"completionCount"] unsignedLongLongValue]==completions&&authIdle(after)&&noSignInForm()){
            if(!s.awaitingNativeLogin.load()){
                s.nativeLoginEpoch=epoch;s.nativeLoginGeneration=generation;s.nativeLoginKey=s.attemptKey;
                s.nativeLoginDeadline.store(NSProcessInfo.processInfo.systemUptime+nativeLoginWaitLimit);s.awaitingNativeLogin.store(true);
            }
            // Only an entered normal acquisition or an explicit Account action
            // may advance this attempt. The timer never invokes game login.
            writeStatus();return;
        }
        clearNativeLoginWait();s.savedBootstrapAttempt=false;s.authGeneration=0;wipe(s.attemptKey);s.savedKeyAllowed=false;EHRItchSignInUpdateResult(code,-1,false);
    }
}
void beginAttempt(NSData *key,bool savedBootstrap=false){
    auto &s=state();if(!NSThread.isMainThread||s.clearedForRestart.load()||!key)return;
    retireOwnership();s.savedBootstrapAttempt=savedBootstrap;const uint64_t generation=s.ownershipGeneration,epoch=s.credentialEpoch.load();
    __weak NSData *checkedKey=key;
    s.ownershipPending.store(true);++s.ownershipChecks;
    EHRItchSignInUpdateOwnership(EHRItchOwnershipCancelled,0,true);
    s.ownershipCheck=EHRItchOwnershipBegin(key,^(EHRItchOwnershipStatus status,int32_t http){
        auto &current=state();
        if(current.clearedForRestart.load()||current.credentialEpoch.load()!=epoch||current.ownershipGeneration!=generation||!current.ownershipPending.load()||current.attemptKey!=checkedKey)return;
        // Read only the still-current check after the credential/epoch fence.
        // Its body/key are already wiped; only fixed numeric structure remains.
        setOwnershipResponse(EHRItchOwnershipCopyDiagnostics(current.ownershipCheck));
        current.ownershipCheck=nil;current.ownershipPending.store(false);current.ownershipStatus.store(status);current.ownershipHTTPStatus.store(http);
        if(status==EHRItchOwnershipVerified&&current.attemptKey.length){
            current.proofKey=[current.attemptKey mutableCopy];current.proofEpoch=epoch;current.ownershipVerified.store(true);
            EHRItchSignInUpdateOwnership(status,http,false);continueVerifiedAttempt();
        }else{
            current.ownershipVerified.store(false);current.savedKeyAllowed=false;current.authGeneration=0;
            wipe(current.attemptKey);wipe(current.sessionKey);
            EHRItchSignInUpdateOwnership(status,http,false);EHRItchAuthCancel();
            // An automatic remembered-key check may fail before a form exists.
            current.promptRequested=true;pump();
        }
        writeStatus();
    });
    writeStatus();
}
void initialCredential(){
    auto &s=state();if(!NSThread.isMainThread||s.initialCredentialChecked||s.clearedForRestart.load()||s.prepared.load()!=EHR_RUNTIME_OK)return;
    s.initialCredentialChecked=true;if(s.attemptKey.length||s.sessionKey.length)return;
    NSMutableData *saved=s.savedKeyAllowed?EHRItchSignInCopySavedKey():nil;
    if(saved.length){s.attemptKey=[saved mutableCopy];wipeBytes(saved.mutableBytes,saved.length);beginAttempt(s.attemptKey,true);}
    else{s.promptRequested=true;pump();}
}
void submit(NSData *key){
    auto &s=state();if(!NSThread.isMainThread||s.clearedForRestart.load())return;
    ++s.credentialEpoch;retireOwnership();
    if(!key){
        s.promptRequested=false;s.presenting=false;s.savedKeyAllowed=false;
        wipe(s.attemptKey);wipe(s.sessionKey);EHRItchAuthCancel();writeStatus();return;
    }
    NSDictionary *runtime=EHRItchAuthCopyStatus();
    if([runtime[@"pending"] boolValue]||[runtime[@"awaitingFullCompletion"] boolValue]||[runtime[@"awaitingNewUserConfirmation"] boolValue])EHRItchAuthCancel();
    ++s.submissions;wipe(s.attemptKey);wipe(s.sessionKey);
    if(!key.length||key.length>8192){
        s.ownershipStatus.store(EHRItchOwnershipBadCredentialFormat);s.savedKeyAllowed=false;
        EHRItchSignInUpdateOwnership(EHRItchOwnershipBadCredentialFormat,0,false);EHRItchAuthCancel();writeStatus();return;
    }
    s.attemptKey=[key mutableCopy];beginAttempt(s.attemptKey);
}
void pump(){
    if(!NSThread.isMainThread)return;
    auto &s=state();refreshNativeLoginWait();UIViewController *presenter=s.presenter;
    if(!s.clearedForRestart.load()&&selected()&&presenter&&presenter.view.window){
        // The overlay may arrive before metadata preparation. Retrying here
        // keeps Start passive and only bootstraps credentials with visible UI.
        if(s.prepared.load()!=EHR_RUNTIME_OK)(void)EHRItchAuthProviderStart();
        initialCredential();
    }
    if(s.clearedForRestart.load()||!s.promptRequested||s.presenting||!presenter||!presenter.view.window||presenter.presentedViewController)return;
    s.promptRequested=false;s.presenting=true;++s.prompts;
    EHRItchSignInPresent(presenter,^(NSData *key){submit(key);});
}
void result(int32_t local,int32_t eos,bool known,bool delivered){
    auto &s=state();NSDictionary *runtime=EHRItchAuthCopyStatus();
    if(s.clearedForRestart.load()){writeStatus();return;}
    const bool ownedAttempt=proofForAttempt()&&s.authGeneration==s.ownershipGeneration;
    const bool continued=ownedAttempt&&known&&eos==3&&[runtime[@"continuedNewUser"] boolValue]&&[runtime[@"originalCallbackDelivered"] boolValue];
    const bool complete=ownedAttempt&&!local&&known&&((eos==0&&delivered)||(continued&&[runtime[@"newUserMigrationValidated"] boolValue]))&&[runtime[@"fullGameCompleted"] boolValue];
    s.lastStatus.store(local);
    // Capture/preparation publishes neutral state too. It is neither a rejected
    // credential nor a completed request and must not erase an in-flight key.
    if(!local&&!known)return;
    if(!ownedAttempt){writeStatus();return;}
    if(!local&&known&&eos==3&&[runtime[@"awaitingNewUserConfirmation"] boolValue]){
        // An actual SDK InvalidUser result is a choice, never automatic
        // enrollment. The UI holds no manager, continuation or account handle.
        const auto captureSerial=s.captures.load(),submitSerial=s.submissions.load();
        const auto epoch=s.credentialEpoch.load();
        const auto completionSerial=[runtime[@"completionCount"] unsignedLongLongValue];
        EHRItchSignInOfferNewProfile(^int32_t {
            auto &current=state();NSDictionary *now=EHRItchAuthCopyStatus();
            if(!proofForAttempt()||current.authGeneration!=current.ownershipGeneration||current.clearedForRestart.load()||current.credentialEpoch.load()!=epoch||current.captures.load()!=captureSerial||current.submissions.load()!=submitSerial||
               [now[@"completionCount"] unsignedLongLongValue]!=completionSerial||
               ![now[@"awaitingNewUserConfirmation"] boolValue])return EHR_RUNTIME_NOT_READY;
            const int32_t code=EHRItchAuthConfirmNewUser();current.lastStatus.store(code);
            if(code){wipe(current.attemptKey);wipe(current.sessionKey);current.savedKeyAllowed=false;EHRItchAuthCancel();}
            writeStatus();return code;
        });
        writeStatus();return;
    }
    if(local||(known&&eos&&!continued)){
        s.savedKeyAllowed=false;wipe(s.attemptKey);wipe(s.sessionKey);
    } else if(complete){
        if(s.attemptKey.length){wipe(s.sessionKey);s.sessionKey=[s.attemptKey mutableCopy];}
        wipe(s.attemptKey);s.savedKeyAllowed=true;s.presenting=false;
    }
    EHRItchSignInUpdateResult(local,known?eos:-1,complete);
    writeStatus();
}
void acquire(void *manager,void *success,void *failure,bool silent){
    auto &s=state();
    // Clearing intentionally freezes provider work until the process restarts.
    // A new frame's callbacks are not ours to cancel or fabricate a result for.
    if(s.clearedForRestart.load())return;
    if(NSThread.isMainThread)refreshNativeLoginWait();
    if(silent&&s.awaitingNativeLogin.load())return;
    const auto serial=++s.captures,epoch=s.credentialEpoch.load();
    @try {try {
        if(s.prepared.load()!=EHR_RUNTIME_OK)(void)EHRItchAuthProviderStart();
        const auto code=silent?EHRItchAuthCaptureSilent(manager):EHRItchAuthCapture(manager,success,failure);
        s.lastStatus.store(code);
        if(code){
            if(NSThread.isMainThread&&s.awaitingNativeLogin.load())retireDeferredAttempt();
            ++s.faults;
            dispatch_async(dispatch_get_main_queue(),^{
                auto &current=state();if(current.clearedForRestart.load()||current.credentialEpoch.load()!=epoch||current.captures.load()!=serial)return;
                NSDictionary *runtime=EHRItchAuthCopyStatus();
                if([runtime[@"pending"] boolValue]||[runtime[@"awaitingFullCompletion"] boolValue])return;
                if(current.awaitingNativeLogin.load())retireDeferredAttempt();
                current.promptRequested=true;pump();EHRItchSignInUpdateResult(code,-1,false);writeStatus();
            });
            return;
        }
        initialCredential();
        if(s.attemptKey.length){if(s.ownershipPending.load())return;if(proofForAttempt())beginAuth();else beginAttempt(s.attemptKey);return;}
        if(s.sessionKey.length&&s.savedKeyAllowed){
            ++s.renewalAttempts;s.attemptKey=[s.sessionKey mutableCopy];beginAttempt(s.attemptKey);return;
        }
        s.promptRequested=true;
        dispatch_async(dispatch_get_main_queue(),^{pump();});
    } catch (...) {++s.faults;s.lastStatus.store(EHR_RUNTIME_UNSUPPORTED);}}
    @catch (__unused NSException *exception){++s.faults;s.lastStatus.store(EHR_RUNTIME_UNSUPPORTED);}
}
int32_t clearLocalCredential(){
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    auto &s=state();if(!selected())return EHR_RUNTIME_UNSUPPORTED;
    s.clearedForRestart.store(true);++s.credentialEpoch;++s.credentialClears;retireOwnership();
    s.promptRequested=false;s.presenting=false;s.savedKeyAllowed=false;
    wipe(s.attemptKey);wipe(s.sessionKey);
    const auto code=EHRItchAuthCancel();s.lastStatus.store(code);writeStatus();return code;
}
}

bool EHRItchAuthProviderSelected(void){return selected();}
bool EHRItchAuthProviderOwnershipVerified(void){return NSThread.isMainThread&&proofCurrent();}
bool EHRItchAuthProviderDirectoryAllowed(void){
    if(!NSThread.isMainThread||!proofCurrent())return false;auto &s=state();
    return s.authGeneration==s.ownershipGeneration&&s.sessionKey.length&&[s.proofKey isEqualToData:s.sessionKey]&&[EHRItchAuthCopyStatus()[@"fullGameCompleted"] boolValue];
}
int32_t EHRItchAuthProviderStart(void){
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    auto &s=state();if(!selected())return EHR_RUNTIME_UNSUPPORTED;
    if(s.started&&!s.prepared.load())return EHR_RUNTIME_OK;
    const int32_t code=EHRItchAuthPrepare();s.prepared.store(code);s.lastStatus.store(code);
    if(!code){
        EHRItchAuthSetResultHandler(^(int32_t local,int32_t eos,bool known,bool delivered){result(local,eos,known,delivered);});
        const auto enabled=EHRItchAuthSetEnabled(1);
        if(enabled){s.prepared.store(enabled);s.lastStatus.store(enabled);return enabled;}
    }
    if(!s.started){
        s.started=true;s.timer=[NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(__unused NSTimer *timer){pump();}];
        [NSRunLoop.mainRunLoop addTimer:s.timer forMode:NSRunLoopCommonModes];
    }
    return code;
}
void EHRItchAuthProviderSetPresenter(UIViewController *presenter){
    if(!NSThread.isMainThread)return;
    state().presenter=presenter;if(selected()&&presenter.view.window)(void)EHRItchAuthProviderStart();pump();
}
void EHRItchAuthProviderPresent(void){
    if(!NSThread.isMainThread||!selected())return;
    if(state().clearedForRestart.load()){EHRItchAuthProviderPresentAccount();return;}
    auto &s=state();refreshNativeLoginWait();
    NSDictionary *before=EHRItchAuthCopyStatus();
    if([before[@"fullGameCompleted"] boolValue]){EHRItchAuthProviderPresentAccount();return;}
    if([before[@"pending"] boolValue]||[before[@"awaitingFullCompletion"] boolValue]||[before[@"awaitingNewUserConfirmation"] boolValue])return;
    if(s.ownershipPending.load())return;
    if(s.awaitingNativeLogin.load()){continueVerifiedAttempt();writeStatus();return;}
    // Opening the key form does not enter the game's guest or login path.
    // Only submit's successful ownership callback may request platform login.
    s.promptRequested=true;pump();
}
void EHRItchAuthProviderPresentAccount(void){
    if(!NSThread.isMainThread||!selected())return;
    auto &s=state();refreshNativeLoginWait();UIViewController *presenter=s.presenter;
    if(!presenter||!presenter.view.window||presenter.presentedViewController)return;
    NSDictionary *runtime=EHRItchAuthCopyStatus();
    const bool full=!s.clearedForRestart.load()&&[runtime[@"fullGameCompleted"] boolValue];
    const auto epoch=s.credentialEpoch.load();
    const bool idle=!full&&!s.clearedForRestart.load()&&!s.ownershipPending.load()&&![runtime[@"pending"] boolValue]&&![runtime[@"awaitingFullCompletion"] boolValue]&&![runtime[@"awaitingNewUserConfirmation"] boolValue];
    void (^signIn)(void)=nil;
    if(idle)signIn=^{
        auto &current=state();NSDictionary *now=EHRItchAuthCopyStatus();
        if(current.ownershipPending.load()||current.clearedForRestart.load()||current.credentialEpoch.load()!=epoch||[now[@"fullGameCompleted"] boolValue]||[now[@"pending"] boolValue]||[now[@"awaitingFullCompletion"] boolValue]||[now[@"awaitingNewUserConfirmation"] boolValue])return;
        EHRItchAuthProviderPresent();
    };
    EHRItchSignInPresentAccount(presenter,full,^int32_t {return clearLocalCredential();},signIn);
}
NSDictionary *EHRItchAuthProviderCopyStatus(void){
    auto &s=state();
    return @{@"schemaVersion":@2,@"selected":@(selected()),@"preparedStatus":@(s.prepared.load()),
        @"lastStatus":@(s.lastStatus.load()),@"captures":@(s.captures.load()),@"prompts":@(s.prompts.load()),
        @"submissions":@(s.submissions.load()),@"renewalAttempts":@(s.renewalAttempts.load()),@"faults":@(s.faults.load()),
        @"clearedForRestart":@(s.clearedForRestart.load()),@"credentialEpoch":@(s.credentialEpoch.load()),@"credentialClears":@(s.credentialClears.load()),
        @"ownershipStatus":@(s.ownershipStatus.load()),@"ownershipHTTPStatus":@(s.ownershipHTTPStatus.load()),
        @"ownershipVerified":@(s.ownershipVerified.load()),@"ownershipPending":@(s.ownershipPending.load()),@"ownershipChecks":@(s.ownershipChecks.load()),
        @"directoryAllowed":@(EHRItchAuthProviderDirectoryAllowed()),@"awaitingNativeLogin":@(s.awaitingNativeLogin.load()),@"nativeLoginWaitSeconds":@(nativeLoginWaitSeconds()),@"ownershipResponse":ownershipResponseSnapshot(),@"runtime":EHRItchAuthCopyStatus(),@"interface":EHRItchSignInCopyStatus()};
}

extern "C" __attribute__((visibility("default")))
void ehr_native_eos_itch_platform_impl(void *manager,void *success,void *failure,const void *methodInfo){
    using Original=void(*)(void *,void *,void *,const void *);
    if(!selected()){
        reinterpret_cast<Original>(EHRNativeHooksImageBaseForDiagnostics()+EHRItchAuthImplTrampolineRVA)(manager,success,failure,methodInfo);return;
    }
    acquire(manager,success,failure,false);
    // An explicitly selected provider never falls back into Apple acquisition.
}
extern "C" __attribute__((visibility("default")))
void ehr_native_eos_itch_silent_login(void *manager,const void *methodInfo){
    using Original=void(*)(void *,const void *);
    auto original=reinterpret_cast<Original>(EHRNativeHooksImageBaseForDiagnostics()+EHRItchAuthSilentTrampolineRVA);
    if(!selected()){original(manager,methodInfo);return;}
    if(state().clearedForRestart.load())return;
    bool guest=false;
    const auto status=EHRItchAuthIsGuestSilentPath(manager,&guest);
    if(!status&&guest){
        if(EHRItchAuthProviderOwnershipVerified())original(manager,methodInfo);
        else if(NSThread.isMainThread){state().promptRequested=!state().ownershipPending.load();pump();}
        return;
    }
    if(status){
        if(NSThread.isMainThread){refreshNativeLoginWait();if(state().awaitingNativeLogin.load()){state().lastStatus.store(status);writeStatus();return;}}
        state().lastStatus.store(status);++state().faults;
        const auto serial=++state().captures,epoch=state().credentialEpoch.load();
        dispatch_async(dispatch_get_main_queue(),^{
            if(state().clearedForRestart.load()||state().credentialEpoch.load()!=epoch||state().captures.load()!=serial)return;
            NSDictionary *runtime=EHRItchAuthCopyStatus();
            if([runtime[@"pending"] boolValue]||[runtime[@"awaitingFullCompletion"] boolValue])return;
            EHRItchSignInUpdateResult(status,-1,false);
        });return;
    }
    if(NSThread.isMainThread)refreshNativeLoginWait();
    if(state().awaitingNativeLogin.load())return;
    acquire(manager,nullptr,nullptr,true);
}
extern "C" __attribute__((visibility("default")))
void ehr_native_eos_itch_final_completed(void *manager,const void *methodInfo){
    using Original=void(*)(void *,const void *);
    reinterpret_cast<Original>(EHRNativeHooksImageBaseForDiagnostics()+EHRItchAuthFinalTrampolineRVA)(manager,methodInfo);
    if(selected())EHRItchAuthObserveFullCompletion(manager);
}
extern "C" __attribute__((visibility("default")))
void ehr_native_eos_itch_guest_migration(void *manager,const void *methodInfo){
    using Original=void(*)(void *,const void *);
    if(selected()){
        const auto status=EHRItchAuthCheckNewUserMigration(manager);
        if(status!=EHR_RUNTIME_OK){
            // A normal return lets the caller save account data. Propagate an
            // owned IL2CPP exception after the runtime records/fences rejection.
            EHRRuntimeIteratorRaise(static_cast<EHRRuntimeStatus>(status));return;
        }
    }
    reinterpret_cast<Original>(EHRNativeHooksImageBaseForDiagnostics()+EHRItchAuthGuestMigrationTrampolineRVA)(manager,methodInfo);
}
