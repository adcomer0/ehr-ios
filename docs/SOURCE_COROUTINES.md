> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

This package replaces the compiler-only WrapToIl2Cpp declaration with a production
source IEnumerator bridge. It targets the separately frozen native weak-carrier
table EHRManagedIteratorProductionV1 (72 bytes; per-entry callbacks32). It leaves
the earlier strong, explicitly closed proof table unchanged.

ProductionCoroutines retains CLR source state while its real native ArrayList
enumerator is alive. Native storage owns only weak carrier/owner/coroutine
associations. Every temporary proxy receives a new independently owned root;
disposing a proxy releases that root and never cancels Unity scheduling. A CWT
preserves exact source identity for repeated wraps and Main.StopCoroutine(source).
The native bounded main-thread weak sweep closes abandoned registrations once.
Terminal native identity remains a tombstone: MoveNext=false, Current invalid,
Reset unsupported. Its [private carrier marker](ITERATOR_RETIREMENT.md) now lets
the bounded native registry retire completed entries without waiting for GC.
Managed registration is removed before source Dispose, even
if Dispose throws. Nested CLR iterators become actual child carriers; ancestry
and native current-root cycles are rejected instead of retaining a cycle.

The narrow source adapter adds association bookkeeping after successful real
Unity StartCoroutine, and closes matching registrations only after the real
StopCoroutine/StopAllCoroutines call succeeds. It adapts exactly Main's existing
IEnumerator stop overload to recover the same carrier identity. It does not add
unverified engine hooks. Calls to native Stop elsewhere can stop scheduling
without an immediate managed Dispose; weak collection is the fallback. The
pinned PC BepInEx Il2CppManagedEnumerator likewise has no Dispose method, so an
immediate finally guarantee would exceed the verified upstream contract.

Regeneration uses tools/adapt_coroutine_ownership.py --kind surface or main
--input INPUT --expected-sha256 HASH --output FRESH. Surface input must be the
reviewed generated source surface with the real four native scheduler overloads;
Main input must already have the native sandbox DataPath and static-owner
adaptation. Both transformations preserve actual native calls and reject changed
anchors, repeated adaptation and changed input hashes. No canonical files change.

The managed export ehr_source_bind_coroutines_v1 binds exactly one table. The
separate ehr_source_coroutines_self_test(proof16,16) manually drives genuine
native carrier methods with original own iterators: null/Unicode-NUL/nested
scalar yields, exact identity, proxy release, complete/finally/cancel once and
terminal semantics. It does not execute source Main.Load, Unity scheduling,
network, accounts or gameplay. It has compiled/published with all EHR sources;
actual full-image runtime proof remains the parent's next integration check.

Four ownership adapter regression tests pass; the complete source build has zero
C# errors and publishes ios-arm64 NativeAOT without game reference DLLs. This is
an integration milestone, not a claim of full EHR feature/gameplay parity.
