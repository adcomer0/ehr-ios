#pragma once
#import <Foundation/Foundation.h>
#include <cstdint>

// Internal native helper interfaces. No raw IL2CPP pointer crosses NativeAOT.
// Registration is explicit; there is no automatic startup call or full-EHR claim.
extern "C" {
FOUNDATION_EXPORT NSDictionary *EHRStaticComponentsRegister(void *(*lookup)(const char *));
FOUNDATION_EXPORT NSDictionary *EHRStaticComponentsProbeBegin(void);
FOUNDATION_EXPORT NSDictionary *EHRStaticComponentsProbeCopyStatus(void);
FOUNDATION_EXPORT NSDictionary *EHRStaticComponentsProbeCancel(void);
}

// The three statically linked entry wrappers call these only after any original
// required by their contract. Unknown ordinary runtime data always passes through.
bool EHRStaticComponentsType(const void *type, const void **result) noexcept;
bool EHRStaticComponentsName(const void *image, const char *space, const char *name, const void **result) noexcept;
bool EHRStaticComponentsIndex(int32_t index, const void **result) noexcept;
void EHRStaticComponentsRecordHook(unsigned hook) noexcept;
