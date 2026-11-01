// Actual UIKit with production overlay/cover; all service/runtime inputs owned.
#define EHR_HAS_ITCH_AUTH 1
#define EHR_HAS_LOBBY_SEARCH 1
#import <UIKit/UIKit.h>
#import "../native/EHRRuntimeGateway.h"
#import "../native/EHRItchAuthProvider.h"
#import "../native/EHRFullSourceRuntime.h"
#import "../native/EHRExportSharing.h"
#import "../native/EHRLobbyBrowser.h"
#import "../native/EHRLobbySearch.h"
static bool owned=true;
static int32_t loadingMode=0,searchChoice=0,setStatus=0;
static NSUInteger checks=0,loadingReads=0,heavyReads=0,directoryTicks=0,setCalls=0,accountActions=0,browseActions=0;
static NSMutableArray<NSString *> *failures;
static void Check(bool value,NSString *label){++checks;if(!value)[failures addObject:label];}
bool EHRItchAuthProviderSelected(void){return true;}
bool EHRItchAuthProviderOwnershipVerified(void){return owned;}
bool EHRItchAuthProviderDirectoryAllowed(void){return false;}
int32_t EHRItchAuthProviderStart(void){return 0;}
void EHRItchAuthProviderSetPresenter(__unused UIViewController *value){}
void EHRItchAuthProviderPresent(void){++accountActions;}
void EHRItchAuthProviderPresentAccount(void){++accountActions;}
NSDictionary *EHRItchAuthProviderCopyStatus(void){return @{@"ownershipPending":@NO,@"ownershipChecks":@1,@"ownershipStatus":@0,@"clearedForRestart":@NO,@"runtime":@{}};}
NSDictionary *EHRFullSourceCopyRuntimeStatus(void){++heavyReads;return @{@"application":@{@"state":@3,@"optionsLoaded":@YES},@"attempted":@YES};}
NSDictionary *EHRFullSourceCopySettingsLoadingStatus(void){++loadingReads;return @{@"status":@(loadingMode==2?6:0),@"busy":@(loadingMode!=0),@"processed":@3,@"total":@40};}
void EHRFullSourceRefreshDirectory(void){++directoryTicks;}
UIViewController *EHRExportSharingController(void){return [UIViewController new];}
void EHRPresentLobbyBrowser(__unused UIViewController *value){++browseActions;}
int32_t EHRLobbySearchGetSelection(void){return searchChoice;}
int32_t EHRLobbySearchSetSelection(int32_t value){++setCalls;if(setStatus)return setStatus;if(value<0||value>1)return 4;searchChoice=value;return 0;}
#include "../native/EHRFullSourceOverlay.mm"

static void Later(void (^block)(void)){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,600*NSEC_PER_MSEC),dispatch_get_main_queue(),block);}
static void WaitForCapture(NSString *name,NSUInteger tries,void (^next)(void)){
    NSData *data=[NSData dataWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/captured.json"]];
    NSDictionary *value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if([value[@"file"] isEqualToString:name]){next();return;}
    if(tries>=240){Check(false,@"owned_screenshot_acknowledgement");next();return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{WaitForCapture(name,tries+1,next);});
}
static void Capture(NSString *name,void (^next)(void)){
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"file":name} options:0 error:nil];
    [data writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/phase.json"] atomically:YES];
    WaitForCapture(name,0,next);
}
static bool Contains(CGRect outer,CGRect inner){return CGRectContainsRect(CGRectInset(outer,-0.5,-0.5),inner);}
static bool Overlap(CGRect a,CGRect b){return !CGRectIsEmpty(a)&&!CGRectIsEmpty(b)&&CGRectIntersectsRect(a,b);}
static void LayoutChecks(EHRFullStatusPanel *panel,NSString *orientation){
    UIView *root=panel.window.rootViewController.view;
    CGRect safe=CGRectInset(UIEdgeInsetsInsetRect(root.bounds,root.safeAreaInsets),12,10);
    const CGPoint positions[]={{0.5,0},{0,0},{1,1},{0.5,0.1},{0.5,0.5}};
    for(CGPoint position:positions){
        panel.panel.hidden=YES;panel.badgePosition=position;[panel layoutOverlay];[panel refreshLoading];
        CGRect restingBadge=panel.button.frame;
        Check(Contains(safe,panel.button.frame),[orientation stringByAppendingString:@"_badge_in_safe_area"]);
        Check(Contains(safe,panel.panel.frame),[orientation stringByAppendingString:@"_panel_in_safe_area"]);
        Check(Contains(safe,panel.loadingPill.frame),[orientation stringByAppendingString:@"_pill_in_safe_area"]);
        Check(!Overlap(panel.button.frame,panel.loadingPill.frame),[orientation stringByAppendingString:@"_pill_badge_no_overlap"]);
        panel.panel.hidden=NO;[panel layoutOverlay];[panel refreshLoading];
        Check(panel.loadingPill.hidden,[orientation stringByAppendingString:@"_panel_hides_pill"]);
        Check(Contains(safe,panel.button.frame)&&Contains(safe,panel.panel.frame),[orientation stringByAppendingString:@"_open_panel_and_badge_fit"]);
        NSArray<UIView *> *controls=@[panel.statusScroll,panel.searchSelector,panel.searchHint,panel.lobbiesButton,panel.signInButton,panel.exportsButton];
        for(NSUInteger i=0;i<controls.count;++i){
            Check(Contains(panel.panel.bounds,controls[i].frame),[orientation stringByAppendingString:@"_footer_or_content_in_panel"]);
            for(NSUInteger j=i+1;j<controls.count;++j)
                Check(!Overlap(controls[i].frame,controls[j].frame),[orientation stringByAppendingString:@"_footer_and_content_no_overlap"]);
        }
        for(UIButton *button in @[panel.lobbiesButton,panel.signInButton,panel.exportsButton])
            Check(button.bounds.size.height>=44,[orientation stringByAppendingString:@"_footer_target44"]);
        Check(!Overlap(panel.button.frame,panel.panel.frame),[orientation stringByAppendingString:@"_badge_panel_no_overlap"]);
        Check(CGPointEqualToPoint(panel.badgePosition,position),[orientation stringByAppendingString:@"_opening_preserves_saved_position"]);
        panel.panel.hidden=YES;[panel layoutOverlay];[panel refreshLoading];
        Check(CGRectEqualToRect(panel.button.frame,restingBadge),[orientation stringByAppendingString:@"_closing_restores_badge_position"]);
    }
    panel.badgePosition=CGPointMake(0.5,0);[panel layoutOverlay];
}
static void Finish(void){
    NSDictionary *proof=@{@"schema":@"ehr.settings-overlay-uikit-proof.v1",@"success":@(failures.count==0),@"checks":@(checks),@"failures":failures,
        @"actualUIKit":@YES,@"sourceStubCalls":@(loadingReads),@"heavyStubCalls":@(heavyReads),@"searchSetterCalls":@(setCalls),
        @"actualGameCalls":@0,@"networkRequests":@0,@"credentialReads":@0,@"physicalDeviceActions":@0};
    [[NSJSONSerialization dataWithJSONObject:proof options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/proof.json"] atomically:YES];
    Later(^{exit(failures.count?1:0);});
}
static void LoadingAndEvents(EHRFullStatusPanel *panel){
    [panel refresh];[panel layoutOverlay];
    Check(panel.loadingPill.hidden&&!panel.loadingSpinner.isAnimating,@"idle_hidden_and_stopped");
    loadingMode=1;[panel refreshLoading];
    Check(!panel.loadingPill.hidden&&panel.loadingSpinner.isAnimating,@"busy_visible_and_animating");
    Check([panel.loadingLabel.text containsString:@"3 / 40"],@"real_getter_progress_presented");
    Check(!panel.loadingPill.userInteractionEnabled,@"loading_view_noninteractive");
    Check(panel.loadingLabel.font.pointSize>=14,@"loading_text_readable");
    CGPoint point=[panel.loadingPill convertPoint:CGPointMake(CGRectGetMidX(panel.loadingPill.bounds),CGRectGetMidY(panel.loadingPill.bounds)) toView:panel.window];
    Check([panel.window hitTest:point withEvent:nil]==nil,@"loading_pill_passes_game_touch");
    NSUInteger before=loadingReads,heavy=heavyReads,ticks=directoryTicks;
    Later(^{
        Check(loadingReads>=before+3,@"actual100ms_timer_polls_loading");
        Check(heavyReads<=heavy+1&&directoryTicks<=ticks+1,@"light_poll_does_not_run_heavy_status_or_directory");
        loadingMode=2;[panel refreshLoading];Check(panel.loadingPill.hidden&&!panel.loadingSpinner.isAnimating,@"getter_failure_hides_and_stops");
        loadingMode=1;[panel refreshLoading];
        [panel.button sendActionsForControlEvents:UIControlEventTouchUpInside];
        Check(!panel.panel.hidden&&panel.loadingPill.hidden&&!panel.loadingSpinner.isAnimating,@"open_panel_hides_loading");
        panel.searchSelector.selectedSegmentIndex=1;[panel.searchSelector sendActionsForControlEvents:UIControlEventValueChanged];
        Check(setCalls==1&&searchChoice==1&&panel.searchSelector.selectedSegmentIndex==1,@"ehr_selection_calls_setter_once");
        panel.searchSelector.selectedSegmentIndex=0;[panel.searchSelector sendActionsForControlEvents:UIControlEventValueChanged];
        Check(setCalls==2&&searchChoice==0&&panel.searchSelector.selectedSegmentIndex==0,@"all_selection_calls_setter_once");
        setStatus=7;panel.searchSelector.selectedSegmentIndex=1;[panel.searchSelector sendActionsForControlEvents:UIControlEventValueChanged];
        Check(setCalls==3&&searchChoice==0&&panel.searchSelector.selectedSegmentIndex==0&&[panel.searchHint.text containsString:@"Couldn't change"],@"rejected_selection_restores_actual_state");setStatus=0;
        panel.searchSelector.selectedSegmentIndex=UISegmentedControlNoSegment;[panel.searchSelector sendActionsForControlEvents:UIControlEventValueChanged];
        Check(setCalls==3&&panel.searchSelector.selectedSegmentIndex==0,@"invalid_segment_no_setter");
        [panel.lobbiesButton sendActionsForControlEvents:UIControlEventTouchUpInside];Check(browseActions==1&&panel.panel.hidden,@"lobbies_calls_owned_handler_once");
        [panel.signInButton sendActionsForControlEvents:UIControlEventTouchUpInside];Check(accountActions==1&&panel.panel.hidden,@"account_calls_owned_handler_once");
        owned=false;[panel refresh];Check(panel.loadingPill.hidden&&!panel.ownershipCover.hidden,@"ownership_cover_hides_loading");
        owned=true;[panel refresh];Check(!panel.loadingPill.hidden&&panel.ownershipCover.hidden,@"verified_cover_restore_loading");
        loadingMode=0;[panel refreshLoading];Check(panel.loadingPill.hidden&&!panel.loadingSpinner.isAnimating,@"completion_clears_loading");
        loadingMode=1;[panel refreshLoading];LayoutChecks(panel,@"portrait");Capture(@"settings-overlay-portrait.png",^{
            UIWindowSceneGeometryPreferencesIOS *geometry=[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeLeft];
            [panel.window.windowScene requestGeometryUpdateWithPreferences:geometry errorHandler:^(__unused NSError *error){Check(false,@"landscape_geometry_request");}];
            Later(^{
                Check(panel.window.rootViewController.view.bounds.size.width>panel.window.rootViewController.view.bounds.size.height,@"actual_landscape_geometry");
                LayoutChecks(panel,@"landscape");[panel refreshLoading];Capture(@"settings-overlay-landscape.png",^{
                    panel.panel.hidden=NO;[panel refreshLoading];[panel layoutOverlay];Capture(@"settings-panel-landscape.png",^{
                        panel.panel.hidden=YES;UIViewController *modal=[UIViewController new];modal.view.backgroundColor=UIColor.whiteColor;
                        [panel.window.rootViewController presentViewController:modal animated:NO completion:^{
                            [panel refreshLoading];Check(panel.loadingPill.hidden&&!panel.loadingSpinner.isAnimating,@"presented_controller_hides_loading");
                            [modal dismissViewControllerAnimated:NO completion:^{[panel refreshLoading];Check(!panel.loadingPill.hidden,@"dismissed_controller_restores_loading");Finish();}];
                        }];
                    });
                });
            });
        });
    });
}
static void FindPanel(UIWindowScene *scene,NSUInteger tries){
    for(UIWindow *window in scene.windows)if([window isKindOfClass:EHRFullStatusWindow.class]){LoadingAndEvents(((EHRFullStatusController *)window.rootViewController).statusPanel);return;}
    if(tries>30){Check(false,@"production_constructor_installed");Finish();return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{FindPanel(scene,tries+1);});
}
@interface SettingsFixtureScene:UIResponder<UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation SettingsFixtureScene
- (void)scene:(UIScene *)scene willConnectToSession:(__unused UISceneSession *)session options:(__unused UISceneConnectionOptions *)options {
    failures=[NSMutableArray new];self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];self.window.rootViewController=[UIViewController new];self.window.rootViewController.view.backgroundColor=UIColor.darkGrayColor;[self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{FindPanel((UIWindowScene *)scene,0);});
}
@end
@interface SettingsFixtureApp:UIResponder<UIApplicationDelegate>
@end
@implementation SettingsFixtureApp
- (UISceneConfiguration *)application:(__unused UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(__unused UISceneConnectionOptions *)options {UISceneConfiguration *configuration=[[UISceneConfiguration alloc] initWithName:@"Owned" sessionRole:session.role];configuration.delegateClass=SettingsFixtureScene.class;return configuration;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(SettingsFixtureApp.class));}}
