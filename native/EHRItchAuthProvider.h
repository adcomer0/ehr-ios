#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>
#include <stdbool.h>
@class UIViewController;

// Main-thread coordination of the explicitly selected provider. Start only
// prepares metadata. A visible presenter or native capture can check a saved
// credential; manual entry and every renewal require fresh ownership before
// entering the game-owned login path. A saved bootstrap that reaches login
// before game readiness can wait up to 120 seconds for normal acquisition;
// timers never retry game login. Explicit Account sign-in can resume that same
// current attempt once per action.
FOUNDATION_EXPORT bool EHRItchAuthProviderSelected(void);
// Main thread only. Ownership alone permits the app-owned licensing cover to
// uncover native age/consent/account flows. Directory also requires the actual
// game completion for this credential. Neither function writes game auth flags.
FOUNDATION_EXPORT bool EHRItchAuthProviderOwnershipVerified(void);
FOUNDATION_EXPORT bool EHRItchAuthProviderDirectoryAllowed(void);
FOUNDATION_EXPORT int32_t EHRItchAuthProviderStart(void);
FOUNDATION_EXPORT void EHRItchAuthProviderSetPresenter(UIViewController *presenter);
FOUNDATION_EXPORT void EHRItchAuthProviderPresent(void);
// Account settings can remove only this app's remembered credential. The game
// account/session is not deleted; the user closes and reopens to sign in again.
FOUNDATION_EXPORT void EHRItchAuthProviderPresentAccount(void);
// Numeric state only. awaitingNativeLogin is a boolean and
// nativeLoginWaitSeconds is bounded to 0..120. No credentials, account
// identifiers or arbitrary errors.
FOUNDATION_EXPORT NSDictionary *EHRItchAuthProviderCopyStatus(void);
