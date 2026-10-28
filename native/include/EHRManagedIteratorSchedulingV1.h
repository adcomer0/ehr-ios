#pragma once
#include "EHRRuntimeGateway.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct EHRManagedIteratorScheduleStateV1 {
    uint32_t abi_version, byte_size, steps, finally_count;
} EHRManagedIteratorScheduleStateV1;
// All calls require Unity main thread. Borrow carrier/wait; source owns
// independent roots through existing adapter. No native pointers cross this ABI.
int32_t ehr_iterator_schedule_create(EHRRuntimeToken carrier, EHRRuntimeToken wait, uint64_t *source_id);
int32_t ehr_iterator_schedule_snapshot(uint64_t source_id, EHRManagedIteratorScheduleStateV1 *, size_t);
int32_t ehr_iterator_schedule_close(uint64_t source_id, EHRManagedIteratorScheduleStateV1 *, size_t);
#ifdef __cplusplus
}
static_assert(sizeof(EHRManagedIteratorScheduleStateV1) == 16);
#endif
