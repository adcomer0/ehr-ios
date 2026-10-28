#pragma once
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
FOUNDATION_EXPORT NSDictionary *EHRSourcePluginOwnerProbeBegin(void);
FOUNDATION_EXPORT NSDictionary *EHRSourcePluginOwnerProbeCopyStatus(void);
FOUNDATION_EXPORT NSDictionary *EHRSourcePluginOwnerProbeCancel(void);
#ifdef __cplusplus
}
#endif
