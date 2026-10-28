#pragma once

#import <Foundation/Foundation.h>
#include <mach-o/loader.h>

/*
 * Original, minimal declaration adapter for Unity's published Objective-C API.
 * This is not a copy of the game's launcher, Unity implementation, or game code.
 * No direct UnityFramework class reference is emitted: NSBundle resolves the
 * framework's principal class at runtime after normal signed-bundle loading.
 *
 * Public selector/signature reference (verified 2026-10-28):
 * https://docs.unity3d.com/6000.0/Documentation/Manual/UnityasaLibrary-iOS.html
 * The class is declared by Unity in UnityFramework/UnityFramework.h. This
 * protocol reproduces only the call signatures needed by this original host;
 * opaque object return types are ABI-compatible with UnityFramework* and
 * UnityAppController*, respectively. Unity's implementation is not included.
 *
 * Unity's own public NSBundle/getInstance/setExecuteHeader loading example:
 * https://github.com/Unity-Technologies/uaal-example/blob/master/docs/ios.md
 * https://github.com/Unity-Technologies/uaal-example/blob/master/NativeiOSApp/NativeiOSApp/MainViewController.mm
 */

#if __LP64__
typedef struct mach_header_64 EHRMachHeader;
#else
typedef struct mach_header EHRMachHeader;
#endif

@protocol EHRUnityFrameworkPublicAPI <NSObject>
+ (id<EHRUnityFrameworkPublicAPI>)getInstance;
- (id)appController;
- (void)setExecuteHeader:(const EHRMachHeader *)header;
- (void)setDataBundleId:(const char *)bundleId;
- (void)runUIApplicationMainWithArgc:(int)argc argv:(char *[])argv;
@end

/*
 * Optional bridge supplied by a separately compiled original implementation.
 * The host calls it once on the main queue, after UIKit posts its completed
 * launch notification. IL2CPP may still be initializing: the bridge must wait
 * for the existing domain before game access. No hook implementation is here.
 * The host looks up EHRLiveBridgeStart with dlsym after framework loading; a
 * missing export is valid and leaves the Unity host fully independent.
 */
