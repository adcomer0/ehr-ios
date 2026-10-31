#import "EHRLobbyBrowser.h"
#import <UIKit/UIKit.h>
#import <SafariServices/SafariServices.h>

void EHRPresentLobbyBrowser(UIViewController *presenter) {
    if(!NSThread.isMainThread||!presenter||presenter.isBeingDismissed||
       presenter.isBeingPresented||presenter.presentedViewController)return;
    UIWindow *window=presenter.viewIfLoaded.window;
    if(!window||window.hidden||!window.windowScene||
       window.windowScene.activationState!=UISceneActivationStateForegroundActive)return;

    // Construction is deliberately inside the explicit action, after readiness
    // checks. Safari owns website sign-in/navigation and does not return page
    // data, cookies or credentials to the itch/EOS provider or diagnostics.
    SFSafariViewControllerConfiguration *configuration=[SFSafariViewControllerConfiguration new];
    configuration.entersReaderIfAvailable=NO;
    configuration.barCollapsingEnabled=NO;
    SFSafariViewController *browser=[[SFSafariViewController alloc]
        initWithURL:[NSURL URLWithString:@"https://app.gurge44.eu/lobbies"]
        configuration:configuration];
    browser.dismissButtonStyle=SFSafariViewControllerDismissButtonStyleDone;
    browser.modalPresentationStyle=UIModalPresentationFullScreen;
    [presenter presentViewController:browser animated:YES completion:nil];
}
