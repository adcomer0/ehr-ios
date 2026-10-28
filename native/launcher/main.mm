#import "EHRUnityFrameworkAPI.h"
#import <UIKit/UIKit.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach-o/ldsyms.h>

/*
 * Original native iOS Unity host, staged 2026-10-28.
 *
 * This source loads only its own app bundle's embedded UnityFramework through
 * NSBundle's standard code-loading API and Unity's documented entry points.
 * It does not locate/copy another app, modify any binary, decrypt anything,
 * alter signatures/entitlements, remove account checks, or change protection
 * policy. Required code/resources must be supplied and signed separately by
 * the integrator. This source alone contains no game and is not a playable mod.
 *
 * Expected eventual host layout:
 *   Host.app/<this independently compiled executable>
 *   Host.app/Frameworks/UnityFramework.framework/<framework binary>
 *   Host.app/Data/...  (Unity's default data location)
 * Dependencies of the supplied framework must also be correctly embedded.
 *
 * If Data is intentionally in another bundled resource bundle, its identifier
 * may be configured with the host's EHRUnityDataBundleIdentifier Info.plist key.
 * No override is applied by default: Unity searches the new main app's Data.
 * The host's own app identifier/signing identity must be configured separately.
 */

@interface EHRLauncherBridgeObserver : NSObject
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
@end

@implementation EHRLauncherBridgeObserver
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                   name:UIApplicationDidFinishLaunchingNotification
                                                 object:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        auto start = reinterpret_cast<void (*)(void)>(dlsym(RTLD_DEFAULT, "EHRLiveBridgeStart"));
        if (start) start();
    });
}
@end

static EHRLauncherBridgeObserver *gBridgeObserver;

static BOOL EHRValidateUnitySelectors(id<EHRUnityFrameworkPublicAPI> framework) {
    const SEL selectors[] = {
        @selector(appController),
        @selector(setExecuteHeader:),
        @selector(setDataBundleId:),
        @selector(runUIApplicationMainWithArgc:argv:),
    };
    for (SEL selector : selectors) {
        if (![framework respondsToSelector:selector]) {
            NSLog(@"EHR launcher: supplied framework lacks public selector %@",
                  NSStringFromSelector(selector));
            return NO;
        }
    }
    return YES;
}

static id<EHRUnityFrameworkPublicAPI> EHRLoadBundledUnity(void) {
    NSURL *frameworksURL = [NSBundle mainBundle].privateFrameworksURL;
    if (frameworksURL == nil) {
        NSLog(@"EHR launcher: main bundle has no Frameworks directory URL");
        return nil;
    }
    NSURL *frameworkURL = [frameworksURL URLByAppendingPathComponent:@"UnityFramework.framework"
                                                       isDirectory:YES];
    NSBundle *bundle = [NSBundle bundleWithURL:frameworkURL];
    if (bundle == nil) {
        NSLog(@"EHR launcher: embedded UnityFramework bundle is unavailable");
        return nil;
    }
    NSError *error = nil;
    if (!bundle.isLoaded && ![bundle loadAndReturnError:&error]) {
        NSLog(@"EHR launcher: standard framework load failed (%@, %ld)",
              error.domain, (long)error.code);
        return nil;
    }
    Class<EHRUnityFrameworkPublicAPI> principal =
        (Class<EHRUnityFrameworkPublicAPI>)bundle.principalClass;
    if (principal == Nil || ![principal respondsToSelector:@selector(getInstance)]) {
        NSLog(@"EHR launcher: framework principal class lacks +getInstance");
        return nil;
    }
    id<EHRUnityFrameworkPublicAPI> framework = [principal getInstance];
    if (framework == nil || !EHRValidateUnitySelectors(framework)) {
        return nil;
    }
    if ([framework appController] == nil) {
        // This is this NEW executable's header, supplied for Unity's crash
        // reporting as documented. No original launcher header is used.
        [framework setExecuteHeader:&_mh_execute_header];
    } else {
        // main() is a fresh-launch entry point, not an embedded/re-entry API.
        NSLog(@"EHR launcher: Unity is already initialized; refusing duplicate UIApplicationMain");
        return nil;
    }
    id dataBundleValue = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"EHRUnityDataBundleIdentifier"];
    if (dataBundleValue != nil) {
        if (![dataBundleValue isKindOfClass:[NSString class]] ||
            [(NSString *)dataBundleValue length] == 0) {
            NSLog(@"EHR launcher: invalid data-bundle identifier configuration");
            return nil;
        }
        NSString *identifier = (NSString *)dataBundleValue;
        if ([NSBundle bundleWithIdentifier:identifier] == nil) {
            NSLog(@"EHR launcher: configured data bundle is not loaded");
            return nil;
        }
        [framework setDataBundleId:identifier.UTF8String];
    }
    return framework;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        id<EHRUnityFrameworkPublicAPI> framework = EHRLoadBundledUnity();
        if (framework == nil) {
            return 70; // Bootstrap configuration/loading failure; no fallback.
        }
        gBridgeObserver = [EHRLauncherBridgeObserver new];
        [[NSNotificationCenter defaultCenter] addObserver:gBridgeObserver
                                                     selector:@selector(applicationDidFinishLaunching:)
                                                         name:UIApplicationDidFinishLaunchingNotification
                                                       object:nil];
        // Unity's documented fresh-app entry owns UIApplicationMain and its
        // delegate. This original host does not introduce a second UI loop.
        [framework runUIApplicationMainWithArgc:argc argv:argv];
        if (gBridgeObserver != nil) {
            [[NSNotificationCenter defaultCenter] removeObserver:gBridgeObserver];
            gBridgeObserver = nil;
        }
    }
    return 0;
}
