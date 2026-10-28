#pragma once
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
FOUNDATION_EXPORT NSDictionary *EHRManagedSourceComponentProbeBegin(void);
FOUNDATION_EXPORT NSDictionary *EHRManagedSourceComponentProbeCopyStatus(void);
FOUNDATION_EXPORT NSDictionary *EHRManagedSourceComponentProbeCancel(void);
#ifdef __cplusplus
}
#endif
