#pragma once
#include "EHRRuntimeGateway.h"
#ifdef __cplusplus
extern "C" {
#endif
// Main-thread, exact signed-image gate. This calls Unity2022.3's engine icall,
// never inventing a missing managed MethodInfo. rgba is R<<24|G<<16|B<<8|A,
// independent of native byte order. Null string tokens are managed null.
// All outputs are zero on preflight failure; absent icall is NOT_FOUND.
EHRRuntimeStatus ehr_runtime_color_parse_html(EHRRuntimeToken text,
    int32_t *parsed, uint32_t *rgba);
#ifdef __cplusplus
}
#endif
