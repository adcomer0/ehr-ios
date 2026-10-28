#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Main thread, bound native host/gateway. Returns 0 on success; exactly 8 words.
// [success, created, id, repeatedId, independentlyRetainedId,
//  DestroyRequested, wrappersDisposed, containedFailureStatus].
// Caller verifies nonzero equal signed IDs and native roots before/after, then
// yields a Unity frame for deferred Destroy. No physical destruction claim here.
int32_t ehr_ios_touch_identity_self_test_v1(int32_t *proof,size_t count);
#ifdef __cplusplus
}
#endif
