#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Uses existing gateway/reflection/method/value/type-name tables; adds no table.
// proof[7]: pass,status,builderUnicodeIdentity,queueBoxedValueFIFO,clear,
// originalEmptyQueueException,existingFuncBoolMetadata. Last slot proves only
// delegate metadata; no native source callback or existing Func.Invoke is tested.
int32_t ehr_generated_system_types_self_test(int32_t *proof,size_t count);
#ifdef __cplusplus
}
#endif
