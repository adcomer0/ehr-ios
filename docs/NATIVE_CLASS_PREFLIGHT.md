> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Read-only IL2CPP class preflight

This package contains original source for an isolated signed-XCTest overlay.
It requests no custom type allocation, writes no guessed runtime field, calls
no private function, and performs no class registration or executable patch.
No game bytes are included in the source package. Canonical is untouched.

Generate against the latest test source, including other overlays if desired:

```
python3 make_test_overlay.py --canonical /path/to/EHR-iOS \
  --test-source /path/to/combined/NativeRuntimeTests.mm --output /fresh/stage
```

Omit `--test-source` for current canonical tests. The tool inlines its OWN
source, calls `EHRClassLayoutPreflightWithLookup(bridgeExport)` after scheduling,
asserts success and adds `classLayoutPreflight` to the existing JSON evidence.
It needs no new app export, app source, native hook, or game rebuild. All app
gateway functions are obtained through the existing lookup callback; symbol
checks confirm no new app-link dependency. Use the existing app-hosted signing
and launch workflow. The generator never launches or signs anything.

Before guessed class memory is read, the probe exact-resolves the version
getter and requires existing `validate_native_method(...,30734292)` success.
That adapter verifies the allowlisted original source SHA256, loaded UUID,
complete signed candidate-file SHA256 and executable association. Failure
returns without a private class read.

Seven real classes are examined: System.Object, String, Int32, ArrayList,
ArrayListEnumeratorSimple, UnityEngine.Object and MonoBehaviour. Normal public
exports supply image/name/namespace/type/parent/declaring/element pointers,
instance size, flags/token/rank, type attributes/kind/byref/value bits,
initialization/reference bits and six bounded public enumerations. Public
parent chains and assignability relations are bounded to 32. Those public
queries may populate runtime-owned metadata caches; no private initializer or
guessed field write is used.

The 312-byte class header is a hypothesis buffer. Counts and pointer fields must
match public facts/cursors before any guessed array is read. Method/nested/
interface pointer arrays compare first/last values; fields/properties/events
compare public contiguous entry addresses against candidate strides 32/40/56.
Empty pointer/stride fields remain explicitly unwitnessed. The hierarchy array
must match the complete public root-to-class chain. All guessed reads use
bounded `vm_read_overwrite` on the process's own task; unreadable ranges fail.

Two owned value objects (a string and boxed Int32) provide vtable witnesses.
Public Object.ToString lookup and object_get_virtual_method identify the exact
native overrides. Public method facts validate the candidate MethodInfo fields
before reading slot 80/virtual pointer 8. A fresh class sample must pass all
prerequisites and initialized/vtable bits before reading one candidate vtable
entry at 312+slot*16. Both entry method identity and code pointer must match.
Only these slots are corroborated; the complete vtable/count and allocation
sizes 312/88/16 are not falsely declared proved by this runtime check. Local
UInt32 IL2CPP handles root the owned values and release once, including unwind.
No object or metadata pointer crosses NativeAOT.

`inspect_class_internal_targets.py` separately reads only the original clear
framework/metadata with exact SHA256/UUID allowlists. It follows public ARM64
wrapper branch/dataflow paths to three OFFLINE candidates:

- FromIl2CppType: 0x19c1970, two arguments (Type*, bool).
- FromName implementation: 0x19b7bf0, image/namespace/name.
- GetTypeInfoFromTypeDefinitionIndex: 0x19ad6a0, signed Int32 index.

Two independent paths converge on the index body. Its native allocation path
uses a 312-byte base plus the type-definition vtable count times 16. This is
offline corroboration, not a claim every class offset or private ABI is live
proved. The manifest includes seven exact metadata definition indices for a
later bounded private-ABI validation. It never invokes those targets.

Reproduce private offline evidence:

```
python3 inspect_class_internal_targets.py --framework /path/to/clear/UnityFramework \
  --metadata /path/to/global-metadata.dat --private-output-dir /outside/git/report
```

The output directory is rejected inside Git. JSON emits no instruction words
or body bytes. Bounded LLDB disassembly is retained only in the private report
directory, with no process launch/attach. Current evidence is under
`Artifacts/Reports/2026-10-28-ehr-native/class-preflight/reproducible`.

Local verification: 19 OWN guarded-layout checks and 5 OWN ARM64 decoder tests
pass. Both native source and the entire generated XCTest translation unit
compile for iOS 17 arm64 with all warnings treated as errors. No game image is
executed by the checker:

```
python3 check_preflight.py --canonical /path/to/EHR-iOS --output /fresh/check
```

The actual class-layout runtime test remains pending the parent run. Nothing in
this package establishes a working ClassInjector, custom MonoBehaviour lifecycle,
full IL2CPP layout compatibility or full EHR feature coverage.


Actual unchanged Candidate20 XCTest passed all seven class facts and both String/
boxedInt32 known virtual slot witnesses. Header/cursor/endpoint/hierarchy facts
are verified; complete class fields, complete vtables and allocation sizes are
explicitly unverified. No private class write, type registration or private
internal function invocation occurred. Evidence is private RuntimeClassPreflight20.
Canonical overlay generator: tools/generate_class_preflight_overlay.py; read-only
internal mapper: tools/inspect_class_internal_targets.py.
