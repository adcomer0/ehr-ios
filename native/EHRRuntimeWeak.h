#pragma once
#include "EHRRuntimeGateway.h"
#ifdef __cplusplus
extern "C" {
#endif
// Separate capability, no resize of the ABI-1 gateway table. The returned token
// owns one weak IL2CPP handle, never a strong root. It may be released/deferred
// using the ordinary object release functions. Object-using gateway calls
// promote weak inputs into call-local strong roots before allocating/invoking.
// object_retain deliberately returns a NEW strong root. A collected weak input
// returns INVALID_TOKEN; it never becomes a fabricated null object.
EHRRuntimeStatus ehr_runtime_object_weak(EHRRuntimeToken object,EHRRuntimeToken *weak);
EHRRuntimeStatus ehr_runtime_object_weak_alive(EHRRuntimeToken weak,int32_t *alive);
#ifdef __cplusplus
}
#endif
