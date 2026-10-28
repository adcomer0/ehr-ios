#pragma once
#import <Foundation/Foundation.h>
#include "EHRSourceComponentABI.h"
#ifdef __cplusplus
// Called only by the exact owned static class callbacks, after existing self,
// MethodInfo and main-thread validation. Raw self never crosses NativeAOT.
void EHRSourceComponentConstruct(uint32_t type_id,void *borrowed_self) noexcept;
void EHRSourceComponentEvent(uint32_t type_id,uint32_t message,void *borrowed_self) noexcept;
extern "C" {
#endif
FOUNDATION_EXPORT NSDictionary *EHRSourceComponentsBind(void *managed_bind_export);
FOUNDATION_EXPORT NSDictionary *EHRSourceComponentsCopyStatus(void);
FOUNDATION_EXPORT NSDictionary *EHRSourceComponentsCloseAll(void);
#ifdef __cplusplus
}
#endif
