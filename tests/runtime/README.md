# Actual native game XCTest

This package contains original test/runner/project source only. It contains no
game bytes, signing material or device IDs. The current test requires a candidate
built with the canonical NativeSourceReuse.framework and the native hooks enabled by that candidate.
Keep the runner, test, project and canonical native headers together.

Normal app-hosted XCTest launches a NEW, company-signed iOS game copy on an Apple
Silicon Mac. It observes the real IL2CPP domain and native hook counters. It tests
exact method/field resolution, getter calls, reference/scalar/boxed-struct inputs,
scalar ref/out, live arrays, caught static initialization, generic List<int>
construction and mutation, managed exceptions and GC ownership.

The NativeAOT source slice calls the real game through fixed C ABI tables and
executes unchanged upstream EHR version/option rules. A real IsVersionModded
Prefix returns true and skips the original. Generated facade tests exercise live
arrays/lists, native reference identity/hash, idempotent disposal, worker enqueue
and .NET finalizer reclamation. The API audit resolves declarations only;
unresolved declarations are reported individually and do not become role claims.

No UI action, agreement acceptance, account login, lobby, role assignment, kill
or report is performed. The full binding snapshot and proof go to stdout and
keep-always XCTest JSON attachments. ARC retains dictionaries across async waits.
The test does not read another application's sandbox or OS pairing credentials.

```sh
python3 run_native_runtime_test.py \
  --source-root /path/to/own/EHR-iOS \
  --candidate-app /path/to/personal/EHRNativeGame.app \
  --output-root /new/non-git/artifact/directory \
  --team-id "$TEAM_ID" \
  --bundle-id "$APP_BUNDLE_ID" \
  --sign-identity 'Profile-covered Apple Development identity'
```

Supply your own explicit development team and separate app identifier. Both the source candidate and new test
host are verified against the exact Mac provisioning UDID, team/certificate,
profile expiry, app identifier and nested signatures. Add
`--allow-provisioning-updates` only when Xcode needs to update your development assets.
`--prepare-only` generates own project source without copying/launching a game.

The runner first builds an original placeholder app/test target using the real
bundle contract, preserves it, and substitutes a NEW candidate copy as test host.
It embeds the signed test bundle and normally re-signs only that copy. All four
candidate executable images, including the NativeAOT framework, must hash
identically before/after. ENABLE_DEBUG_DYLIB=NO prevents a placeholder debug-dylib
dependency from remaining in the test bundle.

Keep the iOS project AND scheme arguments with destination
`platform=macOS,arch=arm64`. Bare xctestrun can expose unrelated Mac variants and
select ordinary macOS, producing kLSExecutableIncorrectFormat. The project/scheme
constrains Designed for iPad/iPhone. The preserved temporary wrapper is evidence,
not a standalone installation. Direct execution can still fail normal launch
policy. Normal standalone GUI launch and physical iPhone installation remain
separate work.

Current passing evidence is private RuntimeSourceReuse20/RuntimeResults.xcresult
and Attachments/EHRNativeXCTestProof.json. It records gateway/facade/lifetime,
boxed value receiver, copy isolation, retained exceptions, validated casts, nested
classes, exact runtime names, vector classes, real MethodInfo/generic inflation,
native iterator baseline live dictionaries, explicit managed source predicates and both native/NativeAOT
one-shot original route checks passing. Dynamic-code
flags0, getter50663650, online source case50663675, numeric cases8/4, and1776/1777
metadata declarations resolve. Missing binding1148 is desktop TextBoxTMP.caretPos.
The public RuntimeMethodHandle.GetFunctionPointer declaration is absent; the
separate exact-version native method validator passes, checking loaded UUID and
final signed framework hash before private proven field offsets. It establishes
association for the tested method, not a stable public ABI or all hook bindings.
The candidate remains unchanged. Full EHR roles, source iterator adaptation,
physical-phone installation and multiplayer are not established.


Build17 additionally passes the registered native IEnumerator-to-NativeAOT source
adapter through manual runtime_invoke. Three typed pre-sign hooks preserve
unregistered enumerators. The proof records null and native-string yields,
identity-preserving Current, contained Reset/Current exceptions, source effects3,
dispose1, and zero registrations/current roots after close. Unity scheduling and
source cancellation bindings still require their separate asynchronous test.

All296 ordinary source targets are separately verified against exact actual
runtime signatures, declaring types and native RVAs in RuntimeBindingAudit16.
This audit invokes no target and leaves both unresolved MoveNext selectors
excluded. See docs/RUNTIME_BINDING_AUDIT.md for reproducible generation and run.


Build18 adds the separate32-byte method-reflection table and real inherited
DestroyableSingleton<T> facade shape. Exact closed getter metadata and native
InstanceExists pass. The selected singleton is absent before the lobby, so its
Instance getter is explicitly skipped and remains untested. Generator sources
and21 synthetic regressions are under tools/facades; their
compilation does not establish full source gameplay compatibility.


Build20 additionally passes exact constructors and actual generic Unity methods
on independent GameObject/Transform objects, then normal destruction. Unity
StartCoroutine drives the source iterator to completion with a real realtime
wait; StopCoroutine cancels a second wait. Its existing active owner is a
UniversalDeeplinkingRuntimeScript found by a bounded public MonoBehaviour scan,
without creating scripts, invoking singleton getters or entering UI/lobbies.
The original AmongUsClient-only build19 scheduling test correctly reported that
owner absent and was not a passing whole-suite candidate.

Build20's production native Action roundtrip verifies source effects2, retained
native invocation after .NET proxy disposal, contained source exception, explicit
Close/no-op, and release of all owned delegate roots. A separate asynchronous
ActionWeakCollection overlay observes automatic weak cleanup2→0 after normal
IL2CPP collections. It reports active0 and final explicit sweep removed0. Use
`tools/generate_action_weak_collection_overlay.py` for that additional gate.
