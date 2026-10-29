> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Failure-only source startup cleanup

The current source load creates Unity components and starts source coroutines before its final patch activation. A later startup failure must retire that partial plugin. This package changes only the native failure path. It performs no account, login, network, file, or gameplay command.

`EHRFullSourceFailureCleanup()` first deactivates all source target dispatch, then hides only the owned source UIKit controls with the existing touch table. It permanently seals production iterator registration, stops each actually associated returned `UnityEngine.Coroutine` through caught exact `MonoBehaviour.StopCoroutine(Coroutine)`, then cancels each source exactly once. It continues after stop/cancel errors. It destroys the owned source component GameObject and releases source state/Scene callback scopes, then takes a final iterator snapshot. It never stops unrelated native coroutines on a shared owner.

Executing Step/Reset is marked for deferred retirement. The source callback finishes before Cancel, and a retiring MoveNext returns false. Cleanup may report deferred entries while that callback is still running. Repeating cleanup is supported; restarting this failed plugin is not.

The existing production table remains 72 bytes and status remains 104 bytes. The separate native failure helper adds an 88-byte report. [Terminal carrier markers](ITERATOR_RETIREMENT.md) now preserve later terminal native calls while allowing immediate registry/weak-handle retirement after cancellation. Publication failure retains a safe bounded routed tombstone for retry. No source, current or owner/Coroutine association roots survive normal retirement. The owned fixture proves registry/weak/current/association roots zero even while external roots still retain completed carriers.

The cleanup is integrated in the canonical native source. No new compilation
unit, managed ABI or native scheduler hook was added. FullRuntime invokes it only
after source Load failure, preserving the original error and reporting cleanup.
The historical composition receipts remain outside Git.

Check the integrated implementation directly:

```sh
python3 tools/check_failure_cleanup.py --source-root /path/to/ehr-ios --current-native --generated-headers /absolute/Candidate37 --output /absolute/fresh/checks
```

Validation covers normal/deferred Step/deferred Reset cleanup, nested cleanup from Cancel, status and thrown stop failures, failing Cancel, exact native handle selection on a shared owner, registration/acquisition seal, repeated cleanup, worker rejection, tombstone routing, final GC cleanup, coordinator ordering and containment, and no-hook rejection. Native files and composed runtime compile for iOS arm64 with `-Wall -Wextra -Werror`. These are owned fixtures and syntax checks; no actual game cleanup or full EHR startup was executed by this package.

Actual normal signed iOS-on-Mac37 startup and diagnostic cleanup passed with
unchanged candidate binaries. All source states/native registrations, current
roots and association roots reached zero, with four bounded weak carrier
tombstones remaining. This run had no active associated engine handles to stop
(engineStopAttempts0); live-handle stop/error/deferred behavior is covered by the
owned fixtures, not claimed as an actual-game stop observation. The phone has
not yet received this build, and multiplayer/authentication remain unverified.
