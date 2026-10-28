#pragma once
#include "EHRRuntimeGateway.h"
// Native-only: caller supplies a real borrowed IL2CPP object from a validated
// invocation frame; null is permitted. This returns ONE new independent strong
// gateway root, or0 for null. The caller owns it and must release it exactly
// once on main (or transfer ownership under the existing owned-token contract).
// It can outlive the native frame. The input pointer remains borrowed and is
// never stored/exported; no raw pointer enters any managed table/C# ABI.
// Unity main thread and ready runtime required; not an arbitrary-pointer API.
EHRRuntimeStatus EHRRuntimeActionRootBorrowed(void *object,EHRRuntimeToken *owned);
