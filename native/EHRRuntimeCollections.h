#pragma once
#include "EHRRuntimeGateway.h"
#ifdef __cplusplus
extern "C" {
#endif
// Live managed arrays: no copied native collection masquerades as game state.
// Each nonzero returned value follows the gateway's owned strong-root contract.
// Length/index are signed managed Int32. Bounds are checked before Get/SetValue.
// This first implementation bounds arrays to 65,536 elements, invokes actual
// System.Array methods, and contains their managed exceptions through invoke.
EHRRuntimeStatus ehr_runtime_array_create(EHRRuntimeToken element_class, int32_t length,
    EHRRuntimeToken *result, EHRRuntimeToken *exception);
EHRRuntimeStatus ehr_runtime_array_length(EHRRuntimeToken array, int32_t *length,
    EHRRuntimeToken *exception);
EHRRuntimeStatus ehr_runtime_array_get(EHRRuntimeToken array, int32_t index,
    EHRRuntimeToken *result, EHRRuntimeToken *exception);
EHRRuntimeStatus ehr_runtime_array_set(EHRRuntimeToken array, int32_t index,
    EHRRuntimeToken value, EHRRuntimeToken *exception);
#ifdef __cplusplus
}
#endif
