#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(int32_t, EHRItchOwnershipStatus) {
    EHRItchOwnershipVerified=0,
    EHRItchOwnershipNoEntitlement=1,
    EHRItchOwnershipInvalidCredential=2,
    EHRItchOwnershipInsufficientScope=3,
    EHRItchOwnershipNetworkUnavailable=4,
    EHRItchOwnershipMalformedResponse=5,
    EHRItchOwnershipCancelled=6,
    EHRItchOwnershipLimitExceeded=7,
    EHRItchOwnershipServiceUnavailable=8,
    EHRItchOwnershipBadCredentialFormat=9,
    EHRItchOwnershipRedirectRejected=10,
    EHRItchOwnershipServerRejected=11,
};
// Only a numeric decision, HTTP status and fixed structural diagnostics leave
// this helper. No response body,
// download key, account identity, exception text or credential is exposed.
typedef void (^EHRItchOwnershipCompletion)(EHRItchOwnershipStatus status,int32_t httpStatus);
@interface EHRItchOwnershipCheck:NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
// Any thread, idempotent. Completion still runs exactly once on main.
- (void)cancel;
@end
// Copies borrowed key bytes synchronously. Only verified ownership permits the
// caller to continue. NoEntitlement means no claimed entitlement was returned;
// an unclaimed bundle may require the player to claim the game on itch.io.
// The observed API empty owned_keys object is accepted only as a negative empty
// page after valid pagination; nonempty objects never establish ownership.
// Bounded network reads only, never purchases/claims/downloads or EOS calls.
FOUNDATION_EXPORT EHRItchOwnershipCheck *EHRItchOwnershipBegin(NSData *key,
    EHRItchOwnershipCompletion completion);
// Any thread. Fixed numeric structural facts for this check's current/last
// page. Never returns response content, header values, URLs, identifiers or keys.
// Kind codes: 0 missing, 1 null, 2 object, 3 array, 4 integer, 5 other number,
// 6 boolean, 7 string, 8 other. Page values clamp to [-1000,1000] and are only
// populated for kind 4; array/object counts clamp to [0,1000].
FOUNDATION_EXPORT NSDictionary<NSString *,NSNumber *> *EHRItchOwnershipCopyDiagnostics(
    EHRItchOwnershipCheck * _Nullable check);
NS_ASSUME_NONNULL_END
