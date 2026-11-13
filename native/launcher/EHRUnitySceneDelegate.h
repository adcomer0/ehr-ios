#pragma once
#import <UIKit/UIKit.h>
#import "EHRUnityFrameworkAPI.h"
#include <stdint.h>

// One original host scene attaches Unity's existing public app-controller
// window. It does not create a Unity window/root, start another application
// loop, inspect ivars, or alter game/account state.
// Initial foreground invokes Unity's existing idempotent initializer, validated
// by Objective-C ABI and the configured framework's loaded image. Attachment
// waits until the original first active callback returns. Initial foreground
// is not synthesized as a legacy app resume; later lifecycle events forward.
@interface EHRUnitySceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong,nullable) UIWindow *window;
@end

#ifdef __cplusplus
extern "C" {
#endif
// Call on main before Unity's runUIApplicationMain entry. appController may
// still be nil here. Repeating the same framework is idempotent; replacement
// is rejected. Returns0 success,2wrongthread,4badargument,7alreadyconfigured.
__attribute__((visibility("default"))) int32_t EHRUnitySceneConfigure(id<EHRUnityFrameworkPublicAPI> _Nonnull framework);
// Atomic, fixed numeric fields only. Safe on a diagnostics worker; never
// queries UIKit/Unity or returns addresses, scene identifiers or strings.
__attribute__((visibility("default"))) NSDictionary<NSString *,id> * _Nonnull EHRUnitySceneCopyStatus(void);
#ifdef __cplusplus
}
#endif
