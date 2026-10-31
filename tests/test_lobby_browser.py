"""Compile the production presentation action against owned UIKit sentinels."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
UIKIT = '''#pragma once
#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, UISceneActivationState) { UISceneActivationStateUnattached=-1, UISceneActivationStateForegroundActive=0, UISceneActivationStateForegroundInactive=1, UISceneActivationStateBackground=2 };
typedef NS_ENUM(NSInteger, UIModalPresentationStyle) { UIModalPresentationFullScreen=0 };
@interface UIWindowScene:NSObject
@property(nonatomic) UISceneActivationState activationState;
@end
@interface UIWindow:NSObject
@property(nonatomic) BOOL hidden;
@property(nonatomic,strong) UIWindowScene *windowScene;
@end
@interface UIView:NSObject
@property(nonatomic,strong) UIWindow *window;
@end
@interface UIViewController:NSObject
@property(nonatomic,strong) UIView *ownedView;
@property(nonatomic,readonly) UIView *viewIfLoaded;
@property(nonatomic) BOOL isBeingPresented,isBeingDismissed;
@property(nonatomic,strong) UIViewController *presentedViewController;
@property(nonatomic) UIModalPresentationStyle modalPresentationStyle;
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void(^)(void))completion;
@end
'''
SAFARI = '''#pragma once
#import <UIKit/UIKit.h>
typedef NS_ENUM(NSInteger, SFSafariViewControllerDismissButtonStyle) { SFSafariViewControllerDismissButtonStyleDone=0 };
@interface SFSafariViewControllerConfiguration:NSObject
@property(nonatomic) BOOL entersReaderIfAvailable,barCollapsingEnabled;
@end
@interface SFSafariViewController:UIViewController
@property(nonatomic) SFSafariViewControllerDismissButtonStyle dismissButtonStyle;
- (instancetype)initWithURL:(NSURL *)url configuration:(SFSafariViewControllerConfiguration *)configuration;
@end
'''


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "Requires Apple's Objective-C++ compiler")
class LobbyBrowserTests(unittest.TestCase):
    def test_real_action_readiness_and_exact_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, source in (("UIKit/UIKit.h", UIKIT), ("SafariServices/SafariServices.h", SAFARI)):
                path = root / name
                path.parent.mkdir(parents=True)
                path.write_text(source)
            binary = root / "owned-browser"
            source = ROOT / "native/EHRLobbyBrowser.mm"
            command = ["xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-framework", "Foundation", "-I", str(root), "-I", str(ROOT / "native"), '-DEHR_LOBBY_BROWSER_SOURCE="' + str(source) + '"', str(ROOT / "tests/LobbyBrowserFixture.mm"), "-o", str(binary)]
            built = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
            self.assertEqual(built.returncode, 0, built.stdout)
            ran = subprocess.run([str(binary)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
            self.assertEqual(ran.returncode, 0, ran.stdout)
            proof = json.loads(ran.stdout)
            self.assertTrue(proof["pass"])
            self.assertGreaterEqual(proof["checks"], 17)
            self.assertEqual(proof["actualNetworkRequests"], 0)
            self.assertEqual(proof["credentialReads"], 0)


if __name__ == "__main__":
    unittest.main()
