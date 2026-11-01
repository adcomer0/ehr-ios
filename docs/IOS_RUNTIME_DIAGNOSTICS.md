> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Native runtime diagnostics

The native helper records bounded numeric evidence for the physical-device
startup and lobby-transition investigation. It changes no startup, metadata,
account, callback or exception-handling decisions. It requires no new NativeAOT
export. Candidate44 remains frozen; these records first accompany the next
native diagnostic build.

The app writes its own `Library/Caches/EHRDiagnostics/runtime-native-v1.json`
approximately every two seconds. The serial worker reads only copied numbers;
it never calls IL2CPP, source code, UIKit, or account APIs. A complete private
temporary snapshot is renamed over the previous regular snapshot. Source files
are never read or changed by this writer. The snapshot is capped at 512 KiB.
Directory/file opens reject symlinks, and an existing destination must be a
regular file with one hard link. No arbitrary text, exception messages, source
arguments, object addresses, GC tokens, player/account identifiers, or URLs are
serialized. The path is relative to this independently installed app container.

`EHRFullSourceCopyRuntimeStatus().numericDiagnostics` also exposes the same
numeric schema plus `writeStatus` and `writtenSequence`. Writer status 0 means a
complete snapshot was renamed successfully; 1 means no write has finished; 7 is
a filesystem/serialization failure; 8 is the size/allocation limit. A snapshot
can be up to two seconds behind the process. A process termination before its
first write leaves no new snapshot. It is not a crash handler.

Each of at most 384 routes retains checks, active checks, wrong-thread checks,
source starts/completions/failures, unentered fallback count, last status, and
last begin/end sequence and monotonic timestamp. This survives replacement of
the 128 recent events by frequent updates. Thirty-two failure events have their
own bounded ring. `unknownRoutes` reports a conflicting route RVA or overflow;
it does not silently merge conflicting sites. The current catalog has 298
targets. Route IDs and method RVAs come from the compiled, pinned catalog.

Event kinds are:

| Kind | Meaning | ID/detail |
|---|---|---|
| 1/2 |Source route begin/end|Target ID/method RVA|
| 3 |Startup publication|Detail is stage number|
| 4/5 |Component callback begin/end|Source type ID/message number|
| 6 |Apple error observation|Detail is fixed domain enum; status is numeric code|
| 7/8 |Source iterator callback begin/end|Own registration ID; operation 1 step, 2 reset, 3 cancel|
| 9 |First native route decision|Target ID; flag 1 enabled; status 2 wrong thread|

Route end flags are bit values: 1 dispatcher entered, 2 rooted native exception
present, 4 original attempted, 8 runtime invoke entered, 16 original permit
consumed, 32 one or more original hook consumptions, 64 target found. Bit 32 is a
boolean observation, not an exact consumption count. Once dispatcher entered,
the original is never retried after failure. Diagnostics preserve that rule.
The original native exception is still raised after managed/native cleanup;
other failures still use the existing native status exception path.

Startup stages are 1 runtime initialization, 2 full source image, 3 facade tables,
4 callbacks, 5 production iterators, 6 source components, 7 touch renderer,
8 compiled targets, 9 source application host, 10 all tables bound, 11 bind
failure, 12 prepare, 13 Main.Load, 14 startup failure, 15 callbacks active. The
application record includes readiness flags, actual source state, options
loaded/count, active bindings, candidates and post-load completion.

Apple fields contain only the observer install result, fixed error-domain enum,
numeric error code, error count, and request/success/error/overlap counters.
They distinguish an authorization success callback from an error callback;
QuickLogin may return an Apple ID or password credential, and the observer never
inspects which credential was returned. A success callback is not proof of an
Apple ID token or EOS acceptance.
they do not establish backend authentication success. Original authentication
callbacks continue unchanged. The observer is independently pinned and may
report that installation was unavailable.

The recorder identifies a failed target and bridge phase; it does not retain
arbitrary source exception text or the precise failing source statement. Join
target IDs to the exact private compiled catalog offline to identify callback
descriptors. An entered route without completion can indicate a call that did
not return; a live main-thread/UI status panel is separate evidence and should
not be described as a main-thread hang.

Validation:

```sh
python3 -m unittest discover -s tests -p test_runtime_diagnostics.py -v
python3 -m unittest discover -s tests -p test_native_typed_thunks.py -v
```

The first command executes the bounded ring/concurrent snapshot fixture and
the actual Foundation JSON serializer against an exact allowed-key schema.
Neither fixture starts the writer, loads the game, accesses an app container,
or presents UI. Modified native translation units also compile for real
iphoneos arm64 with ARC and `-Wall -Wextra -Werror`. Actual physical route
behavior remains to be observed in the diagnostic build.

## Limit and predispatch diagnostics

The additive v1 fields require only a native rebuild; no managed export or table
layout changes. Existing guards, statuses, exception handling, auth checks, and
original fallback remain unchanged. No capacity is raised and no GC collection
is requested.

Each route now has `lastPhase` and one-based `lastArgument` (0 means none). The
failure event also retains these when later successful calls replace the route
summary: `detail & 65535` is the phase and `detail >> 16` is the argument index.

| Phase | Existing operation being checked |
|---|---|
|1|Main thread|
|2|Prepared site lookup|
|3|Argument count/span|
|4|Runtime API availability|
|5|Return storage|
|6|Argument descriptor/input storage|
|7|Output storage/overlap|
|8|Input/output overlap|
|9|Copy-buffer allocation/capacity|
|10|Receiver present|
|11|Receiver metadata borrow|
|12|Receiver assignability/rooting|
|13|Reference argument assignability/rooting|
|14|Value argument boxing/rooting|
|15|Managed dispatcher returned a failure|
|16|Dispatch proof validation|
|17|Reference output copyback|
|18|Return conversion|
|19|Validated output commit|

Thus status 5 with phase 12 means receiver assignability failed; phase 13 with
argument 2 means the second reference argument failed. This reports a bridge
boundary, not a source statement or a justification to relax type checking.
Successful calls normally finish at phase 19. Reentrant route/iterator scopes
restore the prior thread-local context; worker contexts remain independent.

`guards` is a separate 32-record ring, `guardTotal` is cumulative, and event kind 10
marks an observed LIMIT guard. Each record contains numeric category, count,
limit, route/RVA, own iterator registration, phase, and argument. Categories are:

|Category|Existing guard|
|---|---|
|1/2/3|Strong/weak/pinned root capacity 65536|
|4|Pinned-root token exhaustion|
|5|Per-call weak promotion capacity 129|
|6|Deferred queue capacity 65536|
|7|Value payload size|
|8|Non-query value-copy output capacity|
|9/10|String length/non-query output capacity|
|11/12|Type-name length/non-query output capacity|
|13/14|Nested depth 32/assembly count 512|
|15/16/17|Nested/member method/field scan bound 65536|
|18/19|Native iterator registry 256/token exhaustion|
|20|Iterator registry allocation failure|
|21/22|Thunk copy bytes 65536/allocation failure|
|23|Managed iterator Step returned LIMIT; exact guard unknown|
|24|Contained native iterator C++ exception mapped to LIMIT|

A zero `limit` explicitly means no numeric bound was observed. In particular,
category 23 must never be presented as proof that the managed 256-source limit
was reached. The managed Wrap source count and its exception origin cannot be
read by this native-only diagnostic. The native registry includes terminal
weak-carrier tombstones, so its entries differ from active managed sources.
Expected zero-capacity buffer-size queries retain LIMIT but do not fill the
guard ring. Unknown allocation/managed limits remain possible.

`gateway` is a numeric snapshot copied only on main: root/weak-root count and
capacity, deferred depth/capacity/high-water, cumulative enqueued/dequeued/freed
counts and full-queue observations. `observedRootHighWater` is the maximum
sampled root count, not an exact allocation peak. Dequeued counts include stale
queued IDs; freed counts include only actual root removals. Enqueues remain
any-thread and touch only their existing queue lock. The snapshot publisher does
not initialize IL2CPP, read objects, invoke methods, collect, or drain releases.
Copies occur at main-thread full-source status publication, native limit guards,
completed deferred drains, iterator registration/quarter-second sweeps, and
failed iterator callbacks. The writer reads only these already-copied numbers.

`productionIterators` copies registry entries, active sources, terminal
carriers, held-root counts, pins and lifecycle counters on main. Each guard
freezes the latest copied gateway/iterator counts with their own snapshot
monotonic timestamps. A zero timestamp means no corresponding sample existed;
compare timestamps before treating a sample as contemporaneous.

The five diagnostic tests include the actual production thunk preflight with
synthetic receiver/argument metadata, actual gateway guards with synthetic root
and deferred state, production iterator lifecycle/fallthrough plus returned
LIMIT and registry-capacity cases, the concurrent bounded recorder, and actual
Foundation JSON serialization. Mock GC/free APIs remain in the owned fixtures;
no game, source callbacks, account, container or UI is used. Test output is not
physical-device failure evidence. The next phone snapshot must establish which
boundary/guard actually failed before any corrective behavior is selected.

## Settings and UI progress

Build 65 adds numeric `settingsLoading`, `uiHeartbeat` and
`snapshotMonotonicNs` fields. The lightweight main-thread timer reads only the
managed settings builder's own state. The writer serializes its copied sample,
never reads Unity UI from its worker. Entered/completed monotonic timestamps and
counts can distinguish a missing later UI tick from an unfinished sampled tick;
background state and sample age must be considered. They do not identify a
blocking call or establish a freeze's cause.

When search is compiled, `lobbySearch` records schema-2 selection and forwarding
counters, without room, player, response or credential content. This makes a
future empty-list reproduction distinguish a request that never reaches the
search helper from one forwarded in All mode or augmented in EHR mode.
