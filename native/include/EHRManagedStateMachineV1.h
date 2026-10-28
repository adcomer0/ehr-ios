#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// pass,status,initial states,independent field writes,null native owners,
// mismatched iterator rejected,unmapped owner rejected. The two private
// iterator constructors run; neither factory nor MoveNext is invoked.
int32_t ehr_generated_state_machine_self_test(int32_t *proof,size_t count);
#ifdef __cplusplus
}
#endif
