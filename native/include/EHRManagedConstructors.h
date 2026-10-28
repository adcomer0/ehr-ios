#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Six int32 outputs: pass,status,waitTime,exactClass,wrongParamRejected,innerException. */
int32_t ehr_generated_constructor_self_test(int32_t *,size_t);
#ifdef __cplusplus
}
#endif
