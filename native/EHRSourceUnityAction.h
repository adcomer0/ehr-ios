#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Separate genuine native UnityEvent; no scene UI or Main is touched.
// count10: return0, proof0=1, proof1=0, proof2..8=1, proof9 dynamicCodeFlags0.
int32_t ehr_source_unity_action_self_test(int32_t *proof,size_t count);
#ifdef __cplusplus
}
#endif
