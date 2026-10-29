#pragma once
#include "EHRRuntimeGateway.h"
// Native-only bridge. These are never entries in the managed function table.
EHRRuntimeStatus EHRRuntimeIteratorPin(EHRRuntimeToken borrowed, EHRRuntimeToken *owned, void **identity);
EHRRuntimeStatus EHRRuntimeIteratorBorrow(EHRRuntimeToken borrowed, void **object);
// Main-thread metadata/marker preparation does not modify the carrier. Terminal
// publication uses the runtime reference write barrier on a pinned owned carrier.
EHRRuntimeStatus EHRRuntimeIteratorTerminalPrepare(EHRRuntimeToken carrier);
EHRRuntimeStatus EHRRuntimeIteratorMarkTerminal(EHRRuntimeToken carrier);
// Any-thread, allocation-free: exact cached class header precedes field access.
// Caller must supply a live method receiver or independently pinned object.
bool EHRRuntimeIteratorIsTerminal(const void *identity) noexcept;
// Raises an actual IL2CPP exception only AFTER the managed callback returned.
// A local owning root survives until native C++ unwind; no .NET frame is live.
void EHRRuntimeIteratorRaise(EHRRuntimeStatus status);
