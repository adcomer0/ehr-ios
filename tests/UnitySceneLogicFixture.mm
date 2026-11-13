// Exact scene-adapter TU with owned Foundation/UIKit-shaped collaborators.
// No simulator, game, engine, network, account or real window is involved.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../native/launcher/EHRUnitySceneDelegate.h"
#include <cstring>
static NSUInteger checks=0,initializerCalls=0,activeCalls=0,resignCalls=0,foregroundCalls=0,backgroundCalls=0,loops=0;
static NSUInteger windowReads=0,sceneWrites=0,keyCalls=0;
static BOOL initialized=NO,activeReturned=NO,throwInitializer=NO,throwActive=NO,exposeDelegate=YES,enforceOrdering=YES;
static NSUInteger sceneBaseline=0,keyBaseline=0;
static NSMutableArray<NSString *> *failures,*events;
static UIWindow *originalWindow;
static UIViewController *originalRoot;
static void Check(BOOL okay,NSString *name){++checks;if(!okay)[failures addObject:name];}
NSString *const UIWindowSceneSessionRoleApplication=@"UIWindowSceneSessionRoleApplication";
@implementation UIResponder
@end
@implementation UIViewController
@end
@implementation UISceneSession
@end
@implementation UISceneConnectionOptions
@end
@implementation UIScene
@end
@implementation UIWindowScene
@end
@implementation UIApplication
+ (instancetype)sharedApplication {static UIApplication *app=[UIApplication new];return app;}
@end
@implementation UIWindow
@synthesize windowScene=_windowScene;
- (void)setWindowScene:(UIWindowScene *)scene {++sceneWrites;if(enforceOrdering)Check(activeReturned,@"adapter_scene_assignment_waits_for_successful_original_active");_windowScene=scene;}
- (void)makeKeyAndVisible {++keyCalls;if(enforceOrdering)Check(activeReturned,@"adapter_key_work_waits_for_successful_original_active");self.hidden=NO;self.keyWindow=YES;}
@end
@interface OwnedController:NSObject<UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
- (void)initUnityWithApplication:(UIApplication *)application;
@end
@implementation OwnedController
@synthesize window=_window;
- (UIWindow *)window {++windowReads;if(enforceOrdering)Check(activeReturned,@"adapter_window_getter_waits_for_successful_original_active");return _window;}
- (void)initUnityWithApplication:(UIApplication *)application {
    ++initializerCalls;[events addObject:@"initialize"];Check(application==UIApplication.sharedApplication,@"initializer_receives_existing_application");Check(![EHRUnitySceneCopyStatus()[@"attached"] boolValue]&&sceneWrites==sceneBaseline&&keyCalls==keyBaseline,@"initializer_runs_without_adapter_window_work");
    if(throwInitializer)@throw [NSException exceptionWithName:@"OwnedInitializer" reason:nil userInfo:nil];initialized=YES;
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;++activeCalls;[events addObject:@"active"];Check(initialized,@"original_active_requires_completed_initializer");if(!activeReturned)Check(![EHRUnitySceneCopyStatus()[@"attached"] boolValue]&&sceneWrites==sceneBaseline&&keyCalls==keyBaseline,@"first_active_observes_no_adapter_attachment_or_key_work");
    if(throwActive)@throw [NSException exceptionWithName:@"OwnedActive" reason:nil userInfo:nil];activeReturned=YES;
}
- (void)applicationWillResignActive:(UIApplication *)application {(void)application;++resignCalls;[events addObject:@"resign"];}
- (void)applicationWillEnterForeground:(UIApplication *)application {(void)application;++foregroundCalls;[events addObject:@"foreground"];}
- (void)applicationDidEnterBackground:(UIApplication *)application {(void)application;++backgroundCalls;[events addObject:@"background"];}
@end
@interface OwnedBadController:NSObject<UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation OwnedBadController
- (id)initUnityWithApplication:(UIApplication *)application {(void)application;return self;}
@end
@interface OwnedFramework:NSObject<EHRUnityFrameworkPublicAPI>
@end
@implementation OwnedFramework
+ (id<EHRUnityFrameworkPublicAPI>)getInstance{return nil;}
- (id)appController{return exposeDelegate?UIApplication.sharedApplication.delegate:nil;}
- (void)setExecuteHeader:(const EHRMachHeader *)header {(void)header;++loops;}
- (void)setDataBundleId:(const char *)bundle {(void)bundle;++loops;}
- (void)runUIApplicationMainWithArgc:(int)argc argv:(char *[])argv {(void)argc;(void)argv;++loops;}
@end
static uint64_t Metric(NSString *name){return [EHRUnitySceneCopyStatus()[name] unsignedLongLongValue];}
int main(int argc,char **argv){@autoreleasepool{
    NSString *scenario=argc==2?[NSString stringWithUTF8String:argv[1]]:@"normal";failures=[NSMutableArray new];events=[NSMutableArray new];
    BOOL hidden=[scenario isEqualToString:@"hidden"],preassociated=[scenario isEqualToString:@"preassociated"],bad=[scenario isEqualToString:@"wrong-abi"],late=[scenario isEqualToString:@"late-controller"];
    throwInitializer=[scenario isEqualToString:@"initializer-throw"];throwActive=[scenario isEqualToString:@"active-throw"];
    originalRoot=[UIViewController new];originalWindow=[UIWindow new];originalWindow.hidden=hidden;originalWindow.rootViewController=originalRoot;
    id controller=bad?(id)[OwnedBadController new]:(id)[OwnedController new];[controller setWindow:originalWindow];UIApplication.sharedApplication.delegate=controller;
    UIWindowScene *scene=[UIWindowScene new];scene.session=[UISceneSession new];scene.session.role=UIWindowSceneSessionRoleApplication;EHRUnitySceneDelegate *adapter=[EHRUnitySceneDelegate new];
    enforceOrdering=NO;if(preassociated)originalWindow.windowScene=scene;sceneBaseline=sceneWrites;keyBaseline=keyCalls;enforceOrdering=YES;
    OwnedFramework *framework=[OwnedFramework new];Check(EHRUnitySceneConfigure(framework)==0,@"own_framework_configured");
    [adapter scene:scene willConnectToSession:scene.session options:[UISceneConnectionOptions new]];Check(!Metric(@"attached")&&windowReads==0,@"connection_does_not_touch_window_before_original_active");
    if([scenario isEqualToString:@"early-active"]){[adapter sceneDidBecomeActive:scene];Check(!activeCalls&&!initializerCalls&&!Metric(@"attached")&&!windowReads,@"pre_foreground_active_is_refused_without_window_or_original_work");}
    if(late)exposeDelegate=NO;
    BOOL initializerRethrew=NO;@try{[adapter sceneWillEnterForeground:scene];}@catch(NSException *exception){initializerRethrew=[exception.name isEqualToString:@"OwnedInitializer"];}
    if(late){Check(!initializerCalls&&!activeCalls,@"unavailable_controller_queues_foreground");exposeDelegate=YES;}
    if(throwInitializer){
        Check(initializerRethrew&&initializerCalls==1&&!Metric(@"initializerReturned")&&!Metric(@"firstActiveCompleted"),@"throwing_initializer_never_becomes_ready");Check(Metric(@"callbackFailures")==1&&Metric(@"initializerStatus")==6,@"initializer_exception_records_once");
        [adapter sceneWillEnterForeground:scene];[adapter sceneDidEnterBackground:scene];[adapter sceneWillEnterForeground:scene];[adapter sceneDidBecomeActive:scene];Check(initializerCalls==1&&activeCalls==0&&!Metric(@"attached")&&!windowReads,@"entered_initializer_is_never_retried_or_followed_by_active");
    }else if(bad){
        [adapter sceneDidBecomeActive:scene];Check(!initializerCalls&&!activeCalls&&Metric(@"initializerStatus")==5&&!windowReads&&!Metric(@"attached"),@"wrong_initializer_abi_fails_before_original_or_window");Check(!Metric(@"initializerCalls")&&!Metric(@"initializerReturned")&&!keyCalls,@"wrong_abi_never_enters_initializer_or_key_work");
    }else{
        if(!late)Check(initializerCalls==1&&Metric(@"initializerReturned")==1&&foregroundCalls==0,@"cold_foreground_initializes_once_without_legacy_resume");
        BOOL activeRethrew=NO;@try{[adapter sceneDidBecomeActive:scene];}@catch(NSException *exception){activeRethrew=[exception.name isEqualToString:@"OwnedActive"];}
        Check(initializerCalls==1&&events.count>=2&&[events[0] isEqualToString:@"initialize"]&&[events[1] isEqualToString:@"active"],@"initializer_precedes_first_original_active");
        if(throwActive){[adapter sceneDidBecomeActive:scene];Check(activeRethrew&&activeCalls==1&&!Metric(@"firstActiveCompleted")&&!Metric(@"attached")&&!windowReads,@"entered_throwing_active_is_not_replayed_and_does_not_enable_attachment");Check(Metric(@"callbackFailures")==1,@"active_exception_records_once");}
        else{
            Check(activeReturned&&Metric(@"firstActiveCompleted")==1&&adapter.window==originalWindow&&originalWindow.windowScene==scene,@"successful_original_active_then_attaches_exact_window");Check(originalWindow.rootViewController==originalRoot,@"root_identity_preserved");Check(originalWindow.hidden==hidden&&(hidden?keyCalls==keyBaseline:keyCalls==keyBaseline+1),@"only_previously_visible_window_is_made_key");
            [adapter sceneDidBecomeActive:scene];Check(activeCalls==1&&initializerCalls==1,@"duplicate_active_does_not_reenter_initializer_or_original");
            [adapter sceneWillResignActive:scene];[adapter sceneDidEnterBackground:scene];[adapter sceneWillEnterForeground:scene];[adapter sceneDidBecomeActive:scene];Check(initializerCalls==1&&foregroundCalls==1&&activeCalls==2,@"later_resume_uses_normal_callbacks_without_reinitialization");
            [adapter sceneDidDisconnect:scene];[adapter scene:scene willConnectToSession:scene.session options:[UISceneConnectionOptions new]];[adapter sceneWillEnterForeground:scene];[adapter sceneDidBecomeActive:scene];Check(initializerCalls==1&&Metric(@"firstActiveCompleted")==1&&adapter.window==originalWindow&&originalWindow.rootViewController==originalRoot,@"reconnect_preserves_sticky_initialization_and_same_window_root");
        }
    }
    Check(loops==0,@"no_second_unity_loop_or_framework_reconfiguration");
    NSDictionary *proof=@{@"schema":@"ehr.unity-scene-owned-logic-proof.v1",@"scenario":scenario,@"success":@(failures.count==0),@"checks":@(checks),@"failures":failures,@"events":events,@"adapterStatus":EHRUnitySceneCopyStatus(),@"actualUIKit":@NO,@"gameFilesUsed":@NO,@"networkRequests":@0,@"credentialsRead":@0};NSData *data=[NSJSONSerialization dataWithJSONObject:proof options:NSJSONWritingSortedKeys error:nil];puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);return failures.count?1:0;
}}
