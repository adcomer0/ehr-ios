#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Diagnostics for the entry interceptors in the signed, local game copy.
/// Installation in a file does not count as observing a live game callback.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EHRNativeHooksCopyStatus(void);
// Native-only: existing UUID-checked base used by pre-sign diagnostic forwarders.
// Same fail-closed build-invariant behavior as the installed original routes.
FOUNDATION_EXPORT uintptr_t EHRNativeHooksImageBaseForDiagnostics(void);

#ifdef __cplusplus
}
#endif
