#pragma once
#include <stddef.h>
#include <stdint.h>
#include "EHRManagedIteratorProductionV1.h"
#ifdef __cplusplus
extern "C" {
#endif
int32_t ehr_source_bind_coroutines_v1(const EHRManagedIteratorProductionV1 *,size_t);
// Manual driver of genuine native carrier methods, never Unity StartCoroutine.
// count16, return0; proof0 overall1, proof1 error0, proof2..14 must1, proof15
// dynamic-code flags0. Does not run source Main, account, network or game actions.
int32_t ehr_source_coroutines_self_test(int32_t *proof,size_t count);
#ifdef __cplusplus
}
#endif
