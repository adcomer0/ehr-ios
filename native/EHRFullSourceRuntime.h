#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Production bindings only. Uses exports from the single packaged full-source
// NativeAOT image. Does not call fixture setup, game UI or account operations.
FOUNDATION_EXPORT NSDictionary *EHRFullSourceBindRuntime(void);
FOUNDATION_EXPORT NSDictionary *EHRFullSourceCopyRuntimeStatus(void);
// Main-thread, bounded own source state only. Does not inspect Unity objects,
// credentials or requests. Suitable for the lightweight loading indicator.
FOUNDATION_EXPORT NSDictionary *EHRFullSourceCopySettingsLoadingStatus(void);
// Interactive launcher tick only. Passive validation never calls this; the
// optional website feature independently checks its current account gate.
FOUNDATION_EXPORT void EHRFullSourceRefreshDirectory(void);
FOUNDATION_EXPORT NSDictionary *EHRFullSourcePrepareApplication(void);
FOUNDATION_EXPORT NSDictionary *EHRFullSourceLoadApplication(void);
void EHRFullSourceBeforeTarget(uint64_t target);
#ifdef __cplusplus
}
#endif
