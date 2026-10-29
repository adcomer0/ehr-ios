#pragma once
#include "EHRManagedIteratorProductionV1.h"
// Native-only route helpers. Unknown or stale recycled identities pass through.
// All raw pointers stay native. Main-thread calls pin+validate the live weak
// identity for the entire entry operation; worker calls never execute source.
bool EHRProductionIteratorOwnsIdentity(void *identity);
// Native-only main-thread cache query, no IL2CPP calls or lifecycle mutation.
// Caller holds a validated pin on the actual receiver. Unlike OwnsIdentity,
// terminal markers, closing/executing entries and sealed runtime are rejected.
bool EHRProductionIteratorHasActiveIdentity(void *identity);
bool EHRProductionIteratorMoveNext(void *identity,bool *result);
bool EHRProductionIteratorCurrent(void *identity,void **result);
bool EHRProductionIteratorReset(void *identity);
// Narrow integration adds this read-only helper to the old fixture registry so
// neither mode can claim the other's exact carrier identity.
bool EHRManagedIteratorOwnsIdentity(void *identity);

// Failure-only native cleanup. The production host table stays 72 bytes.
// Permanently rejects new source registrations; retains weak carrier identity
// tombstones until GC so surviving engine references cannot run ArrayList code.
struct EHRProductionIteratorFailureV1 {
    uint32_t abi_version,byte_size;int32_t status;uint32_t sealed;
    uint64_t entries,deferred,engine_stop_attempts,engine_stop_failures,cancel_failures;
    uint64_t active_sources,current_roots,carrier_weak_roots,association_weak_roots;
};
static_assert(sizeof(EHRProductionIteratorFailureV1)==88);
extern "C" __attribute__((visibility("default"))) EHRRuntimeStatus EHRManagedIteratorProductionFailClosed(
    EHRProductionIteratorFailureV1 *,size_t bytes);
