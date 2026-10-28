# Terminal coroutine retirement

Physical build 47 reached the existing 256-entry native coroutine registry limit
with one active source and 255 completed weak tombstones. This change keeps that
limit and removes completed entries without waiting for collection. It adds no
hooks, executable writes, forced collection or managed table/export changes.
The production host/status remain 72/104 bytes; the old strong host remains
40 bytes. Device validation of this change is still required.

## Carrier identity

Registration validates the real `ArrayList+ArrayListEnumeratorSimple` class and
the existing three pinned native methods. A separate private gateway check finds
its exact nonstatic, writable `System.Object _currentElement` field. Public
runtime APIs supply the field offset, object header size and class instance size.
Their function entries must pass the existing signed-image gate. A pinned
carrier's first header word must agree with `object_get_class`. Alignment,
header/instance bounds and exact field ownership are checked before enabling
the capability; incompatible builds fail registration.

One private, real `System.Object` is created and permanently pinned. It is never
returned as source `Current` and has no per-carrier allocation or root. Terminal
cleanup writes this marker into the registered carrier's field through
`il2cpp_field_set_value_object`, then verifies the public field read. The marker
is an internal identity convention, not a boundary against arbitrary trusted
code using private-field reflection.

The source is cancelled once and its current yield is released. With the carrier
temporarily pinned, marker publication and route removal occur under the registry
mutex. Weak carrier/owner/Coroutine handles are released after unlocking. The
marker is now stored in the native object's existing GC-traced field, so keeping
old native carriers alive creates no C++ registry history. No field of an
unrelated or shared game enumerator is written.

If a barrier write or verification fails, the old routed terminal entry remains
inside the original bound and the sweep retries publication. It cannot fall
through to the native ArrayList implementation. Collected entries need no marker;
their routes are removed before cancelling abandoned source state, preserving
address-reuse behavior. Failure shutdown retains the existing exact-Coroutine
Stop, deferred executing-call cleanup and cancel-once rules.

## Terminal methods and threads

For active identities, routing still takes a temporary pin. Otherwise it checks
the cached exact class header before reading the validated aligned reference
field. A matching private marker gives the same terminal behavior:

| Call | Result |
| --- | --- |
| `MoveNext` | handled, false |
| `Current` | actual `InvalidOperationException` |
| `Reset` | actual `NotSupportedException` |
| registration in either bridge | rejected |
| unrelated/freshly reused identity | original fallthrough |

Worker checks use only cached immutable facts, aligned atomic pointer loads and
the registry mutex. They perform no IL2CPP calls or allocations. Main-thread
publication uses that same mutex; therefore a worker delayed from before a
registration cannot observe a publication gap. Source callbacks, root releases
and metadata initialization never run while holding the mutex. A live hook
receiver (or an independently pinned registration input) supplies the object's
lifetime; the marker itself stays pinned for the process. This remains specific
to the verified runtime header representation and reference-field layout.

## Registration IDs and counters

IDs are opaque and use the existing `0x50524f44` prefix with a checked 32-bit
ordinal. Both registry indexes commit before advancing the next ID. Failed
registrations leave no gaps. A previously issued ID no longer in the registry
returns `UNSUPPORTED (7)` from Acquire/Associate and `OK (0)` from Close; an
unissued or foreign-prefix ID returns `INVALID_TOKEN (9)`. Collected sources are
closed issued registrations too. The managed coroutine consumer already handles
7/9 as unavailable and Close as idempotent. This distinction costs fixed state,
not an unbounded set of retired IDs.

`entries` and `carrier_weak_roots` now count retained registry state only;
`terminal_tombstones` normally becomes zero immediately. A nonzero terminal
count means publication has been retained for safe retry. `swept` counts all
retired registry entries, including immediate completion. Gateway roots include
one fixed lifetime marker root. Active scheduling still has the same 256 bound.

## Reproducible checks

Run from the repository root, using a fresh output directory for each tool:

```sh
python3 -m unittest discover -s tests -p test_iterator_terminal_marker.py -v
python3 -m unittest discover -s tests -p test_runtime_diagnostics.py -v
python3 tools/check_production_iterator.py --source-root . --output /fresh/iterator-proof
python3 tools/check_failure_cleanup.py --source-root . --output /fresh/failure-proof
```

Owned fixtures keep 1,024 completed carriers alive beside one active source,
exercise every old terminal method, duplicate registration in both bridges,
collected IDs, failed registration/ID exhaustion, native address reuse, worker
publication exclusion, barrier-failure fallback, source/native yield cycles and
all Step/Reset/Stop/Cancel shutdown paths. The actual gateway helper is tested
against synthetic public metadata/GC APIs: bad type/offset/header, checked write
barrier with pinned arguments, contained exceptions and 10,000 terminal queries
without runtime calls. Production/legacy/gateway sources also compile for iOS
arm64 with strict warnings. These are source/ownership proofs; they do not
constitute real-game long-session or physical-device validation.

The signed build-48 iOS-on-Mac runtime also passed the owned-carrier probe in
`tests/runtime/IteratorRetirementProof.inc`. It retained all 1,024 completed
native carriers beside one active owned entry, verified every late `MoveNext`
returned false, sampled native `Current`/`Reset` exceptions and rejected
duplicate registrations. The two pre-existing source entries remained active:
the registry stayed at three entries during retention and returned to two after
cleanup. Gateway owned roots were exactly equal before and after, with no
deferred releases during the measured section. This runs the real patched
runtime with own objects; it does not create a lobby or validate a game round.
