#pragma once
#include "EHRManagedBridgeV1.h"
#include "EHRManagedFacadeExtensionsV1.h"
#include "EHRManagedReflectionV1.h"
#include "EHRManagedLifetimeV1.h"
#include "EHRManagedTypeNamesV1.h"
#include "EHRManagedMethodsV1.h"
#include "EHRManagedEngineColorV1.h"

// Native-owned tables; no test methods, source startup or account actions.
struct EHRManagedFacadeTables {
    EHRManagedGatewayV1 gateway;
    EHRManagedFacadeExtensionsV1 extensions;
    EHRManagedReflectionV1 reflection;
    EHRManagedLifetimeV1 lifetime;
    EHRManagedTypeNamesV1 typeNames;
    EHRManagedMethodsV1 methods;
    EHRManagedEngineColorV1 engineColors;
};
void EHRManagedFacadeMakeTables(EHRManagedFacadeTables *);
