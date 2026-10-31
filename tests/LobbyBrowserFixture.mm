// Owned UIKit/Safari sentinels. No browser/network/game/account is used.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SafariServices/SafariServices.h>
#include <atomic>
#include <thread>

static std::atomic<int> constructions{0},presentations{0},viewReads{0};
static NSURL *lastURL=nil;
static SFSafariViewControllerConfiguration *lastConfiguration=nil;
static int checks=0;
static void Check(bool condition){++checks;if(!condition)abort();}

@implementation UIWindowScene
@end
@implementation UIWindow
@end
@implementation UIView
@end
@implementation UIViewController
- (UIView *)viewIfLoaded {++viewReads;return self.ownedView;}
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void(^)(void))completion {
    Check(animated);++presentations;self.presentedViewController=controller;if(completion)completion();
}
@end
@implementation SFSafariViewControllerConfiguration
@end
@implementation SFSafariViewController
- (instancetype)initWithURL:(NSURL *)url configuration:(SFSafariViewControllerConfiguration *)configuration {
    if((self=[super init])){++constructions;lastURL=url;lastConfiguration=configuration;}return self;
}
@end

#include EHR_LOBBY_BROWSER_SOURCE

int main(){@autoreleasepool{
    UIViewController *owner=[UIViewController new];
    UIWindowScene *scene=[UIWindowScene new];scene.activationState=UISceneActivationStateForegroundActive;
    UIWindow *window=[UIWindow new];window.windowScene=scene;
    UIView *view=[UIView new];view.window=window;
    EHRPresentLobbyBrowser(nil);EHRPresentLobbyBrowser(owner);Check(constructions==0&&presentations==0);
    owner.ownedView=view;window.hidden=YES;EHRPresentLobbyBrowser(owner);Check(constructions==0&&presentations==0);
    window.hidden=NO;
    for(auto state:{UISceneActivationStateForegroundInactive,UISceneActivationStateBackground,UISceneActivationStateUnattached}){
        scene.activationState=state;EHRPresentLobbyBrowser(owner);Check(constructions==0&&presentations==0);
    }
    scene.activationState=UISceneActivationStateForegroundActive;
    window.windowScene=nil;EHRPresentLobbyBrowser(owner);Check(constructions==0&&presentations==0);window.windowScene=scene;
    owner.isBeingPresented=YES;EHRPresentLobbyBrowser(owner);Check(constructions==0&&presentations==0);owner.isBeingPresented=NO;
    owner.isBeingDismissed=YES;EHRPresentLobbyBrowser(owner);Check(constructions==0&&presentations==0);owner.isBeingDismissed=NO;
    owner.presentedViewController=[UIViewController new];EHRPresentLobbyBrowser(owner);Check(constructions==0&&presentations==0);owner.presentedViewController=nil;
    const int reads=viewReads.load();std::thread worker([=]{@autoreleasepool{EHRPresentLobbyBrowser(owner);}});worker.join();
    Check(viewReads==reads&&constructions==0&&presentations==0);
    EHRPresentLobbyBrowser(owner);Check(constructions==1&&presentations==1);
    Check([lastURL.absoluteString isEqualToString:@"https://app.gurge44.eu/lobbies"]);
    Check(!lastConfiguration.entersReaderIfAvailable&&!lastConfiguration.barCollapsingEnabled);
    auto *browser=(SFSafariViewController *)owner.presentedViewController;
    Check(browser.dismissButtonStyle==SFSafariViewControllerDismissButtonStyleDone);
    Check(browser.modalPresentationStyle==UIModalPresentationFullScreen);
    EHRPresentLobbyBrowser(owner);Check(constructions==1&&presentations==1);
    printf("{\"schema\":\"ehr.lobby-browser-owned-proof.v1\",\"pass\":true,\"checks\":%d,\"actualNetworkRequests\":0,\"actualGameCalls\":0,\"credentialReads\":0}\n",checks);
}return 0;}
