// Actual UIKit input-boundary fixture. No game, Keychain or network is used.
#define EHR_HAS_ITCH_AUTH 1
#import <UIKit/UIKit.h>
#import "../native/EHRItchAuthProvider.h"
#import "../native/EHROwnershipCover.h"
#import "../native/EHRFullSourceRuntime.h"
#import "../native/EHRExportSharing.h"
@interface EHROwnershipCover (OwnedInspection)
@property(nonatomic,readonly) UIButton *signIn;
@property(nonatomic,readonly) UIButton *account;
@property(nonatomic,readonly) UILabel *message;
@end
static bool owned=false,pending=false,cleared=false;
static int32_t ownershipStatus=6;
static NSUInteger checks=0,signIns=0,accounts=0;
static NSMutableArray<NSString *> *failures;
static void Check(bool value,NSString *label){++checks;if(!value)[failures addObject:label];}
bool EHRItchAuthProviderSelected(void){return true;}
bool EHRItchAuthProviderOwnershipVerified(void){return owned;}
bool EHRItchAuthProviderDirectoryAllowed(void){return false;}
int32_t EHRItchAuthProviderStart(void){return 0;}
void EHRItchAuthProviderSetPresenter(__unused UIViewController *presenter){}
void EHRItchAuthProviderPresent(void){++signIns;}
void EHRItchAuthProviderPresentAccount(void){++accounts;}
NSDictionary *EHRItchAuthProviderCopyStatus(void){return @{@"ownershipPending":@(pending),@"ownershipChecks":@1,@"ownershipStatus":@(ownershipStatus),@"clearedForRestart":@(cleared),@"runtime":@{}};}
NSDictionary *EHRFullSourceCopyRuntimeStatus(void){return @{@"application":@{},@"attempted":@NO};}
void EHRFullSourceRefreshDirectory(void){}
UIViewController *EHRExportSharingController(void){return [UIViewController new];}
#include "../native/EHRFullSourceOverlay.mm"

static void Later(void (^block)(void)){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,900*NSEC_PER_MSEC),dispatch_get_main_queue(),block);}
static void Capture(NSString *name){NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"file":name} options:0 error:nil];[data writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/phase.json"] atomically:YES];}
static void Finish(void){
    NSDictionary *proof=@{@"schema":@"ehr.ownership-cover-uikit-proof.v1",@"success":@(failures.count==0),@"checks":@(checks),@"failures":failures,@"actualUIKit":@YES,@"actualCredentialsRead":@0,@"networkRequests":@0,@"accountActions":@0,@"gameInputs":@0};
    [[NSJSONSerialization dataWithJSONObject:proof options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/proof.json"] atomically:YES];
    Later(^{exit(failures.count?1:0);});
}
static void Exercise(EHRFullStatusPanel *panel){
    UIView *root=panel.window.rootViewController.view;EHROwnershipCover *cover=panel.ownershipCover;
    [panel refresh];[panel layoutOverlay];[cover layoutIfNeeded];
    Check(!cover.hidden&&CGRectEqualToRect(cover.frame,root.bounds),@"unowned_cover_fills_game_window");
    Check(panel.button.hidden,@"unowned_status_badge_not_escape");
    Check([panel.window hitTest:CGPointMake(4,root.bounds.size.height-4) withEvent:nil]!=nil,@"unowned_blank_space_blocks_game_touch");
    Check(cover.signIn.bounds.size.height>=44&&cover.signIn.bounds.size.width>=260,@"portrait_signin_target_readable");
    [cover.signIn sendActionsForControlEvents:UIControlEventTouchUpInside];Check(signIns==1,@"explicit_signin_callback_once");
    [cover.account sendActionsForControlEvents:UIControlEventTouchUpInside];Check(accounts==1,@"explicit_account_callback_once");
    Capture(@"ownership-cover-portrait.png");
    Later(^{
        UIWindowSceneGeometryPreferencesIOS *geometry=[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeLeft];
        [panel.window.windowScene requestGeometryUpdateWithPreferences:geometry errorHandler:^(__unused NSError *error){}];
        Later(^{
            [panel layoutOverlay];[cover layoutIfNeeded];
            Check(root.bounds.size.width>root.bounds.size.height,@"actual_landscape_geometry");
            Check(CGRectEqualToRect(cover.frame,root.bounds),@"landscape_cover_still_fills_window");
            Check(cover.signIn.bounds.size.height>=44&&cover.signIn.bounds.size.width>=260,@"landscape_signin_target_readable");
            Check(cover.contentSize.height>cover.bounds.size.height,@"short_landscape_content_can_scroll");
            Capture(@"ownership-cover-landscape.png");
            Later(^{
                pending=true;[panel refresh];Check(!cover.hidden&&!cover.signIn.enabled,@"pending_proof_cannot_unlock_game_or_resubmit");
                pending=false;ownershipStatus=1;[panel refresh];Check([cover.message.text containsString:@"claimed library"],@"no_entitlement_explains_claimed_library");
                ownershipStatus=4;[panel refresh];Check([cover.message.text containsString:@"does not mean your purchase is missing"],@"network_failure_not_unowned_claim");
                owned=true;[panel refresh];Check(cover.hidden&&!panel.button.hidden,@"verified_proof_restores_normal_badge");
                Check([panel.window hitTest:CGPointMake(4,root.bounds.size.height-4) withEvent:nil]==nil,@"verified_blank_space_passes_to_game");
                owned=false;Check(cover.hidden,@"timer_not_run_before_revocation_test");
                Check([panel.window hitTest:CGPointMake(4,root.bounds.size.height-4) withEvent:nil]!=nil&&!cover.hidden,@"proof_revoked_blocks_touch_before_timer");
                cleared=true;[panel refresh];Check(!cover.hidden&&!cover.signIn.enabled&&[cover.message.text containsString:@"Close and reopen"],@"clear_requires_manual_reopen_without_game_access");
                Finish();
            });
        });
    });
}
static void FindPanel(UIWindowScene *scene,NSUInteger tries){
    for(UIWindow *window in scene.windows)if([window isKindOfClass:EHRFullStatusWindow.class]){Exercise(((EHRFullStatusController *)window.rootViewController).statusPanel);return;}
    if(tries>20){Check(false,@"production_constructor_installs_when_scene_ready");Finish();return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{FindPanel(scene,tries+1);});
}
@interface OwnershipFixtureScene:UIResponder<UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation OwnershipFixtureScene
- (void)scene:(UIScene *)scene willConnectToSession:(__unused UISceneSession *)session options:(__unused UISceneConnectionOptions *)options {
    failures=[NSMutableArray new];self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];self.window.rootViewController=[UIViewController new];self.window.rootViewController.view.backgroundColor=UIColor.whiteColor;[self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{FindPanel((UIWindowScene *)scene,0);});
}
@end
@interface OwnershipFixtureApp:UIResponder<UIApplicationDelegate>
@end
@implementation OwnershipFixtureApp
- (UISceneConfiguration *)application:(__unused UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(__unused UISceneConnectionOptions *)options {UISceneConfiguration *configuration=[[UISceneConfiguration alloc] initWithName:@"Owned" sessionRole:session.role];configuration.delegateClass=OwnershipFixtureScene.class;return configuration;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(OwnershipFixtureApp.class));}}
