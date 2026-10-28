> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Typed native patch entry thunks

The planner consumes exact method/type facts, pinned source metadata, successful
public layout observations and actual runtime type spellings. It emits no claim
of installed or playable availability. A separate generator emits native C++
structs, size/alignment/offset assertions, exact typed entry thunks and strict
patcher contracts. Every generated file goes into a new outside-Git directory.

`generate_native_typed_thunks.py thunks` requires `--plans`, `--catalog`, one or
more `--runtime-type-proof` files and `--output`. The runtime proof UUID must
match the planner's framework UUID. The catalog must contain exactly the same
selector identities and native RVAs. It emits:

- `EHRNativeTypedThunks.generated.inc` (compile into the native helper once).
- `EHRNativeThunkTypes.generated.h` (native typed structs and assertions).
- `EHRNativeThunkSites.generated.h` (initially every install pointer is null).
- `native-thunk-contracts.local.json` (strict patcher contracts).

Each hook symbol is `_ehr_full_hook_<selectorId>` in Mach-O, with contract key
`ehr.full.<selectorId>`. Existing hooks sharing the entry must be replaced,
never installed as a second independent interceptor at the same address.

After the strict patcher produces its unsigned output, run generator mode
`sites` with `--catalog`, `--patch-manifest`, `--patched-framework` and a new
`--output` directory. It checks the exact unsigned output hash and UUID, entry
branch, stub and strict reconstructed relocation. Its site header contains
numeric addresses and SHA256 digests, with no copied original instruction
bytes. Use this header instead of the initial null header when compiling the
helper. Signing the framework changes its signature, not those RX ranges.

Compile `EHRNativePatchThunks.mm` with normal native exceptions enabled, as for
the existing gateway. Include the generated `.inc` in exactly one native unit.
Call `EHRNativeGeneratedRegisterCompiled()` once on the main thread, then bind
the native table from `EHRNativePatchMakeTargetsTable` using the existing
`ehr_source_bind_patch_targets_v1`. Registration does not activate anything.

The source side first prepares passive definitions so SignatureV1 is available.
TargetsV1.Validate checks exact compiled/installed evidence, public method token,
owner, parameter/return classes, ref/out attributes, value sizes, alignments,
reference/blittability flags and observed field offsets. Method association also
passes the existing full signed-framework hash/UUID gate. Source bindings can
then be installed for exactly those accepted IDs. TargetsV1.Activate revalidates
the whole requested set and publishes it as one immutable transaction. Any
failure clears all active handlers. At most32 activation generations are retained
per process; further activation returns LIMIT. Deactivate is atomic.

Before source activation, worker calls, bypass-permit calls and pre-entry
failures execute the signed original trampoline with their unchanged hidden
MethodInfo argument. A hook can use this original path before source bootstrap,
because installed-site validation does not require IL2CPP metadata readiness.
Missing/invalid installed evidence aborts an intercepted call rather than
jumping to a guessed trampoline. No runtime executable memory is written.

After DispatchV2 marks dispatcher_entered, the handler never retries original.
Every returned native root is released or transferred once. Supported raw value
ref outputs are read into bounded native buffers, class/size checked, and copied
back before native exception rethrow. All ref conversions validate before any
copyback commits. CLR-only failures become proper native exceptions after the
NativeAOT call has returned. Per-frame immutable metadata survives reentrant
activation. Aliased ref outputs are rejected before source entry and follow the
original path. General managed-reference ref/out remains unsupported.

Reference-bearing value input stays entirely in native memory. A compiler-typed
incoming value is copied only by public `il2cpp_value_box` into an independently
rooted real IL2CPP object. The CLR receives its opaque root token. It never sees
those reference payload bytes. Such value returns/ref outputs are unsupported.
The native-only `EHRNativePatchBoxBorrowedValue` accepts only bounded, aligned,
actual native value views whose exact public class/layout matches its descriptor.

For the current Activity descriptor, generated export
`ehr_native_patch_value_box_selftest()` constructs only isolated boxed values
and an owned String containing a NUL, copies with public value_box, releases the
input roots, performs one normal collection if exports exist, and checks the
String survives through the copied value. It also checks raw copy_value rejects
the reference-bearing payload. This test never calls UpdateActivity or another
target body. It requires a parent-run actual XCTest before that path is claimed
operational. Compilation alone does not prove native reference ownership.

Own ARM64 fixtures exercise emitted HFA4, indirect144 with pointer fields, tiny
value return, out16, Boolean ref1, hidden-context preservation, skip-original,
pre-entry fallback and accepted failure without fallback. The native dispatcher
in that fixture is an explicit mock: it proves compiler ABI/control flow, not
actual IL2CPP binding. Separate original-source Mach-O fixtures test installed
site generation and branch/stub/trampoline tamper rejection. Actual handler
activation and target execution remain parent-run candidate gates.
