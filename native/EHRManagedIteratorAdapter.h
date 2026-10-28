#pragma once
#include "EHRManagedIteratorV1.h"
void EHRManagedIteratorMakeTable(EHRManagedIteratorHostV1 *);
EHRRuntimeStatus EHRManagedIteratorSetCallbacks(const EHRManagedIteratorCallbacksV1 *);
uint64_t EHRManagedIteratorRegistrationCount(void);
uint64_t EHRManagedIteratorCurrentRootCount(void);
// Called by the three exact typed pre-sign hooks. False means original native
// trampoline. True means registered identity, including completed/error state.
bool EHRManagedIteratorMoveNext(void *identity, bool *result);
bool EHRManagedIteratorCurrent(void *identity, void **result);
bool EHRManagedIteratorReset(void *identity);
