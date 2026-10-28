#pragma once
#include <stdint.h>
// Main-thread installation. 0=installed/idempotent, 1=wrong thread,
// 2=runtime/image pin not ready or invalid, 3=class absent, 4=method mismatch.
// This observer never starts, retries, cancels, or suppresses authentication.
int32_t EHRAppleAuthDiagnosticsInstall(void);
#ifdef __OBJC__
@class NSDictionary;
// Fixed keys and numeric values only. Does not access credentials or userInfo.
NSDictionary *EHRAppleAuthDiagnosticsCopyStatus(void);
#endif
