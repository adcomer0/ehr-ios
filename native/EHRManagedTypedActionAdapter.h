#pragma once
#include "EHRManagedTypedActionV1.h"
void EHRManagedTypedActionMakeTable(EHRManagedTypedActionHostV1 *);
EHRRuntimeStatus EHRManagedTypedActionSetCallbacks(const EHRManagedTypedActionCallbacksV1 *);
extern "C" {
EHRRuntimeStatus EHRManagedTypedActionSweep(size_t *removed);
uint64_t EHRManagedTypedActionRegistrationCount(void);
uint64_t EHRManagedTypedActionActiveCount(void);
uint32_t EHRManagedTypedActionLastStep(void);
}
