#pragma once
#include "EHRRuntimeGateway.h"
// Native-only bridge. These are never entries in the managed function table.
EHRRuntimeStatus EHRRuntimeIteratorPin(EHRRuntimeToken borrowed, EHRRuntimeToken *owned, void **identity);
EHRRuntimeStatus EHRRuntimeIteratorBorrow(EHRRuntimeToken borrowed, void **object);
// Raises an actual IL2CPP exception only AFTER the managed callback returned.
// A local owning root survives until native C++ unwind; no .NET frame is live.
void EHRRuntimeIteratorRaise(EHRRuntimeStatus status);
