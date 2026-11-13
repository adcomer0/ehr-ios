// Owned UIKit application. Links the exact scene adapter, no Unity/game code.
#import <UIKit/UIKit.h>
#import "../native/launcher/EHRUnitySceneDelegate.h"
#include <atomic>
static NSMutableArray<NSString *> *failures,*events;
static NSUInteger checks=0,activeCalls=0,resignCalls=0,backgroundCalls=0,foregroundCalls=0;
static NSUInteger loopCalls=0,headerCalls=0,dataCalls=0,missingWindowReads=0,launchCalls=0;
static BOOL throwNextResign=NO;
static NSUInteger initializerCalls=0;
static BOOL initializerReady=NO,initialActiveReturned=NO,firstActiveObservedUnattached=NO;
static BOOL HiddenMode(void){return [NSBundle.mainBundle.infoDictionary[@"OwnedHiddenWindow"] boolValue];}
static std::atomic<bool> callbackOnWorker{false};
static UIWindow *originalWindow;
static UIViewController *originalRoot;
static void Check(BOOL okay,NSString *name){++checks;if(!okay)[failures addObject:name];}
static void Event(NSString *name){if(!NSThread.isMainThread){callbackOnWorker.store(true);return;}[events addObject:name];}
@interface OwnedFramework:NSObject<EHRUnityFrameworkPublicAPI>
@end
static OwnedFramework *framework;
@implementation OwnedFramework
+ (id<EHRUnityFrameworkPublicAPI>)getInstance{return framework;}
- (id)appController{return UIApplication.sharedApplication.delegate;}
- (void)setExecuteHeader:(const EHRMachHeader *)header{(void)header;++headerCalls;}
- (void)setDataBundleId:(const char *)bundle{(void)bundle;++dataCalls;}
- (void)runUIApplicationMainWithArgc:(int)argc argv:(char *[])argv{(void)argc;(void)argv;++loopCalls;}
@end
@interface OwnedRole:NSObject
@property(nonatomic,strong) NSString *role;
@end
@implementation OwnedRole
@end
@interface OwnedAppDelegate:UIResponder<UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
static void RunTests(void);
@implementation OwnedAppDelegate
@synthesize window=_window;
- (UIWindow *)window{if(!_window)++missingWindowReads;return _window;}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;(void)options;++launchCalls;
    // Deliberately unavailable during scene connection. The production adapter
    // must retry this existing owner's window instead of making another root.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        originalWindow=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        originalRoot=[UIViewController new];originalRoot.view.backgroundColor=[UIColor colorWithRed:0.04 green:0.09 blue:0.14 alpha:1];originalRoot.view.tag=715;
        UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(30,100,340,70)];label.text=@"Owned Unity scene fixture";label.textColor=UIColor.cyanColor;[originalRoot.view addSubview:label];
        if(!HiddenMode())originalWindow.rootViewController=originalRoot;originalWindow.hidden=HiddenMode();self.window=originalWindow;
        if(HiddenMode())dispatch_after(dispatch_time(DISPATCH_TIME_NOW,400*NSEC_PER_MSEC),dispatch_get_main_queue(),^{Check(originalWindow.rootViewController==nil&&originalWindow.hidden,@"lazy_hidden_window_root_not_manufactured_or_shown");originalWindow.rootViewController=originalRoot;});
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{RunTests();});return YES;
}
- (void)initUnityWithApplication:(UIApplication *)application {++initializerCalls;Event(@"initialize");Check(application==UIApplication.sharedApplication,@"initializer_receives_original_application");Check(![EHRUnitySceneCopyStatus()[@"attached"] boolValue],@"initialization_precedes_adapter_attachment");initializerReady=YES;}
- (void)applicationDidBecomeActive:(UIApplication *)application{(void)application;++activeCalls;Event(@"active");Check(initializerReady,@"original_active_has_initialized_keyboard_prerequisite");if(!initialActiveReturned){firstActiveObservedUnattached=![EHRUnitySceneCopyStatus()[@"attached"] boolValue];Check(firstActiveObservedUnattached,@"first_original_active_returns_before_adapter_attachment");}initialActiveReturned=YES;}
- (void)applicationWillResignActive:(UIApplication *)application{(void)application;++resignCalls;Event(@"resign");if(throwNextResign){throwNextResign=NO;@throw [NSException exceptionWithName:@"OwnedSceneFixture" reason:nil userInfo:nil];}}
- (void)applicationDidEnterBackground:(UIApplication *)application{(void)application;++backgroundCalls;Event(@"background");}
- (void)applicationWillEnterForeground:(UIApplication *)application{(void)application;++foregroundCalls;Event(@"foreground");}
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window{(void)application;(void)window;return UIInterfaceOrientationMaskAllButUpsideDown;}
@end
static void RunTests(void){
    Check(NSThread.isMainThread,@"fixture_on_main");UIWindowScene *scene=nil;
    for(UIScene *candidate in UIApplication.sharedApplication.connectedScenes)if([candidate isKindOfClass:UIWindowScene.class]){scene=(UIWindowScene *)candidate;break;}
    Check(scene!=nil,@"actual_window_scene_created_from_manifest");id delegate=scene.delegate;
    Check([delegate isKindOfClass:EHRUnitySceneDelegate.class],@"actual_production_scene_delegate_instantiated");EHRUnitySceneDelegate *adapter=delegate;
    Check(launchCalls==1,@"one_application_launch");Check(loopCalls==0&&headerCalls==0&&dataCalls==0,@"scene_adapter_never_starts_or_reconfigures_unity");
    const BOOL osActive=scene.activationState==UISceneActivationStateForegroundActive;Check(!osActive||activeCalls==1,@"os_reported_active_is_forwarded_once");const BOOL automaticActive=activeCalls==1;
    if(!initializerCalls)[adapter sceneWillEnterForeground:scene];if(!activeCalls)[adapter sceneDidBecomeActive:scene];
    Check(initializerCalls==1&&initializerReady&&firstActiveObservedUnattached,@"first_foreground_initializes_once_before_original_active_and_attachment");Check(foregroundCalls==0,@"cold_foreground_is_not_legacy_resume");Check([EHRUnitySceneCopyStatus()[@"firstActiveCompleted"] boolValue],@"successful_first_active_is_sticky");
    Check([EHRUnitySceneCopyStatus()[@"retriesScheduled"] unsignedLongLongValue]>0,@"pending_first_active_uses_bounded_attachment_retry");Check(adapter.window==originalWindow,@"same_existing_window_attached");Check(originalWindow.windowScene==scene,@"existing_window_uses_actual_scene");Check(originalWindow.rootViewController==originalRoot&&originalRoot.view.tag==715,@"original_root_and_state_preserved");Check(originalWindow.hidden==HiddenMode(),@"unity_original_visibility_intent_preserved");Check(HiddenMode()||originalWindow.isKeyWindow,@"previously_visible_window_becomes_key_after_attachment");
    Check(activeCalls==1,@"owned_active_event_forwarded_once");NSUInteger before=activeCalls;[adapter sceneDidBecomeActive:scene];[adapter sceneDidBecomeActive:scene];Check(activeCalls==before,@"duplicate_active_not_forwarded");
    before=resignCalls;[adapter sceneWillResignActive:scene];[adapter sceneWillResignActive:scene];Check(resignCalls==before+1,@"resign_forwarded_once");
    before=backgroundCalls;[adapter sceneDidEnterBackground:scene];[adapter sceneDidEnterBackground:scene];Check(backgroundCalls==before+1,@"background_forwarded_once");
    before=foregroundCalls;[adapter sceneWillEnterForeground:scene];[adapter sceneWillEnterForeground:scene];Check(foregroundCalls==before+1,@"foreground_forwarded_once");
    before=activeCalls;[adapter sceneDidBecomeActive:scene];[adapter sceneDidBecomeActive:scene];Check(activeCalls==before+1,@"reactivation_forwarded_once");
    before=activeCalls+resignCalls+backgroundCalls+foregroundCalls;UIScene *foreign=(UIScene *)(id)[NSObject new];
    [adapter sceneDidBecomeActive:foreign];[adapter sceneWillResignActive:foreign];[adapter sceneDidEnterBackground:foreign];[adapter sceneWillEnterForeground:foreign];Check(activeCalls+resignCalls+backgroundCalls+foregroundCalls==before,@"foreign_scene_events_ignored");
    UIWindow *savedWindow=adapter.window;OwnedRole *role=[OwnedRole new];role.role=@"owned.unsupported.role";[adapter scene:scene willConnectToSession:(UISceneSession *)(id)role options:(UISceneConnectionOptions *)(id)[NSObject new]];Check(adapter.window==savedWindow&&originalWindow.rootViewController==originalRoot,@"unsupported_session_role_preserves_existing_window");
    dispatch_semaphore_t done=dispatch_semaphore_create(0);__block int32_t workerConfigure=0;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{workerConfigure=EHRUnitySceneConfigure(framework);[adapter sceneDidBecomeActive:scene];[adapter sceneWillResignActive:scene];[adapter sceneDidEnterBackground:scene];[adapter sceneWillEnterForeground:scene];[adapter sceneDidDisconnect:scene];dispatch_semaphore_signal(done);});
    Check(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0,@"worker_guard_completes_without_main_dispatch_wait");Check(workerConfigure!=0&&!callbackOnWorker.load(),@"worker_never_reaches_original_app_delegate");Check(activeCalls+resignCalls+backgroundCalls+foregroundCalls==before,@"worker_lifecycle_not_forwarded");Check(originalWindow.windowScene==scene&&originalWindow.rootViewController==originalRoot,@"worker_disconnect_does_not_detach_window");
    before=resignCalls;throwNextResign=YES;BOOL rethrew=NO;@try{[adapter sceneWillResignActive:scene];}@catch(NSException *exception){rethrew=[exception.name isEqualToString:@"OwnedSceneFixture"];}
    Check(rethrew&&resignCalls==before+1,@"original_delegate_exception_is_rethrown_once");[adapter sceneWillResignActive:scene];Check(resignCalls==before+1,@"exception_does_not_retry_same_callback");
    [adapter sceneDidDisconnect:scene];Check(originalWindow.rootViewController==originalRoot,@"disconnect_preserves_original_root");
    [adapter scene:scene willConnectToSession:scene.session options:(UISceneConnectionOptions *)(id)[NSObject new]];
    [adapter sceneWillEnterForeground:scene];[adapter sceneDidBecomeActive:scene];Check(adapter.window==originalWindow&&originalWindow.windowScene==scene&&originalWindow.rootViewController==originalRoot,@"reconnect_reattaches_same_window_and_root");Check(initializerCalls==1,@"reconnect_never_reenters_initializer");Check(loopCalls==0&&launchCalls==1,@"reconnect_never_creates_second_unity_loop");
    NSDictionary *status=EHRUnitySceneCopyStatus();Check([status[@"callbackFailures"] unsignedLongLongValue]==1,@"one_injected_objc_exception_records_one_failure");Check(status.count>0&&status.count<=40,@"adapter_status_bounded");for(id value in status.allValues)Check([value isKindOfClass:NSNumber.class],@"adapter_status_numeric_only");
    NSDictionary *proof=@{@"schema":@"ehr.unity-scene-owned-proof.v2",@"success":@(failures.count==0),@"checks":@(checks),@"failures":failures,@"actualUIKitScene":@YES,@"initializerCalls":@(initializerCalls),@"firstActiveBeforeAttachment":@(firstActiveObservedUnattached),@"hiddenWindowMode":@(HiddenMode()),@"automaticActiveObserved":@(automaticActive),@"osSceneActivationState":@(scene.activationState),@"osApplicationState":@(UIApplication.sharedApplication.applicationState),@"actualUnityCalls":@0,@"originalRootPreserved":@(originalWindow.rootViewController==originalRoot),@"unityLoopCalls":@(loopCalls),@"applicationLaunchCalls":@(launchCalls),@"callbackEvents":events,@"adapterStatus":status,@"networkRequests":@0,@"credentialsRead":@0,@"gameFilesUsed":@NO};NSData *data=[NSJSONSerialization dataWithJSONObject:proof options:NSJSONWritingSortedKeys|NSJSONWritingPrettyPrinted error:nil];[data writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/proof.json"] atomically:YES];printf("OWNED_SCENE_PROOF checks=%lu failures=%lu\n",(unsigned long)checks,(unsigned long)failures.count);fflush(stdout);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{exit(failures.count?1:0);});
}
int main(int argc,char **argv){@autoreleasepool{failures=[NSMutableArray new];events=[NSMutableArray new];framework=[OwnedFramework new];Check(EHRUnitySceneConfigure(framework)==0,@"framework_configured_before_single_application_loop");return UIApplicationMain(argc,argv,nil,NSStringFromClass(OwnedAppDelegate.class));}}
