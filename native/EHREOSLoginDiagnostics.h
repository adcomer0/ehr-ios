#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Main-thread metadata-only preflight. 0=ready; otherwise an EHRRuntimeStatus.
// A failed preflight disables only the observation, never original forwarding.
int32_t EHREOSLoginDiagnosticsPrepare(void);
#ifdef __cplusplus
}
#endif
