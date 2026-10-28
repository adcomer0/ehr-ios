#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
// Explicit XCTest/user-triggered start, never automatic at game bootstrap.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EHRManagedIteratorSchedulingBegin(void);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EHRManagedIteratorSchedulingCopyStatus(void);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EHRManagedIteratorSchedulingCancel(void);
#ifdef __cplusplus
}
#endif
