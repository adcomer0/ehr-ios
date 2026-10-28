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
FOUNDATION_EXPORT NSDictionary *EHRFullSourcePrepareApplication(void);
FOUNDATION_EXPORT NSDictionary *EHRFullSourceLoadApplication(void);
void EHRFullSourceBeforeTarget(uint64_t target);
#ifdef __cplusplus
}
#endif
