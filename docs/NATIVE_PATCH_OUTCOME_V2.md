> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Per-dispatch original outcome

`ehr_source_patch_dispatch_v2` is a separate export with an explicit 32-byte plain output proof. V1 dispatch and every existing function-table layout remain unchanged. Proof fields are eight UInt32 values: abi_version=2, byte_size=32, target_found, dispatcher_entered, original_attempted, runtime_entered, permit_consumed and hook_consumptions.

All root/output/input buffers and the proof are checked for bounded spans and overlap before any output write. The proof requires four-byte alignment; root arrays/slots retain their existing eight-byte alignment. Invalid proof spans/overlap leave all caller memory untouched. Once validated, outputs initialize deterministically, including target-not-found calls.

TargetFound means a configured target was found. DispatcherEntered is set after target/count/receiver-kind acceptance and before argument marshalling or source work. OriginalAttempted is set on entry to the original delegate, before original marshalling/capability setup. Native RuntimeEntered/PermitConsumed/HookConsumptions are copied immediately after the host Invoke returns, before any ref conversion, exception construction, result conversion or finally cleanup can throw. Consequently final dispatch failure status cannot erase evidence that original already executed.

A native handler MUST NOT retry original after DispatcherEntered becomes1. A surviving native exception is raised only after NativeAOT returns, after observable ref outputs copy back. A CLR-only failure has no borrowed native exception root; the handler must construct and raise a proper native exception after returning from NativeAOT, rather than silently returning a default or retrying original. This extension records the outcome; it does not claim the full typed native handler/error policy is already implemented.

The existing isolated arithmetic native probe now exercises V2 in addition to V1: version original runs exactly once; a bool skipping prefix runs it zero times; own prefix and postfix failures preserve distinct before/after original flags; proof overlap writes nothing; four-byte proof alignment is accepted. No lobby or game object is changed. Own failure fixture setup reconfigures only the existing arithmetic definitions and restores the normal fixture before returning.

The original NativeAOT simulated-host fixture links the production NativePatchRuntime, StaticPatchRuntime and NativePatchFixture source. It tests the same outcome distinctions plus an injected original-scope cleanup failure that occurs after native Invoke proof capture, and asserts every own root was released. It makes no actual IL2CPP execution claim. Build/run:

```sh
DOTNET_GENERATE_ASPNET_CERTIFICATE=false dotnet publish tests/patch_outcome_fixture/PatchOutcomeFixture.csproj -c Release -r osx-arm64 --self-contained -o /tmp/ehr-patch-outcome-fixture
/tmp/ehr-patch-outcome-fixture/PatchOutcomeFixture
```

Actual candidate XCTest is a separate parent-serialized gate. Neither this no-ref arithmetic payload nor the own fixture claims actual native byref/exception behavior for the full298 source catalog.
