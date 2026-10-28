> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

This stage is a separate production lifetime mode for the already proved native
ArrayListEnumeratorSimple carrier. It does not replace the old strong fixture ABI
and does not add native entry hooks. It is not a gameplay or full EHR completion
claim. No game bytes are included; no canonical source is changed by the tools.

Run tools/check_production_iterator.py --source-root /path/to/current/EHR-iOS
--output /fresh/output to regenerate a narrow adapter overlay, compile both
actual source files for iOS arm64 with -Wall -Wextra -Werror, and run owned native
fixtures. The overlay adds production routing before the old adapter and mutual
exact-identity exclusion. Compile BOTH the new EHRManagedIteratorProduction.mm
and the narrowly adapted old EHRManagedIteratorAdapter.mm. Existing three exact
iterator hooks stay unchanged. Registration returns Unsupported when the generated
EHR_HAS_ITERATOR_HOOKS binding is absent; production validation still requires the
exact live carrier class and all three pinned native method associations.

EHRManagedIteratorProductionMakeTable fills the independent 72-byte table. Its
header describes every borrowed/owned token. Register copies a 32-byte callback
table PER ENTRY, so different permanently loaded NativeAOT images can coexist.
The old host40/callback32/core152 byte layouts remain unchanged. The new104-byte
status records source, tombstone, current, weak-root and temporary-pin counts.
The header must be the sole source of field order and function signatures.

Registry ownership is weak for the carrier. Acquire gives the caller a fresh
independent strong carrier root; a managed ConditionalWeakTable may remember the
registration ID but must never cache a strong carrier proxy. Every hook acquires
a temporary strong pin and verifies the exact registered identity before source
execution. Unknown or recycled identities pass through to the native original.
Worker calls are contained without touching IL2CPP/source. Current's independent
strong root survives repeated Current queries until next step/cancel. Cyclic
registered-carrier Current-root graphs are rejected, preventing a registry-created
strong cycle. The managed nested-source adapter must also reject source ancestry
cycles and close its active child explicitly when resumed/cancelled.

Normal completion, explicit close and failure each call the source Cancel callback
once. That callback must remove its managed registration before Dispose, including
when Dispose throws. Completed native carriers now retain a private terminal
marker in their existing field while their registry slots/weak handles retire:
MoveNext=false, Current invalid, Reset unsupported. The existing bound remains256.
See [terminal retirement](ITERATOR_RETIREMENT.md) for exact runtime layout/barrier
checks, safe publication-failure fallback and owned churn tests. A closed or
collected issued registration returns7 from Acquire; an unissued ID returns9.
No native source callback is
run after it has been marked closed. Active Reset uses the original source callback.

A 0.25-second main-thread timer automatically sweeps16 entries per tick, rotating
through the bounded256-entry registry. Explicit Sweep accepts1..256. It removes a
collected identity route before disposing abandoned source, so allocator-address
reuse cannot route into prior state. There is no proxy-finalizer early cancellation.

Associate records weak MonoBehaviour owner/Coroutine matching keys only after
actual StartCoroutine succeeds. It validates exact Coroutine type and the inherited
MonoBehaviour StartCoroutine method identity. Successful real StopCoroutine or
StopAllCoroutines must precede Close/CloseMatching. Match kinds are1Carrier,
2Coroutine,3Owner. Association wrapper GC alone does NOT cancel scheduling: Unity
can still schedule while those wrappers are unreferenced. Carrier abandonment is
the automatic lifetime signal. Explicit source owner teardown should stop actual
Unity work and then close matching registrations.

Owned fixtures execute the actual production adapter, and a second fixture links
the actual old+new adapter sources to prove routing/identity exclusion while
preserving old fixture semantics. Fake objects/handles represent only an owned
test universe, not a game simulator or live IL2CPP proof. They cover temporary
pins, independent roots, repeated Current, terminal cleanup, callback-image
coexistence, abandon/GC, weak association semantics, explicit Stop matching,
reentrancy, native Current cycles, worker containment, fair sweep and no-hook
rejection. The real Unity/source scheduling test and production NativeAOT binding
remain the parent's next actual runtime gate.
