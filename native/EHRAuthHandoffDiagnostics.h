#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Optional main-thread metadata-only preparation. Failure disables scalar
// observation only; each installed forwarder still calls its original once.
int32_t EHRAuthHandoffDiagnosticsPrepare(void);
// Call only from the already-positive original Apple authorization observer.
// These record fixed numeric events; they never inspect credentials or login.
void EHRAuthHandoffDiagnosticsRecordAppleSuccess(void);
void EHRAuthHandoffDiagnosticsRecordEOSResult(uint32_t channel, int32_t status, int32_t resultCode);
// Worker-safe snapshots of owned counters. No game metadata/runtime calls.
NSDictionary<NSString *, id> *EHRAuthHandoffDiagnosticsCopyStatus(void);
// Isolated recorder fixture + readiness, no originals/authentication/game calls.
NSDictionary<NSString *, id> *EHRAuthHandoffDiagnosticsSelfTest(void);
#ifdef __cplusplus
}
#endif
