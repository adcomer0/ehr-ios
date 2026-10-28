#pragma once
#include "EHRManagedComplexDelegateV1.h"
void EHRComplexDelegateMakeTable(EHRComplexDelegateHostV1 *);
EHRRuntimeStatus EHRComplexDelegateSetCallbacks(const EHRComplexDelegateCallbacksV1 *);
extern "C" EHRRuntimeStatus EHRComplexDelegateSweep(size_t *removed);
extern "C" uint64_t EHRComplexDelegateActiveCount(void);
extern "C" uint64_t EHRComplexDelegateWeakCount(void);
extern "C" uint32_t EHRComplexDelegateLastStep(void);
