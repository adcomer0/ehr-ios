#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
// Only numeric status leaves this adapter. Key bytes and SDK/account handles
// are never returned, logged, included in exceptions, or written to disk.
typedef void (^EHRItchAuthResultHandler)(int32_t localStatus, int32_t eosResult,
    bool resultKnown, bool originalSuccessDelivered);
int32_t EHRItchAuthPrepare(void);
int32_t EHRItchAuthSetEnabled(int32_t enabled);
// Native entry frames only: all three borrowed objects are independently rooted
// before return. UI must never retain or supply raw IL2CPP pointers.
int32_t EHRItchAuthCapture(void *manager, void *originalSuccessDelegate,
                         void *originalFailureAction);
// Renewal uses the existing AOT silent method through the public Delegate
// factory. It neither constructs a game owner nor requests Apple credentials.
int32_t EHRItchAuthCaptureSilent(void *manager);
// Entered native silent frame only. Reads only already initialized native data;
// never invokes a class initializer or loads/constructs account data.
int32_t EHRItchAuthIsGuestSilentPath(void *manager, bool *isGuest);
// Key is borrowed for this call only and copied synchronously. The adapter
// wipes its copy after EOS_Connect_Login returns. No credential is cached here.
int32_t EHRItchAuthBegin(NSData *UTF8Key, bool resultOnly);
// Explicit human confirmation only. Delivers the retained genuine InvalidUser
// result through the original game callback; never fabricates SDK success.
int32_t EHRItchAuthConfirmNewUser(void);
// Exact native migration entry wrapper only: ordinary flows return OK. A
// confirmed new-profile flow must still satisfy the game's no-migration case.
int32_t EHRItchAuthCheckNewUserMigration(void *manager);
// Cancellation retains at most one KEYLESS resumption context when the exact
// original normal acquisition is still pending. SetEnabled(0) releases it.
int32_t EHRItchAuthCancel(void);
int32_t EHRItchAuthRequestPlatformLogin(void);
void EHRItchAuthSetResultHandler(EHRItchAuthResultHandler handler);
// Called only AFTER the unmodified normal final-account method returns.
void EHRItchAuthObserveFullCompletion(void *manager);
// Any-thread: fixed numeric atomics only; no runtime, account or Unity reads.
NSDictionary<NSString *, id> *EHRItchAuthCopyStatus(void);
// Own default-value SDK marshal probe only: no login, game callback or account
// handle is invoked. Requires successful passive preparation.
NSDictionary<NSString *, id> *EHRItchAuthSelfTest(void);
#ifdef __cplusplus
}
#endif
