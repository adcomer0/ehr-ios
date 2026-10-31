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
// A call-local native pinned GC handle survives until C++ unwind. The public
// IL2CPP exception factory is used, without reflection/Activator or token-map
// allocation; no .NET frame is live. Unsupported runtime/factory states fail
// closed rather than reporting a successful iterator result.
void EHRRuntimeIteratorRaise(EHRRuntimeStatus status);
#ifdef __OBJC__
@class NSDictionary;
// Native XCTest diagnostic only, never a managed table entry. Constructs and
// catches two real runtime exceptions using owned objects; performs no game,
// source callback, account, scene, network or forced-collection operation.
extern "C" NSDictionary *EHRRuntimeIteratorExceptionSelfTest(void);
#endif
