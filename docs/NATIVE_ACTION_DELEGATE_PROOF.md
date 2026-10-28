> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Native System.Action construction proof

The finite prototype in `tests/runtime/ActionDelegatePrototype.inc` constructs
a real IL2CPP `System.Object` carrier and a real `System.Action`, then invokes
the Action twice through exported `il2cpp_runtime_invoke`. Both calls enter a
statically compiled C++ callback with the expected carrier and hidden method
metadata. It requires no injected class or runtime code generation.

This is execution evidence for the pinned Unity 2022 runtime and a zero-argument
Action. The callback metadata is one process-lived record. The prototype does
not return a delegate to callers or attach it to an event, so it makes no
general delegate/callback lifetime claim.

## Protocol and provenance

The design was checked against local Il2CppInterop commit
`dbda1cb353b0f4253345dc45136d170b9e50a5a0`, specifically
[DelegateSupport.cs](https://github.com/BepInEx/Il2CppInterop/blob/dbda1cb353b0f4253345dc45136d170b9e50a5a0/Il2CppInterop.Runtime/DelegateSupport.cs#L280)
and
[MethodInfo_29_1.cs](https://github.com/BepInEx/Il2CppInterop/blob/dbda1cb353b0f4253345dc45136d170b9e50a5a0/Il2CppInterop.Runtime/Runtime/VersionSpecific/MethodInfo/MethodInfo_29_1.cs).
The prototype is original code using the recorded layout facts.

Actual read-only framework disassembly independently established the constructor
and invocation behavior. The Action constructor reads `virtualMethodPointer`
from the supplied native metadata, so this prototype initializes both entry
fields to the same static callback. The Action invocation passes `method_code`
as callback self and `method` as its hidden method argument. Those observations
are specific to the validated image, rather than a portable delegate ABI.

Before initializing or consuming that private protocol, the test requires the
existing native-association gateway to validate the signed framework's full
SHA-256, runtime UUID, and exact version-method association. The owned native
record is 88 bytes, has zero parameters and slot 65535, and remains allocated
until process exit. No game metadata is overwritten.

Classes, constructor/Invoke signatures, field names, and field types are
checked through real exported IL2CPP metadata functions. Object and Action
constructors execute through caught `runtime_invoke`. The six Delegate fields
are written and read back through exported field APIs. Reference writes use
`field_set_value_object` with the direct object, preserving the runtime write
barrier; IntPtr writes use a native eight-byte buffer. The real reflection
MethodInfo for Action.Invoke is used for `method_info`.

Three own pinned GC handles retain the carrier, Action, and reflection object
through the entire proof. All three are freed once after the final invocation.
No native object or metadata pointer crosses the managed facade ABI.

## Reproduce

Generate a new overlay outside Git from the current own XCTest source:

```sh
ehr_source=/path/to/ehr-ios
ehr_reports=/path/to/local-reports

python3 "$ehr_source/tools/generate_action_delegate_proof.py" \
  --source-root "$ehr_source" \
  --output "$ehr_reports/action-delegate-new-overlay"

python3 "$ehr_source/tests/runtime/run_native_runtime_test.py" \
  --source-root "$ehr_source" \
  --candidate-app "$ehr_candidate_app" \
  --test-source "$ehr_reports/action-delegate-new-overlay/NativeRuntimeActionDelegate.local.mm" \
  --output-root /path/to/local-builds/RuntimeActionDelegateNew \
  --team-id YOURTEAMID \
  --sign-identity "$ehr_sign_identity"
```

The candidate and installed normal development identity are supplied through
task-specific variables. Use a candidate with the pinned-association gateway;
serialize normal runtime test launches. Generation refuses an existing output,
an output inside source/Git, or an incompatible/already-extended base test.

Own generator tests:

```sh
python3 -m unittest discover -s tests -p test_action_delegate_proof.py -v
```

## Actual execution

On 2026-10-28, normal signed Candidate17 XCTest passed with:

- Full signed-framework hash/UUID/version gate true.
- Exact native carrier, Action constructors, Invoke, and Delegate fields found.
- Both actual Action invocations entering the static callback.
- Exact carrier self and hidden metadata identity on the Unity main thread.
- All six public field writes read back correctly.
- Three allocated GC roots and three releases.
- Source candidate unchanged; no event registration or gameplay mutation.

Evidence remains outside Git:

```text
/path/to/local-reports/action-delegate17-overlay/generation-manifest.local.json
/path/to/local-reports/delegate-metadata.local.json
/path/to/local-reports/delegate-action-disassembly.local.txt
/path/to/local-builds/RuntimeActionDelegate17/runtime-test-summary.json
/path/to/local-builds/RuntimeActionDelegate17/Attachments/EHRNativeXCTestProof.json
```

The proof key is `nativeActionDelegatePrototype`. The executed overlay SHA-256
is `e1d113f52f88461f1b71590c092deea01e625894eb2452abfe2c7b2a1214d095`.
The reproducible generator produces the identical overlay from that base test.

## Required production work

A NativeAOT bridge can route this static native callback through an opaque
callback ID. Before use in source UI/events, it still needs an owned registry,
exact managed exception containment, delegate identity caching, cancellation,
event removal, and lifetime handling when native owners outlive managed
wrappers. Disposal must leave retained native delegates callable in a defined
state; freeing metadata while a delegate survives is invalid. Main-thread
requirements must be explicit. Generic Action/Func and UnityAction signatures
require separate metadata, argument/return ABI, and actual execution tests.
