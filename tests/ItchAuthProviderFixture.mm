// Compiles the exact coordinator with owned Foundation/UIKit/runtime shims.
// No game, SDK, Keychain, account, credential or network operation is linked.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../native/EHRItchAuthRuntime.h"
#import "../native/EHRItchSignInUI.h"
#import "../native/EHRItchOwnership.h"
#import "../native/EHRRuntimeGateway.h"
#include <atomic>
#include <cstring>
#include <stdexcept>

@implementation UIView
@end
@implementation UIViewController
@end
static NSDictionary *fixtureInfo;
@interface FixtureBundle:NSObject
+ (instancetype)mainBundle;
- (NSDictionary *)infoDictionary;
@end
@implementation FixtureBundle
+ (instancetype)mainBundle {static FixtureBundle *bundle=[FixtureBundle new];return bundle;}
- (NSDictionary *)infoDictionary {return fixtureInfo;}
@end
static void FixtureOriginalImpl(void *,void *,void *,const void *);
static void FixtureOriginalFinal(void *,const void *);
static void FixtureOriginalSilent(void *,const void *);
static void FixtureOriginalMigration(void *,const void *);
#define NSBundle FixtureBundle
#import "../native/EHRItchAuthProvider.mm"
#undef NSBundle

namespace {
NSUInteger checks=0;NSMutableArray<NSString *> *failures;
EHRItchOwnershipStatus fixtureOwnership=EHRItchOwnershipVerified;
bool deferOwnership=false;NSUInteger ownershipStarts=0,ownershipCancels=0,ownershipUpdates=0;
NSMutableArray<EHRItchOwnershipCompletion> *ownershipCallbacks;
struct Calls {NSUInteger prepare=0,enable=0,capture=0,captureSilent=0,guestCheck=0,begin=0,cancel=0,request=0,observe=0,present=0,update=0,saved=0,original=0,finalOriginal=0,silentOriginal=0,offer=0,confirm=0,migrationCheck=0,migrationOriginal=0,migrationRaise=0,accountPresent=0;};
Calls calls;
int32_t fixturePrepare=0,fixtureEnable=0,fixtureCapture=0,fixtureBegin=0,fixtureRequest=0,fixtureGuestStatus=0;
int32_t fixtureConfirm=0,fixtureMigration=0;
bool runtimeCaptured=false,runtimePending=false,runtimeFull=false,runtimeAwaiting=false,neutralDuringCapture=false,reenterRequest=false,fixtureGuest=false,retainKeylessOnCancel=false;
bool runtimeNewPending=false,runtimeContinued=false,runtimeCallbackDelivered=false,runtimeMigrationValidated=false;
uint64_t runtimeCompletions=0;
std::atomic<bool> wrongUIThread{false};
EHRItchAuthResultHandler resultHandler=nil;
EHRItchSignInSubmit uiSubmit=nil;
int32_t (^uiConfirm)(void)=nil;
int32_t (^uiAccountClear)(void)=nil;
void (^uiAccountSignIn)(void)=nil;
bool accountFull=false,fixtureUIVisible=false,fixtureUIBusy=false,runtimeResultKnown=false;
uint64_t runtimeSDKCalls=0;
void (^requestSideEffect)(void)=nil;
NSMutableData *runtimeKey=nil,*savedKey=nil;
NSMutableArray<NSString *> *order;
int32_t uiLocal=0,uiEOS=0;bool uiFull=false;
void *expectedManager=nullptr,*expectedSuccess=nullptr,*expectedFailure=nullptr;const void *expectedMethod=nullptr;
int managerTag=1,successTag=2,failureTag=3,methodTag=4;
void Check(bool okay,NSString *name){++checks;if(!okay)[failures addObject:name];}
NSMutableData *FakeKey(NSString *suffix){return [[[NSString stringWithFormat:@"OWNED-FAKE-%@-NOT-A-CREDENTIAL",suffix] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];}
bool Zeroed(NSData *data){if(!data)return false;const uint8_t *bytes=(const uint8_t *)data.bytes;for(NSUInteger i=0;i<data.length;++i)if(bytes[i])return false;return true;}
void DrainMain(){__block bool reached=false;dispatch_async(dispatch_get_main_queue(),^{reached=true;});NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];while(!reached&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];Check(reached,@"owned_main_queue_drained");}
void OnWorker(void(^block)(void)){dispatch_semaphore_t done=dispatch_semaphore_create(0);dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{Check(!NSThread.isMainThread,@"owned_actual_worker_thread");block();dispatch_semaphore_signal(done);});Check(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0,@"owned_worker_completed");}
void Reset(){
    DrainMain();auto &s=state();[s.timer invalidate];s.timer=nil;retireOwnership();wipe(s.attemptKey);wipe(s.sessionKey);s.initialCredentialChecked=false;s.ownershipGeneration=0;s.proofEpoch=0;s.authGeneration=0;s.ownershipChecks.store(0);ownershipStarts=ownershipCancels=ownershipUpdates=0;fixtureOwnership=EHRItchOwnershipVerified;deferOwnership=false;ownershipCallbacks=[NSMutableArray new];s.presenter=nil;s.started=false;s.promptRequested=false;s.presenting=false;s.savedKeyAllowed=true;s.prepared.store(EHR_RUNTIME_NOT_READY);s.lastStatus.store(EHR_RUNTIME_NOT_READY);s.captures.store(0);s.prompts.store(0);s.submissions.store(0);s.renewalAttempts.store(0);s.faults.store(0);
    s.clearedForRestart.store(false);s.credentialEpoch.store(0);s.credentialClears.store(0);
    fixtureUIVisible=fixtureUIBusy=runtimeResultKnown=false;runtimeSDKCalls=0;requestSideEffect=nil;
    fixtureInfo=@{@"EHRItchAuthCompiled":@YES,@"EHRAuthProvider":@"itchio"};calls={};fixturePrepare=fixtureEnable=fixtureCapture=fixtureBegin=fixtureRequest=fixtureGuestStatus=fixtureConfirm=fixtureMigration=0;runtimeCaptured=runtimePending=runtimeFull=runtimeAwaiting=neutralDuringCapture=reenterRequest=fixtureGuest=retainKeylessOnCancel=runtimeNewPending=runtimeContinued=runtimeCallbackDelivered=runtimeMigrationValidated=false;runtimeCompletions=0;resultHandler=nil;uiSubmit=nil;uiConfirm=nil;uiAccountClear=nil;uiAccountSignIn=nil;accountFull=false;runtimeKey=nil;savedKey=nil;uiLocal=uiEOS=0;uiFull=false;wrongUIThread.store(false);order=[NSMutableArray new];expectedManager=&managerTag;expectedSuccess=&successTag;expectedFailure=&failureTag;expectedMethod=&methodTag;
}
UIViewController *Presenter(){UIViewController *view=[UIViewController new];view.view=[UIView new];view.view.window=[NSObject new];return view;}
void SeedAttempt(NSString *name){auto &s=state();s.attemptKey=FakeKey(name);s.proofKey=[s.attemptKey mutableCopy];s.proofEpoch=s.credentialEpoch.load();s.ownershipVerified.store(true);s.ownershipPending.store(false);s.ownershipStatus.store(EHRItchOwnershipVerified);++s.ownershipGeneration;s.authGeneration=s.ownershipGeneration;}
void Wrapper(){ehr_native_eos_itch_platform_impl(expectedManager,expectedSuccess,expectedFailure,expectedMethod);}
void SilentWrapper(){ehr_native_eos_itch_silent_login(expectedManager,expectedMethod);}
}

@interface EHRItchOwnershipCheck()
- (instancetype)initOwnedFixture;
@end
@implementation EHRItchOwnershipCheck
- (instancetype)initOwnedFixture {return [super init];}
- (void)cancel {++ownershipCancels;}
@end
EHRItchOwnershipCheck *EHRItchOwnershipBegin(NSData *key,EHRItchOwnershipCompletion completion){
    ++ownershipStarts;Check(NSThread.isMainThread,@"ownership_starts_only_main");[order addObject:@"ownership"];
    Check(key!=nil,@"only_synthetic_credential_passed_to_owned_check");
    EHRItchOwnershipCheck *check=[[EHRItchOwnershipCheck alloc] initOwnedFixture];
    if(deferOwnership)[ownershipCallbacks addObject:[completion copy]];
    else completion((!key.length||key.length>8192)?EHRItchOwnershipBadCredentialFormat:fixtureOwnership,200);
    return check;
}
NSDictionary<NSString *,NSNumber *> *EHRItchOwnershipCopyDiagnostics(EHRItchOwnershipCheck *check){
    Check(check==state().ownershipCheck,@"diagnostics_only_copied_from_current_owned_check");
    return (NSDictionary *)@{@"schemaVersion":@1,@"parserStage":@25,@"requestedPage":@1,@"responseBytes":@17,@"totalBytes":@17,
        @"httpTyped":@1,@"urlMatched":@1,@"mimeJSON":@1,@"lengthOK":@1,@"rootKind":@2,@"ownedKeysKind":@3,@"ownedKeysCount":@0,
        @"pageKind":@0,@"returnedPage":@0,@"perPageKind":@0,@"returnedPerPage":@0,
        @"unexpectedString":@"OWNED-REDACTION-SECRET",@"unexpectedNumber":@777,@"unexpectedBody":@{@"secret":@1}};
}
void EHRItchSignInUpdateOwnership(EHRItchOwnershipStatus status,int32_t http,bool pending){
    ++ownershipUpdates;Check(NSThread.isMainThread,@"ownership_ui_only_main");Check(status>=0&&status<=11&&http>=0&&http<=999,@"ownership_ui_bounded_numeric");
    if(!pending)[order addObject:status==EHRItchOwnershipVerified?@"verified":@"denied"];
}

extern "C" uintptr_t EHRNativeHooksImageBaseForDiagnostics(void){return 0;}
static void FixtureOriginalImpl(void *manager,void *success,void *failure,const void *method){++calls.original;Check(manager==expectedManager&&success==expectedSuccess&&failure==expectedFailure&&method==expectedMethod,@"ordinary_original_arguments_unchanged");[order addObject:@"original"];}
static void FixtureOriginalSilent(void *manager,const void *method){++calls.silentOriginal;Check(manager==expectedManager&&method==expectedMethod,@"silent_original_arguments_unchanged");[order addObject:@"silent-original"];}
static void FixtureOriginalMigration(void *manager,const void *method){++calls.migrationOriginal;Check(manager==expectedManager&&method==expectedMethod,@"migration_original_arguments_unchanged");[order addObject:@"migration-original"];}
static void FixtureOriginalFinal(void *manager,const void *method){++calls.finalOriginal;Check(manager==expectedManager&&method==expectedMethod,@"final_original_arguments_unchanged");[order addObject:@"final-original"];}
extern "C" int32_t EHRItchAuthPrepare(void){++calls.prepare;[order addObject:@"prepare"];return fixturePrepare;}
extern "C" int32_t EHRItchAuthSetEnabled(int32_t enabled){++calls.enable;Check(enabled==1,@"provider_only_enables_after_prepare");return fixtureEnable;}
extern "C" int32_t EHRItchAuthCapture(void *manager,void *success,void *failure){++calls.capture;Check(manager==expectedManager&&success==expectedSuccess&&failure==expectedFailure,@"capture_frame_args_preserved");if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;[order addObject:@"capture"];if(fixtureCapture)return fixtureCapture;runtimeCaptured=true;runtimePending=false;if(neutralDuringCapture&&resultHandler)resultHandler(0,0,false,false);return 0;}
extern "C" int32_t EHRItchAuthCaptureSilent(void *manager){++calls.captureSilent;Check(manager==expectedManager,@"silent_capture_owner_preserved");if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;[order addObject:@"silent-capture"];if(fixtureCapture)return fixtureCapture;runtimeCaptured=true;runtimePending=false;if(neutralDuringCapture&&resultHandler)resultHandler(0,0,false,false);return 0;}
extern "C" int32_t EHRItchAuthIsGuestSilentPath(void *manager,bool *guest){++calls.guestCheck;Check(manager==expectedManager,@"guest_query_owner_preserved");if(guest)*guest=fixtureGuest;if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;return fixtureGuestStatus;}
extern "C" int32_t EHRItchAuthBegin(NSData *key,bool resultOnly){++calls.begin;[order addObject:@"begin"];Check(NSThread.isMainThread,@"runtime_begin_main_only");Check(!resultOnly,@"provider_requests_normal_game_completion");runtimeKey=[key mutableCopy];if(!fixtureBegin){++runtimeSDKCalls;runtimeCaptured=false;runtimePending=true;}return fixtureBegin;}
extern "C" int32_t EHRItchAuthCancel(void){++calls.cancel;Check(NSThread.isMainThread,@"runtime_cancel_main_only");runtimeCaptured=retainKeylessOnCancel;runtimePending=false;runtimeFull=false;runtimeNewPending=false;return 0;}
extern "C" int32_t EHRItchAuthConfirmNewUser(void){++calls.confirm;Check(NSThread.isMainThread,@"new_user_confirm_main_only");if(!fixtureConfirm){runtimeNewPending=false;runtimeContinued=true;runtimeCallbackDelivered=true;runtimeAwaiting=true;}return fixtureConfirm;}
extern "C" int32_t EHRItchAuthCheckNewUserMigration(void *manager){++calls.migrationCheck;Check(manager==expectedManager,@"migration_check_owner_preserved");return fixtureMigration;}
void EHRRuntimeIteratorRaise(EHRRuntimeStatus status){++calls.migrationRaise;Check(status==EHR_RUNTIME_UNSUPPORTED,@"owned_native_migration_failure_status_propagated");throw std::runtime_error("owned fixture native failure");}
extern "C" int32_t EHRItchAuthRequestPlatformLogin(void){++calls.request;[order addObject:@"request"];Check(NSThread.isMainThread,@"normal_reentry_main_only");void (^sideEffect)(void)=[requestSideEffect copy];if(sideEffect)sideEffect();if(fixtureRequest)return fixtureRequest;if(reenterRequest)Wrapper();return 0;}
extern "C" void EHRItchAuthSetResultHandler(EHRItchAuthResultHandler handler){Check(NSThread.isMainThread,@"handler_installed_on_main");resultHandler=[handler copy];}
extern "C" void EHRItchAuthObserveFullCompletion(void *manager){++calls.observe;Check(manager==expectedManager,@"final_owner_preserved");[order addObject:@"observe"];}
extern "C" NSDictionary<NSString *,id> *EHRItchAuthCopyStatus(void){return @{@"sdkLoginCalls":@(runtimeSDKCalls),@"resultKnown":@(runtimeResultKnown),@"captured":@(runtimeCaptured),@"pending":@(runtimePending),@"fullGameCompleted":@(runtimeFull),@"awaitingFullCompletion":@(runtimeAwaiting),@"awaitingNewUserConfirmation":@(runtimeNewPending),@"continuedNewUser":@(runtimeContinued),@"originalCallbackDelivered":@(runtimeCallbackDelivered),@"completionCount":@(runtimeCompletions),@"newUserMigrationValidated":@(runtimeMigrationValidated)};}
void EHRItchSignInPresent(UIViewController *presenter,EHRItchSignInSubmit submit){++calls.present;if(!NSThread.isMainThread)wrongUIThread.store(true);Check(presenter!=nil,@"own_presenter_supplied");uiSubmit=[submit copy];[order addObject:@"present"];}
void EHRItchSignInPresentAccount(UIViewController *presenter,bool full,int32_t (^clearSession)(void),void (^signIn)(void)){++calls.accountPresent;Check(NSThread.isMainThread&&presenter!=nil,@"account_uses_main_existing_presenter");accountFull=full;uiAccountClear=[clearSession copy];uiAccountSignIn=[signIn copy];}
void EHRItchSignInUpdateResult(int32_t local,int32_t eos,bool complete){++calls.update;if(!NSThread.isMainThread)wrongUIThread.store(true);uiLocal=local;uiEOS=eos;uiFull=complete;}
void EHRItchSignInOfferNewProfile(int32_t (^confirm)(void)){++calls.offer;Check(NSThread.isMainThread,@"new_profile_offer_main_only");uiConfirm=[confirm copy];}
NSDictionary *EHRItchSignInCopyStatus(void){return @{@"schemaVersion":@1,@"known":@NO,@"visible":@(fixtureUIVisible),@"busy":@(fixtureUIBusy)};}
NSMutableData *EHRItchSignInCopySavedKey(void){++calls.saved;Check(NSThread.isMainThread,@"saved_key_queried_on_main");return savedKey;}

int main(){@autoreleasepool{
    failures=[NSMutableArray new];Reset();
    Check(EHRItchAuthProviderSelected(),@"explicit_provider_selected");Check(EHRItchAuthProviderStart()==0,@"startup_prepares");Check(calls.prepare==1&&calls.enable==1&&calls.capture==0&&calls.begin==0&&calls.request==0&&calls.present==0&&calls.saved==0&&ownershipStarts==0,@"passive_startup_does_not_read_credentials_or_authenticate");Check(EHRItchAuthProviderStart()==0&&calls.prepare==1&&calls.enable==1,@"startup_idempotent");
    Reset();fixtureInfo=@{@"EHRItchAuthCompiled":@YES,@"EHRAuthProvider":@1};Check(!EHRItchAuthProviderSelected(),@"malformed_provider_not_selected");Wrapper();Check(calls.original==1&&calls.capture==0&&calls.begin==0,@"unselected_calls_ordinary_original_once");ehr_native_eos_itch_final_completed(expectedManager,expectedMethod);Check(calls.finalOriginal==1&&calls.observe==0,@"unselected_final_only_original");
    Reset();fixturePrepare=EHR_RUNTIME_UNSUPPORTED;Check(EHRItchAuthProviderStart()==EHR_RUNTIME_UNSUPPORTED&&calls.enable==0&&calls.request==0&&calls.begin==0,@"failed_prepare_never_enables_or_logs_in");
    Reset();fixtureEnable=EHR_RUNTIME_NOT_READY;Check(EHRItchAuthProviderStart()==EHR_RUNTIME_NOT_READY&&calls.begin==0&&calls.request==0,@"failed_enable_never_logs_in");
    Reset();OnWorker(^{Check(EHRItchAuthProviderStart()==EHR_RUNTIME_WRONG_THREAD,@"worker_start_rejected");EHRItchAuthProviderPresent();EHRItchAuthProviderSetPresenter(Presenter());});Check(calls.prepare==0&&calls.request==0&&calls.present==0&&state().presenter==nil,@"worker_public_apis_do_not_start_login_or_ui");
    Reset();EHRItchAuthProviderStart();submit([NSData data]);submit([NSMutableData dataWithLength:8193]);Check(calls.begin==0&&calls.request==0&&ownershipUpdates==2&&ownershipStarts==0&&calls.begin==0&&state().attemptKey==nil,@"invalid_submit_never_enters_normal_auth_or_retains_key");
    Reset();EHRItchAuthProviderStart();UIViewController *blockedPresenter=Presenter();blockedPresenter.presentedViewController=[UIViewController new];EHRItchAuthProviderSetPresenter(blockedPresenter);Wrapper();DrainMain();Check(calls.present==0&&state().promptRequested,@"existing_modal_prevents_new_signin_presentation");blockedPresenter.presentedViewController=nil;pump();Check(calls.present==1&&!state().promptRequested,@"pending_prompt_waits_for_available_presenter");
    Reset();EHRItchAuthProviderStart();UIViewController *failedPresenter=Presenter();EHRItchAuthProviderSetPresenter(failedPresenter);fixtureCapture=EHR_RUNTIME_NOT_READY;Wrapper();Check(calls.original==0&&calls.begin==0&&calls.saved==1&&calls.update==0,@"selected_capture_failure_never_apple_or_second_key_read");DrainMain();Check(calls.present==1&&calls.update==1&&uiLocal==EHR_RUNTIME_NOT_READY&&!wrongUIThread.load(),@"main_capture_failure_reports_numeric_error_after_safe_presentation");
    Reset();Check(EHRItchAuthProviderStart()==0,@"neutral_case_start");neutralDuringCapture=true;reenterRequest=true;NSMutableData *key=FakeKey(@"NEUTRAL");submit(key);Check([order containsObject:@"request"]&&calls.request==1&&calls.capture==1&&calls.begin==1,@"normal_request_reentry_reaches_capture_and_begin");Check([order indexOfObject:@"request"]<[order indexOfObject:@"capture"]&&[order indexOfObject:@"capture"]<[order indexOfObject:@"begin"],@"normal_request_capture_begin_order");Check([runtimeKey isEqualToData:key]&&[state().attemptKey isEqualToData:key],@"neutral_capture_notification_preserves_attempt_bytes");Check(calls.update==0&&calls.original==0&&calls.saved==0,@"neutral_capture_no_failure_ui_or_apple_or_saved_fallback");NSMutableData *attempt=state().attemptKey;state().sessionKey=FakeKey(@"PRIOR-SESSION");NSMutableData *priorSession=state().sessionKey;
    dispatch_async(dispatch_get_main_queue(),^{resultHandler(0,7000,true,false);});DrainMain();Check(state().attemptKey==nil&&state().sessionKey==nil&&Zeroed(attempt)&&Zeroed(priorSession),@"delayed_real_failure_wipes_attempt_and_prior_session");Check(calls.update==1&&uiLocal==0&&uiEOS==7000&&!uiFull&&!state().savedKeyAllowed,@"real_failure_updates_ui_and_disallows_bad_saved_renewal");
    Reset();Check(EHRItchAuthProviderStart()==0,@"cancel_case_start");runtimeCaptured=true;NSMutableData *cancelKey=FakeKey(@"CANCEL");submit(cancelKey);state().sessionKey=FakeKey(@"SESSION");NSMutableData *cancelAttempt=state().attemptKey,*cancelSession=state().sessionKey;submit(nil);Check(calls.cancel==1&&state().attemptKey==nil&&state().sessionKey==nil&&Zeroed(cancelAttempt)&&Zeroed(cancelSession),@"local_cancel_wipes_both_caches");Check(!state().presenting&&!state().promptRequested&&!state().savedKeyAllowed,@"local_cancel_clears_queued_prompt");
    Reset();Check(EHRItchAuthProviderStart()==0,@"begin_failure_start");runtimeCaptured=true;fixtureBegin=EHR_RUNTIME_BAD_ARGUMENT;submit(FakeKey(@"INVALID"));Check(calls.begin==1&&calls.cancel==1&&calls.update==1&&uiEOS==-1&&state().attemptKey==nil&&!state().savedKeyAllowed,@"begin_rejection_clears_secret_and_failure_flow");
    Reset();Check(EHRItchAuthProviderStart()==0,@"request_failure_start");fixtureRequest=EHR_RUNTIME_LIMIT;submit(FakeKey(@"REQUEST"));Check(calls.request==1&&calls.begin==0&&state().attemptKey==nil&&calls.update==1&&uiLocal==EHR_RUNTIME_LIMIT,@"normal_request_rejection_clears_attempt");
    for(int localFailure=0;localFailure<2;++localFailure)for(int eosFailure=0;eosFailure<2;++eosFailure)for(int known=0;known<2;++known)for(int delivered=0;delivered<2;++delivered)for(int final=0;final<2;++final){
        Reset();EHRItchAuthProviderStart();SeedAttempt(@"MATRIX");NSMutableData *before=state().attemptKey;runtimeFull=final;resultHandler(localFailure?6:0,eosFailure?7000:0,known,delivered);bool complete=!localFailure&&!eosFailure&&known&&delivered&&final;bool rejected=localFailure||(known&&eosFailure);
        Check(bool(state().sessionKey.length)==complete,@"cache_only_all_success_gates");Check(complete?state().attemptKey==nil:rejected?state().attemptKey==nil:state().attemptKey!=nil,@"pending_vs_rejected_attempt_ownership");Check((complete||rejected)?Zeroed(before):!Zeroed(before),@"attempt_bytes_wiped_only_terminal");Check((!localFailure&&!known)?calls.update==0:calls.update==1,@"unknown_neutral_result_is_not_ui_failure");
    }
    Reset();EHRItchAuthProviderStart();SeedAttempt(@"FULL");runtimeFull=true;resultHandler(0,0,true,true);NSMutableData *session=state().sessionKey;Check(session.length>0&&state().attemptKey==nil&&state().savedKeyAllowed,@"full_success_cache_ready");runtimePending=false;runtimeCaptured=false;runtimeFull=false;Wrapper();Check(calls.capture==1&&calls.begin==1&&calls.saved==0&&[runtimeKey isEqualToData:session],@"renewal_uses_only_successful_session_key");Check(state().renewalAttempts.load()==1&&calls.original==0,@"renewal_never_falls_back_to_apple");
    Reset();savedKey=FakeKey(@"REMEMBERED");EHRItchAuthProviderStart();EHRItchAuthProviderSetPresenter(Presenter());Check(ownershipStarts==1&&calls.begin==0&&calls.request==1&&EHRItchAuthProviderOwnershipVerified(),@"saved_startup_license_preflight_before_game_auth");Wrapper();Check(calls.saved==1&&calls.begin==1&&state().attemptKey.length>0&&Zeroed(savedKey),@"remembered_key_copied_then_borrow_wiped");Check(calls.original==0,@"remembered_login_no_apple");
    Reset();EHRItchAuthProviderStart();UIViewController *presenter=Presenter();EHRItchAuthProviderSetPresenter(presenter);Wrapper();DrainMain();Check(calls.present==1&&calls.begin==0&&calls.original==0&&uiSubmit!=nil,@"selected_without_key_prompts_once_no_login");pump();Check(calls.present==1,@"prompt_not_duplicated");uiSubmit(nil);Check(calls.cancel==1&&!state().presenting,@"ui_cancel_reaches_normal_cancel");
    Reset();EHRItchAuthProviderStart();presenter=Presenter();EHRItchAuthProviderSetPresenter(presenter);OnWorker(^{Wrapper();});Check(calls.update==0&&calls.present==1,@"worker_failure_does_not_touch_ui_inline");expectedManager=reinterpret_cast<void *>(0x55);expectedSuccess=reinterpret_cast<void *>(0x66);expectedFailure=reinterpret_cast<void *>(0x77);DrainMain();Check(calls.update==1&&uiLocal==EHR_RUNTIME_WRONG_THREAD&&calls.present==1&&!wrongUIThread.load(),@"worker_failure_queues_only_numeric_main_update");Check(calls.capture==1&&calls.begin==0&&calls.original==0,@"queued_failure_never_reuses_raw_frame_or_apple");
    Reset();EHRItchAuthProviderStart();presenter=Presenter();EHRItchAuthProviderSetPresenter(presenter);OnWorker(^{Wrapper();});Wrapper();DrainMain();Check(calls.update==0&&calls.present==1&&!wrongUIThread.load(),@"stale_worker_failure_suppressed_after_new_capture");
    Reset();fixtureInfo=@{@"EHRItchAuthCompiled":@NO,@"EHRAuthProvider":@"itchio"};SilentWrapper();Check(calls.silentOriginal==1&&calls.guestCheck==0&&calls.captureSilent==0,@"unselected_silent_forwards_once_without_provider_queries");
    for(int guest=0;guest<2;++guest)for(int unavailable=0;unavailable<2;++unavailable){
        Reset();EHRItchAuthProviderStart();fixtureGuest=guest;fixtureGuestStatus=unavailable?EHR_RUNTIME_NOT_READY:0;SilentWrapper();DrainMain();bool guestForward=false;bool capturedSilent=!guest&&!unavailable;
        Check(calls.silentOriginal==(guestForward?1u:0u),@"only_confirmed_guest_silent_forwards_original");Check(calls.captureSilent==(capturedSilent?1u:0u)&&calls.capture==0,@"nonguest_silent_uses_distinct_captured_flow");Check(calls.begin==0&&calls.original==0,@"silent_state_query_never_invokes_apple_or_keyless_sdk");Check(unavailable?calls.update==1&&uiLocal==EHR_RUNTIME_NOT_READY:calls.update==0,@"unknown_guest_state_is_numeric_failure_not_guest");
    }
    Reset();EHRItchAuthProviderStart();SeedAttempt(@"SILENT-FULL");runtimeFull=true;resultHandler(0,0,true,true);NSMutableData *silentSession=state().sessionKey;runtimeFull=false;neutralDuringCapture=true;SilentWrapper();Check(calls.guestCheck==1&&calls.captureSilent==1&&calls.capture==0&&calls.begin==1&&calls.request==0&&calls.silentOriginal==0,@"nonguest_silent_renews_with_genuine_silent_capture");Check([runtimeKey isEqualToData:silentSession]&&state().renewalAttempts.load()==1&&calls.update==1,@"silent_neutral_preserves_proven_session_key");
    Reset();EHRItchAuthProviderStart();presenter=Presenter();EHRItchAuthProviderSetPresenter(presenter);SilentWrapper();DrainMain();Check(calls.captureSilent==1&&calls.present==1&&calls.begin==0&&uiSubmit!=nil,@"nonguest_silent_without_key_presents_explicit_input");uiSubmit(FakeKey(@"SILENT-USER"));Check(calls.begin==1&&calls.request==0&&calls.captureSilent==1&&calls.silentOriginal==0,@"silent_user_key_submits_captured_flow_without_new_login");
    Reset();EHRItchAuthProviderStart();presenter=Presenter();EHRItchAuthProviderSetPresenter(presenter);retainKeylessOnCancel=true;Wrapper();DrainMain();uiSubmit(nil);Check(runtimeCaptured&&!runtimePending&&state().attemptKey==nil&&state().sessionKey==nil,@"cancel_retains_only_stubbed_keyless_normal_context");calls.present=0;uiSubmit=nil;EHRItchAuthProviderPresent();Check(calls.request==0&&calls.present==1&&uiSubmit!=nil&&calls.begin==0&&calls.capture==1,@"existing_resumable_context_reopens_input_after_zero_request_result");uiSubmit(FakeKey(@"RESUME"));Check(calls.begin==1&&calls.request==0&&calls.capture==1,@"resumed_context_waits_for_user_key_then_begins_once");
    Reset();EHRItchAuthProviderStart();presenter=Presenter();EHRItchAuthProviderSetPresenter(presenter);OnWorker(^{SilentWrapper();});Check(calls.update==0&&calls.present==1&&calls.captureSilent==0&&calls.silentOriginal==0,@"worker_guest_query_cannot_forward_or_capture");expectedManager=reinterpret_cast<void *>(0x88);DrainMain();Check(calls.guestCheck==1&&calls.update==1&&uiLocal==EHR_RUNTIME_WRONG_THREAD&&!wrongUIThread.load(),@"worker_guest_query_failure_queues_only_numeric_status");
    Reset();EHRItchAuthProviderStart();presenter=Presenter();EHRItchAuthProviderSetPresenter(presenter);OnWorker(^{SilentWrapper();});SeedAttempt(@"NEWER-FLOW");state().authGeneration=0;Wrapper();DrainMain();Check(calls.begin==1&&calls.update==0&&calls.silentOriginal==0,@"stale_silent_query_failure_cannot_overwrite_newer_live_flow");
    for(int awaiting=0;awaiting<2;++awaiting){Reset();EHRItchAuthProviderStart();runtimePending=!awaiting;runtimeAwaiting=awaiting;OnWorker(^{SilentWrapper();});DrainMain();Check(calls.update==0&&calls.silentOriginal==0&&calls.begin==0,@"unknown_silent_error_does_not_interrupt_pending_or_final_game_flow");}
    Reset();EHRItchAuthProviderStart();ehr_native_eos_itch_final_completed(expectedManager,expectedMethod);Check(calls.finalOriginal==1&&calls.observe==1&&[order indexOfObject:@"final-original"]<[order indexOfObject:@"observe"],@"final_observed_only_after_ordinary_original_once");
    Reset();EHRItchAuthProviderStart();SeedAttempt(@"NEW-PROFILE");NSMutableData *newProfileKey=state().attemptKey;runtimeNewPending=true;runtimeCompletions=1;resultHandler(0,3,true,false);
    Check(calls.offer==1&&calls.confirm==0&&calls.update==0&&uiConfirm!=nil,@"genuine_new_user_only_offers_explicit_action");
    Check(state().attemptKey==newProfileKey&&!Zeroed(newProfileKey)&&state().sessionKey==nil,@"new_user_choice_retains_only_pending_credential_not_session");
    Check(uiConfirm()==0&&calls.confirm==1&&calls.cancel==0,@"explicit_new_user_action_calls_checked_runtime_once");
    resultHandler(0,3,true,false);Check(calls.update==1&&uiEOS==3&&!uiFull&&state().attemptKey==newProfileKey,@"source_continuation_keeps_real_eos3_without_premature_success");
    runtimeFull=true;runtimeMigrationValidated=true;resultHandler(0,3,true,false);Check(uiFull&&uiEOS==3&&state().attemptKey==nil&&Zeroed(newProfileKey)&&state().sessionKey.length>0,@"genuine_full_endpoint_can_complete_confirmed_profile_without_faking_eos0");
    for(int provenance=0;provenance<3;++provenance){Reset();EHRItchAuthProviderStart();SeedAttempt(@"UNPROVEN-THREE");runtimeFull=true;runtimeContinued=provenance!=0;runtimeCallbackDelivered=provenance==2;resultHandler(provenance==2?7:0,3,true,false);Check(!uiFull&&state().sessionKey==nil&&state().attemptKey==nil,@"eos3_missing_continuation_delivery_or_clean_local_status_cannot_complete");}
    for(int stale=0;stale<4;++stale){Reset();EHRItchAuthProviderStart();SeedAttempt(@"STALE-CHOICE");runtimeNewPending=true;runtimeCompletions=1;resultHandler(0,3,true,false);if(stale==0)++state().captures;else if(stale==1)++state().submissions;else if(stale==2)++runtimeCompletions;else runtimeNewPending=false;Check(uiConfirm()==EHR_RUNTIME_NOT_READY&&calls.confirm==0&&calls.cancel==0,@"stale_ui_choice_cannot_act_on_a_newer_attempt");}
    Reset();EHRItchAuthProviderStart();SeedAttempt(@"CONFIRM-FAIL");newProfileKey=state().attemptKey;runtimeNewPending=true;resultHandler(0,3,true,false);fixtureConfirm=EHR_RUNTIME_UNSUPPORTED;Check(uiConfirm()==EHR_RUNTIME_UNSUPPORTED&&calls.confirm==1&&calls.cancel==1,@"rejected_creation_guard_retires_owned_runtime_choice");Check(state().attemptKey==nil&&state().sessionKey==nil&&Zeroed(newProfileKey)&&!state().savedKeyAllowed,@"rejected_creation_guard_wipes_pending_key");
    Reset();EHRItchAuthProviderStart();SeedAttempt(@"DECLINE-PROFILE");newProfileKey=state().attemptKey;runtimeNewPending=true;resultHandler(0,3,true,false);submit(nil);Check(calls.cancel==1&&calls.confirm==0&&Zeroed(newProfileKey)&&uiConfirm()==EHR_RUNTIME_NOT_READY,@"declined_new_profile_never_continues_source");
    for(int selectedProvider=0;selectedProvider<2;++selectedProvider)for(int blocked=0;blocked<2;++blocked){Reset();if(!selectedProvider)fixtureInfo=@{@"EHRItchAuthCompiled":@NO};fixtureMigration=blocked?EHR_RUNTIME_UNSUPPORTED:0;bool returned=false,raised=false;try{ehr_native_eos_itch_guest_migration(expectedManager,expectedMethod);returned=true;}catch(const std::runtime_error&){raised=true;}const bool reject=selectedProvider&&blocked;Check(calls.migrationCheck==(selectedProvider?1u:0u),@"migration_guard_only_selected_provider");Check(calls.migrationOriginal==(reject?0u:1u),@"ordinary_or_proven_empty_migration_forwards_original_once");Check(raised==reject&&returned!=reject&&calls.migrationRaise==(reject?1u:0u),@"rejected_migration_raises_and_prevents_native_caller_continuation");}
    NSDictionary *synthetic=@{@"knownCounter":@7,@"unknownNumericName":@987,@"knownSecretSlot":@"OWNED-SYNTHETIC-SECRET",@"knownNullSlot":NSNull.null,@"knownNestedSlot":@{@"private":@"OWNED-NESTED-SECRET"},@"knownArraySlot":@[@123]};
    NSDictionary *filtered=numericFields(synthetic,@[@"knownCounter",@"knownSecretSlot",@"knownNullSlot",@"knownNestedSlot",@"knownArraySlot"]);
    Check(filtered.count==1&&[filtered[@"knownCounter"] isEqual:@7],@"numeric_filter_preserves_only_explicit_known_number");
    Check(filtered[@"unknownNumericName"]==nil,@"numeric_filter_excludes_unlisted_numeric_name");
    Check(filtered[@"knownSecretSlot"]==nil,@"numeric_filter_excludes_synthetic_secret_string");
    Check(filtered[@"knownNullSlot"]==nil,@"numeric_filter_excludes_nsnull");
    Check(filtered[@"knownNestedSlot"]==nil&&filtered[@"knownArraySlot"]==nil,@"numeric_filter_excludes_nested_values");
    Check(numericFields((NSDictionary *)NSNull.null,@[@"knownCounter"]).count==0,@"numeric_filter_rejects_non_dictionary_input");
    Check(![fixtureInfo[@"EHRItchAuthDiagnosticsCacheEnabled"] boolValue],@"fixture_disk_diagnostic_optin_is_absent");
    Reset();EHRItchAuthProviderStart();presenter=Presenter();EHRItchAuthProviderSetPresenter(presenter);EHRItchAuthProviderPresentAccount();Check(calls.accountPresent==1&&!accountFull&&uiAccountClear!=nil&&uiAccountSignIn!=nil&&calls.request==0,@"unsigned_idle_account_offers_explicit_signin_without_autologin");uiAccountSignIn();Check(calls.request==0&&calls.present==1,@"account_signin_action_opens_ownership_form_before_game_checks");
    for(int busy=0;busy<4;++busy){Reset();EHRItchAuthProviderStart();presenter=Presenter();EHRItchAuthProviderSetPresenter(presenter);runtimePending=busy==0;runtimeAwaiting=busy==1;runtimeNewPending=busy==2;runtimeFull=busy==3;EHRItchAuthProviderPresentAccount();Check(uiAccountSignIn==nil&&accountFull==(busy==3),@"busy_or_full_account_cannot_start_second_login");EHRItchAuthProviderPresent();Check(calls.request==0&&calls.present==1,@"direct_present_never_interrupts_active_or_full_flow");}
    for(int changed=0;changed<5;++changed){Reset();EHRItchAuthProviderStart();presenter=Presenter();EHRItchAuthProviderSetPresenter(presenter);EHRItchAuthProviderPresentAccount();void(^oldSignIn)(void)=uiAccountSignIn;if(changed==0)runtimePending=true;else if(changed==1)runtimeAwaiting=true;else if(changed==2)runtimeNewPending=true;else if(changed==3)runtimeFull=true;else ++state().credentialEpoch;oldSignIn();Check(calls.request==0&&calls.present==1,@"account_dismissal_signin_revalidates_runtime_and_epoch");}
    Reset();EHRItchAuthProviderStart();presenter=Presenter();EHRItchAuthProviderSetPresenter(presenter);SeedAttempt(@"CLEAR-PENDING");state().sessionKey=FakeKey(@"CLEAR-SESSION");NSMutableData *clearAttempt=state().attemptKey,*clearSession=state().sessionKey;runtimeFull=true;EHRItchAuthProviderPresentAccount();Check(accountFull&&uiAccountSignIn==nil,@"full_account_settings_remain_available");Check(uiAccountClear()==0&&calls.cancel==1,@"confirmed_ui_removal_cancels_owned_auth_once");Check(Zeroed(clearAttempt)&&Zeroed(clearSession)&&state().attemptKey==nil&&state().sessionKey==nil&&!state().savedKeyAllowed&&state().clearedForRestart.load(),@"clear_wipes_both_buffers_and_freezes_for_restart");Check(state().credentialEpoch.load()==1&&state().credentialClears.load()==1,@"clear_invalidates_provider_epoch");const auto updatesBeforeClear=calls.update;runtimeFull=true;resultHandler(0,0,true,true);Check(state().sessionKey==nil&&calls.update==updatesBeforeClear,@"late_full_result_cannot_recapture_or_save_cleared_key");submit(FakeKey(@"AFTER-CLEAR"));Wrapper();SilentWrapper();state().promptRequested=true;pump();EHRItchAuthProviderPresent();Check(calls.begin==0&&calls.request==0&&calls.capture==0&&calls.captureSilent==0&&calls.guestCheck==0&&calls.saved==1&&calls.present==1&&uiAccountSignIn==nil&&!accountFull,@"cleared_process_cannot_reuse_credentials_or_restart_auth_until_reopen");
    Reset();EHRItchAuthProviderStart();presenter=Presenter();EHRItchAuthProviderSetPresenter(presenter);OnWorker(^{Wrapper();});Check(clearLocalCredential()==0,@"clear_after_queued_worker_failure");DrainMain();Check(calls.update==0&&calls.present==1,@"clear_epoch_suppresses_queued_failure_presentation");
    Reset();EHRItchAuthProviderStart();SeedAttempt(@"CLEAR-OFFER");NSMutableData *offered=state().attemptKey;runtimeNewPending=true;resultHandler(0,3,true,false);int32_t(^oldConfirm)(void)=uiConfirm;clearLocalCredential();Check(oldConfirm()==EHR_RUNTIME_NOT_READY&&calls.confirm==0&&Zeroed(offered),@"clear_retires_old_new_profile_confirmation");
    Reset();EHRItchAuthProviderStart();OnWorker(^{Check(clearLocalCredential()==EHR_RUNTIME_WRONG_THREAD,@"worker_clear_rejected");EHRItchAuthProviderPresentAccount();});Check(calls.cancel==0&&calls.accountPresent==0&&!state().clearedForRestart.load(),@"worker_cannot_clear_credentials_or_present_account");
    Reset();savedKey=FakeKey(@"EARLY-PRESENTER");fixturePrepare=EHR_RUNTIME_NOT_READY;UIViewController *earlyPresenter=Presenter();EHRItchAuthProviderSetPresenter(earlyPresenter);
    Check(calls.saved==0&&ownershipStarts==0&&!state().initialCredentialChecked,@"early_presenter_waits_for_metadata_without_keychain_or_network");fixturePrepare=0;deferOwnership=true;pump();
    Check(calls.saved==1&&ownershipStarts==1&&state().initialCredentialChecked&&state().ownershipPending.load()&&calls.request==0&&calls.begin==0,@"visible_pump_retries_bootstrap_after_metadata_ready");
    // Ownership is a separate licensing prerequisite. The transport here is
    // an owned completion queue: no account, API request or credential is used.
    Reset();EHRItchAuthProviderStart();deferOwnership=true;reenterRequest=true;neutralDuringCapture=true;
    NSMutableData *ownedInput=FakeKey(@"ASYNC-ORDER");submit(ownedInput);
    Check(ownershipStarts==1&&calls.request==0&&calls.begin==0&&state().ownershipPending.load()&&!EHRItchAuthProviderOwnershipVerified()&&!EHRItchAuthProviderDirectoryAllowed(),@"no_game_login_before_ownership_completion");
    ownershipCallbacks[0](EHRItchOwnershipVerified,200);
    Check(calls.request==1&&calls.capture==1&&calls.begin==1&&[runtimeKey isEqualToData:ownedInput],@"owned_callback_enters_original_game_flow_for_same_key");
    Check([order indexOfObject:@"ownership"]<[order indexOfObject:@"verified"]&&[order indexOfObject:@"verified"]<[order indexOfObject:@"request"]&&[order indexOfObject:@"capture"]<[order indexOfObject:@"begin"],@"ownership_precedes_outer_game_checks_and_eos");
    Check(EHRItchAuthProviderOwnershipVerified()&&!EHRItchAuthProviderDirectoryAllowed(),@"ownership_can_uncover_native_consent_but_not_directory");
    const auto authCount=calls.begin;ownershipCallbacks[0](EHRItchOwnershipVerified,200);Check(calls.begin==authCount,@"duplicate_ownership_callback_cannot_start_second_eos");
    runtimeFull=true;resultHandler(0,0,true,true);Check(EHRItchAuthProviderDirectoryAllowed(),@"directory_requires_owned_same_key_actual_full_result");
    NSMutableData *goodSession=state().sessionKey;state().sessionKey=FakeKey(@"DIFFERENT-IDENTITY");Check(!EHRItchAuthProviderDirectoryAllowed(),@"directory_rejects_mismatched_credential");state().sessionKey=goodSession;
    runtimeFull=false;Check(!EHRItchAuthProviderDirectoryAllowed(),@"directory_tracks_actual_game_completion");runtimeFull=true;
    OnWorker(^{Check(!EHRItchAuthProviderOwnershipVerified()&&!EHRItchAuthProviderDirectoryAllowed(),@"ownership_and_directory_readers_fail_closed_off_main");});
    fixtureInfo=@{@"EHRItchAuthCompiled":@NO};Check(!EHRItchAuthProviderOwnershipVerified()&&!EHRItchAuthProviderDirectoryAllowed(),@"selection_required_for_both_licenses_and_directory");
    for(int status=1;status<=11;++status){
        Reset();EHRItchAuthProviderStart();deferOwnership=true;runtimeCaptured=true;state().sessionKey=FakeKey(@"FAILED-OLD-SESSION");NSMutableData *oldSession=state().sessionKey;submit(FakeKey(@"FAILED-CHECK"));NSMutableData *failedAttempt=state().attemptKey;
        ownershipCallbacks[0]((EHRItchOwnershipStatus)status,status==2?401:status==3?403:status==8?503:200);
        Check(calls.begin==0&&calls.request==0&&calls.cancel==1&&!EHRItchAuthProviderOwnershipVerified()&&!EHRItchAuthProviderDirectoryAllowed(),@"all_ownership_failure_classes_block_eos_and_directory");
        Check(state().ownershipStatus.load()==status&&!state().ownershipPending.load()&&state().attemptKey==nil&&state().sessionKey==nil&&Zeroed(failedAttempt)&&Zeroed(oldSession),@"failed_check_retires_credential_and_preserves_numeric_reason");
        const auto updates=calls.update;runtimeFull=true;resultHandler(0,0,true,true);Check(calls.update==updates&&state().sessionKey==nil,@"unowned_late_game_success_cannot_save_or_complete");
    }
    for(int cancellation=0;cancellation<2;++cancellation){
        Reset();EHRItchAuthProviderStart();deferOwnership=true;submit(FakeKey(@"CANCEL-DEFERRED"));NSMutableData *pending=state().attemptKey;
        if(cancellation)clearLocalCredential();else submit(nil);
        const auto updates=ownershipUpdates;ownershipCallbacks[0](EHRItchOwnershipVerified,200);
        Check(calls.begin==0&&calls.request==0&&ownershipUpdates==updates&&!EHRItchAuthProviderOwnershipVerified()&&!EHRItchAuthProviderDirectoryAllowed()&&Zeroed(pending),@"cancel_or_clear_fences_late_owned_completion");
        Check(ownershipCancels>=1&&!state().ownershipPending.load(),@"cancel_or_clear_cancels_owned_transport");
    }
    Reset();EHRItchAuthProviderStart();deferOwnership=true;runtimeCaptured=true;submit(FakeKey(@"OLD-ASYNC"));NSMutableData *superseded=state().attemptKey;NSMutableData *newInput=FakeKey(@"NEW-ASYNC");submit(newInput);
    ownershipCallbacks[0](EHRItchOwnershipVerified,200);Check(calls.begin==0&&state().ownershipPending.load()&&!EHRItchAuthProviderOwnershipVerified()&&Zeroed(superseded),@"old_key_proof_cannot_authorize_new_key");
    ownershipCallbacks[1](EHRItchOwnershipVerified,200);Check(calls.begin==1&&[runtimeKey isEqualToData:newInput]&&EHRItchAuthProviderOwnershipVerified(),@"new_attempt_uses_own_verification_only");
    Reset();EHRItchAuthProviderStart();deferOwnership=true;runtimeCaptured=true;submit(FakeKey(@"IDENTITY-BIND"));state().attemptKey=FakeKey(@"REPLACED-WITHOUT-SERIAL");ownershipCallbacks[0](EHRItchOwnershipVerified,200);Check(calls.begin==0&&!EHRItchAuthProviderOwnershipVerified(),@"check_also_binds_current_key_object_identity");
    Reset();EHRItchAuthProviderStart();runtimeCaptured=true;submit(FakeKey(@"LICENSE-WITH-NATIVE-FAILURE"));resultHandler(0,7000,true,false);Check(EHRItchAuthProviderOwnershipVerified()&&!EHRItchAuthProviderDirectoryAllowed()&&state().attemptKey==nil&&state().sessionKey==nil,@"native_auth_failure_preserves_only_same_identity_license_proof");
    for(int silent=0;silent<2;++silent){
        Reset();EHRItchAuthProviderStart();runtimeCaptured=true;submit(FakeKey(@"RENEW-RECHECK"));runtimeFull=true;resultHandler(0,0,true,true);Check(EHRItchAuthProviderDirectoryAllowed(),@"renewal_starts_from_actual_owned_complete_session");
        deferOwnership=true;const auto checksBefore=ownershipStarts,beginBefore=calls.begin;runtimeFull=false;runtimePending=false;if(silent)SilentWrapper();else Wrapper();
        Check(ownershipStarts==checksBefore+1&&calls.begin==beginBefore&&state().ownershipPending.load()&&!EHRItchAuthProviderOwnershipVerified()&&!EHRItchAuthProviderDirectoryAllowed(),@"normal_and_silent_renewal_both_recheck_ownership");
        ownershipCallbacks[0](EHRItchOwnershipNoEntitlement,200);Check(calls.begin==beginBefore&&state().sessionKey==nil&&!EHRItchAuthProviderDirectoryAllowed(),@"renewal_entitlement_rejection_cannot_reuse_prior_proof");
    }
    Reset();savedKey=FakeKey(@"BOOTSTRAP-SAVED");EHRItchAuthProviderStart();Check(calls.saved==0&&ownershipStarts==0,@"passive_startup_never_reads_even_available_saved_key");deferOwnership=true;UIViewController *licensePresenter=Presenter();EHRItchAuthProviderSetPresenter(licensePresenter);fixtureGuest=true;SilentWrapper();
    Check(calls.saved==1&&ownershipStarts==1&&calls.silentOriginal==0&&calls.begin==0&&state().ownershipPending.load(),@"saved_license_preflight_precedes_guest_silent_shortcut");ownershipCallbacks[0](EHRItchOwnershipVerified,200);SilentWrapper();Check(calls.silentOriginal==1&&EHRItchAuthProviderOwnershipVerified()&&!EHRItchAuthProviderDirectoryAllowed(),@"owned_license_allows_native_guest_without_claiming_full_eos_completion");
    EHRItchAuthProviderSetPresenter(licensePresenter);Check(calls.saved==1&&ownershipStarts==1,@"visible_presenter_bootstrap_is_once_per_process");
    Reset();EHRItchAuthProviderStart();deferOwnership=true;submit(FakeKey(@"DIAGNOSTICS-CURRENT"));EHRItchOwnershipCheck *diagnosticHandle=state().ownershipCheck;
    ownershipCallbacks[0](EHRItchOwnershipMalformedResponse,200);NSDictionary *structure=EHRItchAuthProviderCopyStatus()[@"ownershipResponse"];
    Check(diagnosticHandle!=nil&&state().ownershipCheck==nil&&structure.count==16&&[structure[@"parserStage"] intValue]==25&&[structure[@"ownedKeysKind"] intValue]==3,@"current_check_structural_diagnostics_copied_before_handle_retirement");
    for(id value in structure.allValues)Check([value isKindOfClass:NSNumber.class],@"ownership_response_numeric_fields_only");
    Check(structure[@"unexpectedString"]==nil&&structure[@"unexpectedNumber"]==nil&&structure[@"unexpectedBody"]==nil&&![[structure description] containsString:@"REDACTION-SECRET"],@"structural_cache_excludes_unlisted_text_numbers_and_nested_content");
    submit(FakeKey(@"DIAGNOSTICS-NEW"));Check([EHRItchAuthProviderCopyStatus()[@"ownershipResponse"] count]==0,@"new_check_resets_previous_response_diagnostics");ownershipCallbacks[0](EHRItchOwnershipVerified,200);Check([EHRItchAuthProviderCopyStatus()[@"ownershipResponse"] count]==0,@"old_completion_cannot_publish_response_diagnostics_for_new_check");
    // Only a remembered bootstrap with no form can wait through an early
    // outer-login failure; timers never call the game's login method again.
    Reset();savedKey=FakeKey(@"DEFER-SAVED");fixtureRequest=EHR_RUNTIME_MANAGED_EXCEPTION;UIViewController *deferPresenter=Presenter();EHRItchAuthProviderSetPresenter(deferPresenter);NSMutableData *deferredKey=state().attemptKey;
    Check(state().awaitingNativeLogin.load()&&state().savedBootstrapAttempt&&state().savedKeyAllowed&&proofForAttempt()&&calls.request==1&&calls.begin==0&&calls.update==0&&calls.present==0,@"early_saved_no_form_failure_preserves_one_verified_attempt");
    NSDictionary *waiting=EHRItchAuthProviderCopyStatus();Check([waiting[@"awaitingNativeLogin"] boolValue]&&[waiting[@"nativeLoginWaitSeconds"] intValue]>0&&[waiting[@"nativeLoginWaitSeconds"] intValue]<=120&&!EHRItchAuthProviderDirectoryAllowed(),@"deferred_numeric_status_bounded_and_directory_still_denied");
    pump();pump();Check(calls.request==1&&state().attemptKey==deferredKey,@"timer_pump_never_retries_outer_login");
    SilentWrapper();Check(calls.captureSilent==0&&calls.begin==0&&calls.request==1&&state().awaitingNativeLogin.load(),@"initial_saved_wait_cannot_consume_cached_proof_through_silent_adapter");fixtureGuestStatus=EHR_RUNTIME_NOT_READY;SilentWrapper();Check(calls.update==0&&state().attemptKey==deferredKey&&state().awaitingNativeLogin.load(),@"startup_silent_readiness_error_does_not_end_no_form_wait_or_retry_login");fixtureGuestStatus=0;
    Wrapper();Check(calls.capture==1&&calls.begin==1&&[runtimeKey isEqualToData:deferredKey]&&!state().awaitingNativeLogin.load()&&ownershipStarts==1&&calls.request==1,@"genuine_normal_capture_consumes_retained_proof_once");
    Check([EHRItchAuthProviderCopyStatus()[@"nativeLoginWaitSeconds"] intValue]==0&&!EHRItchAuthProviderDirectoryAllowed(),@"consumed_wait_is_not_premature_full_completion");runtimeFull=true;resultHandler(0,0,true,true);Check(EHRItchAuthProviderDirectoryAllowed()&&Zeroed(deferredKey),@"deferred_attempt_directory_requires_real_full_result");
    Reset();savedKey=FakeKey(@"DEFER-EXPLICIT");fixtureRequest=EHR_RUNTIME_MANAGED_EXCEPTION;deferPresenter=Presenter();EHRItchAuthProviderSetPresenter(deferPresenter);const auto originalDeadline=state().nativeLoginDeadline.load();deferredKey=state().attemptKey;EHRItchAuthProviderPresentAccount();Check(uiAccountSignIn!=nil&&calls.request==1,@"deferred_account_settings_offer_explicit_action_only");uiAccountSignIn();Check(calls.request==2&&calls.present==0&&state().attemptKey==deferredKey&&state().nativeLoginDeadline.load()==originalDeadline&&state().awaitingNativeLogin.load(),@"explicit_account_action_retries_once_without_new_form_or_extended_deadline");
    fixtureRequest=0;reenterRequest=true;EHRItchAuthProviderPresent();Check(calls.request==3&&calls.capture==1&&calls.begin==1&&calls.present==0&&!state().awaitingNativeLogin.load(),@"later_explicit_action_reenters_original_checks_and_consumes_wait");
    for(int retirement=0;retirement<4;++retirement){
        Reset();savedKey=FakeKey(@"DEFER-RETIRE");fixtureRequest=EHR_RUNTIME_MANAGED_EXCEPTION;deferPresenter=Presenter();EHRItchAuthProviderSetPresenter(deferPresenter);deferredKey=state().attemptKey;
        if(retirement==0)submit(nil);else if(retirement==1)clearLocalCredential();else if(retirement==2){fixtureRequest=0;submit(FakeKey(@"REPLACEMENT-ATTEMPT"));}else{state().nativeLoginDeadline.store(NSProcessInfo.processInfo.systemUptime-1);pump();}
        Check(!state().awaitingNativeLogin.load()&&Zeroed(deferredKey),@"cancel_clear_new_submission_or_expiry_retires_deferred_bytes");
        if(retirement==3){Check(EHRItchAuthProviderOwnershipVerified()&&state().attemptKey==nil&&!state().savedKeyAllowed&&calls.request==1,@"expiry_preserves_license_but_never_reuses_expired_auth_attempt");Wrapper();Check(calls.begin==0&&calls.request==1,@"post_expiry_normal_capture_cannot_use_stale_proof_to_authenticate");}
    }
    for(int entry=0;entry<2;++entry){
        Reset();savedKey=FakeKey(@"DEFER-LATE-ENTRY");fixtureRequest=EHR_RUNTIME_MANAGED_EXCEPTION;deferPresenter=Presenter();EHRItchAuthProviderSetPresenter(deferPresenter);deferredKey=state().attemptKey;state().nativeLoginDeadline.store(NSProcessInfo.processInfo.systemUptime-1);
        if(entry)EHRItchAuthProviderPresent();else Wrapper();Check(Zeroed(deferredKey)&&!state().awaitingNativeLogin.load()&&calls.begin==0&&calls.request==1,@"entry_checks_deadline_even_before_timer_has_run");
    }
    Reset();savedKey=FakeKey(@"DEFER-CAPTURE-FAIL");fixtureRequest=EHR_RUNTIME_MANAGED_EXCEPTION;deferPresenter=Presenter();EHRItchAuthProviderSetPresenter(deferPresenter);deferredKey=state().attemptKey;fixtureCapture=EHR_RUNTIME_TYPE_MISMATCH;Wrapper();Check(Zeroed(deferredKey)&&state().attemptKey==nil&&!state().awaitingNativeLogin.load(),@"normal_capture_failure_retires_retained_key_before_terminal_ui");DrainMain();Check(calls.update==1&&calls.begin==0,@"deferred_capture_failure_reports_terminal_failure_without_background_eos");
    // Every eligibility boundary must fail closed rather than caching a retry.
    for(int changed=0;changed<12;++changed){
        Reset();savedKey=FakeKey(@"DEFER-ACTIVITY-GUARD");fixtureRequest=EHR_RUNTIME_MANAGED_EXCEPTION;
        requestSideEffect=^{switch(changed){case 0:++state().captures;break;case 1:++runtimeSDKCalls;break;case 2:runtimeCaptured=true;break;case 3:runtimePending=true;break;case 4:runtimeAwaiting=true;break;case 5:runtimeNewPending=true;break;case 6:runtimeFull=true;break;case 7:runtimeResultKnown=true;break;case 8:++runtimeCompletions;break;case 9:fixtureUIVisible=true;break;case 10:fixtureUIBusy=true;break;case 11:state().presenting=true;break;}};
        deferPresenter=Presenter();EHRItchAuthProviderSetPresenter(deferPresenter);Check(!state().awaitingNativeLogin.load()&&state().attemptKey==nil&&calls.update==1,@"capture_sdk_runtime_or_ui_activity_prevents_saved_deferral");
    }
    Reset();EHRItchAuthProviderStart();fixtureRequest=EHR_RUNTIME_MANAGED_EXCEPTION;fixtureUIVisible=true;submit(FakeKey(@"MANUAL-TERMINAL"));Check(!state().awaitingNativeLogin.load()&&state().attemptKey==nil&&calls.update==1,@"manual_visible_form_retains_existing_terminal_cleanup");
    Reset();savedKey=FakeKey(@"DEFER-REENTRANT-OLD");fixtureRequest=EHR_RUNTIME_MANAGED_EXCEPTION;__block NSMutableData *replacement=nil;
    requestSideEffect=^{requestSideEffect=nil;replacement=FakeKey(@"DEFER-REENTRANT-NEW");fixtureRequest=0;submit(replacement);fixtureRequest=EHR_RUNTIME_MANAGED_EXCEPTION;};deferPresenter=Presenter();EHRItchAuthProviderSetPresenter(deferPresenter);
    Check([state().attemptKey isEqualToData:replacement]&&!state().savedBootstrapAttempt&&!state().awaitingNativeLogin.load()&&calls.update==0,@"old_outer_error_cannot_retire_a_reentrant_new_attempt");
    NSDictionary *snapshot=EHRItchAuthProviderCopyStatus();Check(snapshot.count==23,@"provider_snapshot_bounded");for(id value in snapshot.allValues)Check([value isKindOfClass:NSNumber.class]||[value isKindOfClass:NSDictionary.class],@"snapshot_numeric_or_fixed_nested_only");Check(![[snapshot description] containsString:@"OWNED-FAKE"],@"snapshot_never_contains_credential");[state().timer invalidate];wipe(state().attemptKey);wipe(state().sessionKey);
    NSDictionary *proof=@{@"schema":@"ehr.itch-provider-owned-proof.v1",@"success":@(failures.count==0),@"checks":@(checks),@"failures":failures,@"actualProviderCompiled":@YES,@"numericFilterChecks":@7,@"runtimeAndUIKitStubbed":@YES,@"networkRequests":@0,@"keychainOperations":@0,@"gameCalls":@0,@"accountActions":@0,@"actualCredentialsRead":@0};NSData *output=[NSJSONSerialization dataWithJSONObject:proof options:NSJSONWritingSortedKeys error:nil];puts([[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding].UTF8String);return failures.count?1:0;
}}
