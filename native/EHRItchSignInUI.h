#pragma once
#import <Foundation/Foundation.h>
#import "EHRItchOwnership.h"
#include <stdint.h>
#include <stdbool.h>
@class UIViewController;

NS_ASSUME_NONNULL_BEGIN
// Called on main. Non-null bytes are borrowed for this callback only: the
// runtime must synchronously copy them. Nil means explicit cancel/timeout and
// must restore the captured ordinary failure flow. Never log the credential.
typedef void (^EHRItchSignInSubmit)(NSData * _Nullable key);
FOUNDATION_EXPORT void EHRItchSignInPresent(UIViewController *presenter, EHRItchSignInSubmit submit);
// Account settings never deletes a profile or resets game data. An unsigned
// screen may offer an explicit signIn callback, invoked after dismissing once.
// After explicit confirmation and own-service Keychain removal, clearSession
// runs once on main to forget only the provider's in-memory credential. Return
// a numeric status; the UI asks the player to close and reopen the app itself.
FOUNDATION_EXPORT void EHRItchSignInPresentAccount(UIViewController *presenter,
    bool fullGameCompleted, int32_t (^clearSession)(void),
    void (^ _Nullable signIn)(void));
// Main-queue serialized. Only all three success conditions permit 'signed in'
// or optional storage. EOS-only acceptance is not complete game authentication.
// EOS3 can finish only after this controller explicitly confirmed a new profile.
FOUNDATION_EXPORT void EHRItchSignInUpdateResult(int32_t localStatus,int32_t eosResult,bool fullGameCompleted);
// Main-queue serialized and bound by the provider to this pending credential.
// Verification enables only the existing game sign-in flow. A failed ownership
// check wipes the pending UI copy and permits a fresh attempt; it never saves.
FOUNDATION_EXPORT void EHRItchSignInUpdateOwnership(EHRItchOwnershipStatus status,
    int32_t httpStatus,bool pending);
// The current pending key attempt has a genuine missing-user continuation.
// Offering never calls confirm. The explicit button calls it once; return 0
// means only that the original new-profile flow started, never authentication.
// Cancellation still uses the original submit(nil). No linking/merging API.
FOUNDATION_EXPORT void EHRItchSignInOfferNewProfile(int32_t (^confirm)(void));
// Fixed numeric diagnostics only. No key, account identifiers, URLs or errors.
FOUNDATION_EXPORT NSDictionary *EHRItchSignInCopyStatus(void);
// This app's explicitly remembered key only; no shared group/synchronization.
// Caller must copy synchronously if retaining and wipe this mutable return.
FOUNDATION_EXPORT NSMutableData * _Nullable EHRItchSignInCopySavedKey(void);
NS_ASSUME_NONNULL_END
