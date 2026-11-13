"""Own fixture compile checks; simulator execution is an explicit local action."""
from pathlib import Path
import subprocess
import tempfile
import json
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]

@unittest.skipUnless(sys.platform=='darwin','Requires the Apple SDKs')
class UnitySceneLauncherTests(unittest.TestCase):
    def compile(self,sdk_name,target,sources):
        sdk=subprocess.check_output(['xcrun','--sdk',sdk_name,'--show-sdk-path'],text=True).strip()
        result=subprocess.run(['xcrun','clang++','-target',target,'-isysroot',sdk,'-fobjc-arc','-fblocks','-std=c++20','-Wall','-Wextra','-Werror','-fsyntax-only',*[str(ROOT/p) for p in sources]],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stderr)
    def test_actual_scene_adapter_and_launcher_compile_for_ios(self):
        self.compile('iphoneos','arm64-apple-ios17.0',['native/launcher/EHRUnitySceneDelegate.mm','native/launcher/main.mm'])
    def test_owned_scene_fixture_compiles_for_simulator(self):
        self.compile('iphonesimulator','arm64-apple-ios17.0-simulator',['tests/UnitySceneUIKitFixture.mm','native/launcher/EHRUnitySceneDelegate.mm'])
    def test_exact_adapter_ordering_with_owned_collaborators_without_simulator(self):
        with tempfile.TemporaryDirectory(prefix="ehr-scene-ordering-") as directory:
            base=Path(directory);(base/"UIKit").mkdir()
            (base/"UIKit/UIKit.h").write_text('''#pragma once
#import <Foundation/Foundation.h>
@class UIWindow,UIApplication,UIScene,UISceneSession,UISceneConnectionOptions;
@protocol UIApplicationDelegate<NSObject>
@optional
@property(nonatomic,strong) UIWindow *window;
- (void)applicationDidBecomeActive:(UIApplication *)application;
- (void)applicationWillResignActive:(UIApplication *)application;
- (void)applicationWillEnterForeground:(UIApplication *)application;
- (void)applicationDidEnterBackground:(UIApplication *)application;
@end
@protocol UIWindowSceneDelegate<NSObject>
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options;
- (void)sceneWillEnterForeground:(UIScene *)scene;
- (void)sceneDidBecomeActive:(UIScene *)scene;
- (void)sceneWillResignActive:(UIScene *)scene;
- (void)sceneDidEnterBackground:(UIScene *)scene;
- (void)sceneDidDisconnect:(UIScene *)scene;
@end
@interface UIResponder:NSObject
@end
@interface UIViewController:NSObject
@end
@interface UISceneSession:NSObject
@property(nonatomic,strong) NSString *role;
@end
@interface UISceneConnectionOptions:NSObject
@end
@interface UIScene:NSObject
@property(nonatomic,strong) UISceneSession *session;
@end
@interface UIWindowScene:UIScene
@end
@interface UIWindow:NSObject
@property(nonatomic,strong) UIWindowScene *windowScene;
@property(nonatomic,strong) UIViewController *rootViewController;
@property(nonatomic) BOOL hidden;
@property(nonatomic,getter=isKeyWindow) BOOL keyWindow;
- (void)makeKeyAndVisible;
@end
@interface UIApplication:NSObject
@property(nonatomic,strong) id<UIApplicationDelegate> delegate;
+ (instancetype)sharedApplication;
@end
extern NSString *const UIWindowSceneSessionRoleApplication;
''')
            executable=base/"fixture"
            result=subprocess.run(["xcrun","clang++","-fobjc-arc","-fblocks","-std=c++20","-Wall","-Wextra","-Werror","-I",str(base),str(ROOT/"tests/UnitySceneLogicFixture.mm"),str(ROOT/"native/launcher/EHRUnitySceneDelegate.mm"),"-framework","Foundation","-o",str(executable)],capture_output=True,text=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stderr)
            for scenario in ["normal","early-active","late-controller","hidden","preassociated","initializer-throw","active-throw","wrong-abi"]:
                with self.subTest(scenario=scenario):
                    run=subprocess.run([str(executable),scenario],capture_output=True,text=True,timeout=10)
                    self.assertEqual(run.returncode,0,run.stdout+run.stderr)
                    proof=json.loads(run.stdout);self.assertTrue(proof["success"]);self.assertGreaterEqual(proof["checks"],5)
                    self.assertFalse(proof["actualUIKit"]);self.assertFalse(proof["gameFilesUsed"]);self.assertEqual(proof["networkRequests"],0)

    def test_runner_is_explicit_simulator_only_and_requires_outside_output(self):
        result=subprocess.run([sys.executable,str(ROOT/'tools/run_unity_scene_fixture.py'),'--help'],capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr)
        for option in ['--simulator-id-file','--create-simulator','--output']:self.assertIn(option,result.stdout)
        denied=subprocess.run([sys.executable,str(ROOT/'tools/run_unity_scene_fixture.py'),'--output',str(ROOT/'forbidden-scene-output'),'--create-simulator'],capture_output=True,text=True,timeout=10)
        self.assertNotEqual(denied.returncode,0);self.assertIn('outside the source repository',denied.stderr);self.assertFalse((ROOT/'forbidden-scene-output').exists())
if __name__=='__main__':unittest.main()
