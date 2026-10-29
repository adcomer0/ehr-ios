#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Metadata-only preparation; EHRRuntimeStatus. Does not inspect an account.
int32_t EHRAuthRetryGuardPrepare(void);
// Main-thread, explicit activation only after preflight. Default is disabled.
int32_t EHRAuthRetryGuardSetEnabled(int32_t enabled);
// Explicit startup request; 0 leaves the initial disabled state untouched.
// 1 prepares metadata before SetEnabled(1). No auth or account invocation.
int32_t EHRAuthRetryGuardStart(int32_t requested);
// Fixed numeric own status; no account identity, tokens, strings or credentials.
NSDictionary<NSString *, id> *EHRAuthRetryGuardCopyStatus(void);
#ifdef __cplusplus
}
#endif
