#pragma once
#include "EHRManagedIteratorV1.h"
#ifdef __cplusplus
extern "C" {
#endif
enum EHRProductionIteratorMatch { EHR_ITERATOR_MATCH_CARRIER=1, EHR_ITERATOR_MATCH_COROUTINE=2, EHR_ITERATOR_MATCH_OWNER=3 };
typedef struct EHRProductionIteratorStatusV1 {
    uint32_t abi_version, byte_size;
    uint64_t entries, active_sources, terminal_tombstones, current_roots;
    uint64_t carrier_weak_roots, association_weak_roots, temporary_pins;
    uint64_t created, swept, closed, callback_failures, rejected_thread_calls;
} EHRProductionIteratorStatusV1;
// Separate production mode. The old strong, explicitly closed fixture ABI is
// unchanged. Register BORROWS the carrier and COPIES the callbacks for this entry.
// It owns only a weak carrier handle, never a permanent strong carrier proxy.
typedef struct EHRManagedIteratorProductionV1 {
    uint32_t abi_version, byte_size;
    int32_t (*register_carrier)(EHRRuntimeToken carrier,uint64_t source_id,
                               const EHRManagedIteratorCallbacksV1 *callbacks,uint64_t *registration);
    int32_t (*acquire)(uint64_t registration,EHRRuntimeToken *owned_carrier);
    int32_t (*close)(uint64_t registration);
    int32_t (*associate)(uint64_t registration,EHRRuntimeToken owner,EHRRuntimeToken coroutine);
    int32_t (*close_matching)(uint32_t kind,EHRRuntimeToken object,uint32_t *closed);
    int32_t (*sweep)(uint32_t maximum_scan,uint32_t *scanned,uint32_t *pruned);
    int32_t (*is_main)(void);
    int32_t (*copy_status)(EHRProductionIteratorStatusV1 *,size_t bytes);
} EHRManagedIteratorProductionV1;
// Acquire returns a NEW strong root for an active live entry:7 previously issued
// and closed/collected,9 never issued. Close is idempotent for issued IDs. A fixed
// contiguous ID range records this distinction without a growing history map.
// Successful engine Stop precedes Close/CloseMatching. Close marks the exact
// native carrier terminal and retires its registry slot; publication failure
// retains a safe routed tombstone for retry. Owner/Coroutine associations
// are weak matching keys; their wrapper GC alone never cancels Unity scheduling.
// Sweep is main-thread, bounded1..256, and cancels an abandoned source exactly once.
__attribute__((visibility("default")))
void EHRManagedIteratorProductionMakeTable(EHRManagedIteratorProductionV1 *);
#ifdef __cplusplus
}
static_assert(sizeof(EHRManagedIteratorProductionV1)==72);
static_assert(sizeof(EHRProductionIteratorStatusV1)==104);
#endif
