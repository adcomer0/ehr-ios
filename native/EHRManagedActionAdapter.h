#pragma once
#include "EHRManagedActionV1.h"
#include "EHRManagedActionFamiliesV1.h"
void EHRManagedActionMakeTable(EHRManagedActionHostV1 *);
void EHRManagedActionMakeFamiliesTable(EHRManagedActionFamiliesV1 *);
EHRRuntimeStatus EHRManagedActionSetCallbacks(const EHRManagedActionCallbacksV1 *);
// Native diagnostics and bounded main-thread GC cleanup; no object pointers.
extern "C" {
EHRRuntimeStatus EHRManagedActionSweep(size_t *removed);
uint64_t EHRManagedActionRegistrationCount(void);
uint64_t EHRManagedActionActiveCount(void);
}
