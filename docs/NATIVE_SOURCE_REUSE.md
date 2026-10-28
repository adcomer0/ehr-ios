> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Native EHR source reuse

The requested deliverable remains the complete EHR host client running locally
on an iPhone. A compiled source inventory, generated wrapper, or successful
startup test does not complete a role, a game mode, or vanilla multiplayer.

## Verified foundation, 2026-10-28

The read-only upstream checkout is EHR v8.0.3, commit
`ce23f0d050f617a59507e5bb0fbfff751d4b5134`. Its complete Mono and IL2CPP source
configurations compile in isolated scratch builds. Neither desktop DLL can run
unchanged in this iOS app. The PC loader, Harmony runtime detours, dynamic code
generation, and Il2CppInterop construction paths require replacements.

The current approach compiles source before signing using Microsoft .NET
NativeAOT. `managed/SourceReuse` links two unchanged upstream files:

- `Modules/OptionItem/ValueRule.cs`: numeric option index/value rules.
- `Patches/ServerVersionPatch.cs`: the actual `ServerUpdatePatch.Postfix`.

Original compile adapters supply the current observed network mode, fixed
gateway calls and a no-op diagnostic logger. They do not implement full EHR
bootstrap, role logic, Harmony, game state, or settings persistence. The unused
`Constants.IsVersionModded` compile declaration throws if called without a real
binding. Merely compiling `IsVersionModdedPatch` does not install that patch.

Candidate build 16 was built from these canonical own sources, with a separate
source-build manifest. Its managed library is an ordinary signed ARM64 iOS
framework dependency. The native version hook executes the original game method
first, then calls the unchanged source postfix. The third native hook executes the
unchanged IsVersionModded Prefix and honors its skip-original result. No runtime executable pages,
JIT, downloaded code, or game decryption are involved.

Normal app-hosted XCTest on this Apple Silicon Mac passed against the actual
signed game framework. Proof is in the private artifact directory
`RuntimeSourceReuse16/Attachments/EHRNativeXCTestProof.json`:

- NativeAOT calls the gateway, invokes the actual getter, crosses the native
  interceptor and source postfix, and returns `50663650`.
- The source online-mode case returns `50663675`; local mode preserves the value.
- Real IsVersionModded returns true through the unchanged Prefix, original-call count0.
- Exact numeric source rules return integer8/float4 in the iOS process.
- Dynamic code support/compilation flags are both zero; one owned result is
  released; the pinned framework UUID is observed.
- Unicode strings, embedded NUL, surrogate pairs, exact reference overloads,
  boxed Vector2 fields and static struct arguments work.
- An isolated exception's reference field can be changed to a real string and
  then null, using the runtime write barrier.
- Scalar `ref/out` copy-in/copy-out works for Int32.TryParse, including Boolean
  return width, successful/unsuccessful parses and invalid-descriptor rejection.
- Live integer/reference arrays support creation, length, get/set, null,
  bounds rejection and contained element-type exceptions.
- Constructed native List<int> supports real IList/ICollection mutations and caught
  invalid arity/constructor exceptions; managed list facades preserve enumeration version checks.
- Worker/finalizer disposal automatically queues bounded main-thread root release;
  identity hashes are paired with actual reference equality.
- The read-only generated API audit resolves1751/1752 declarations. Desktop
  TextBoxTMP.caretPos remains an explicit mobile input adaptation.
- Managed exceptions are returned as owned tokens; stale tokens, double release,
  wrong signatures and open generic invocation are rejected.

These tests use local runtime objects and the version getter. They do not accept
agreements, authenticate, enter a lobby, assign roles, kill/report, or establish
vanilla-client compatibility. The candidate app remains unchanged by the tests.

## Runtime gateway contract

`native/EHRRuntimeGateway.h` defines a main-thread C ABI. Metadata IDs identify
runtime classes/methods/fields; object tokens each own a strong GC root. Tokens
are never native object pointers. Every nonzero returned object token requires
exactly one release. Metadata resolution matches image, namespace, class, exact
parameter/return type names and static/instance shape. Calls validate receiver
assignability and use real virtual dispatch.

The implementation uses exported, version-specific Unity 2022.3 IL2CPP APIs.
They are internal runtime interfaces, not a stable Unity SDK contract. The game
input and native hook image remain pinned by metadata hash, framework hash and
UUID. GC-handle function declarations use this runtime's UInt32 ABI.

Raw values require exact runtime class identity, size/alignment and reference-free
blittability, with explicit managed-width Boolean/Char support. Invocation copies
caller bytes into aligned storage. Reference field writes use the runtime's
object helper; passing the address of a native reference slot to this build's
setter would corrupt its heap. Ref/out uses separate explicit writable output
descriptors and never casts away the immutable input pointer.

`EHRRuntimeCollections` uses actual System.Array methods through this gateway;
it does not return detached collection snapshots. Arrays are currently bounded
to 65,536 elements. A failed operation can still return a managed exception token
that the caller must release.

Closed generic methods are inflated through actual MethodInfo reflection and
converted back through the runtime export; only available AOT bodies can execute.
Current unsupported shapes are explicit: open generic invocation, byref managed
references and raw
structs containing managed references. Static fields on classes with a managed
class initializer require successful caught initialize_class first. Boxed value
arguments stay pinned and rooted, including structs containing managed references;
their payloads never cross the ABI as raw bytes. Boxed value receivers are pinned
and unboxed only for value-declared resolved methods; inherited reference methods
keep boxed this. Both cases pass actual build12 runtime tests.
The immutable invoke API always rejects byref parameters; its separate mutable
entrypoint accepts supported scalar/blittable value refs.

`EHRManagedBridgeV1.h` is a fixed function table for the first AOT source slice.
Separate array/ref-out, reflection, lifetime and exact-type-name extension tables leave its
152-byte layout unchanged. New C exports do not silently change that layout. Full facade work must
bind additional capabilities explicitly, preserve game collection mutations,
schedule game access on the main thread and release roots on that thread.

## Rebuild

Use `tools/build_managed_rules.py --help`. It requires an explicitly selected
local .NET SDK, the pinned clean upstream source and a new non-Git output path.
Its child-process cache/CLI environment is isolated. The generated manifest pins
the source hashes, SDK and resulting iOS image. No desktop game assembly is an
input to this native library.

Pass the resulting dylib with `tools/build_game_probe.py --managed-dylib ...`.
That builder makes a new private app copy, changes only the copied library's
install name, bundles/signs the framework and verifies the exact company profile
and destination coverage. It rejects a selected certificate fingerprint absent
from that profile before building. All game-containing outputs remain local.

The actual runtime runner is documented in `tests/runtime/README.md`. Its result
bundle is the evidence; building a dylib alone does not execute iOS code.

## Full-source integration still required

The source extractors inventory exact feature/patch surfaces and distinguish
discovery from behavioral coverage. `SOURCE_KERNEL_CONTRACTS.json` records the
shared pipelines needed for complete EHR behavior. Generated AOT factories must
preserve original type-selection filters, constructors and settings-sensitive
enumeration order. Source-compatible live game/Unity/Il2CppSystem/Hazel facades
and static patch dispatch must replace the desktop runtime dependencies. The
canonical source_port tools now generate and compile the complete IL2CPP source
with explicit factories/bootstrap/direct callback bridges against its managed
reference profile. Nineteen arithmetic dispatcher checks pass. Native binding and
full-source NativeAOT integration remain separate required work.

Assignment, recipient role/options projection, kill validation, meetings/votes,
custom endings, abilities, touch settings/presets/localization and every game
mode still require integration and actual-game acceptance evidence. Current
complete EHR role verification remains zero; manual Bait is partial. Physical
iPhone installation and multiplayer playtests have not occurred.


## Build15 additions and current limits

Actual-game build15 also verifies settings on an independent native options object,
true value-copy behavior, owning object casts, preserved native exceptions, nested
class traversal and metadata-only vector class identity. Its native IEnumerator
checks use actual ArrayList enumerators, without managed-source adaptation.

A one-shot native permit routes the version getter through caught runtime_invoke
while consuming exactly one matching native hook bypass. Ordinary calls still run
the source postfix. The managed OriginalV1 bridge passes actual-game build16, with no pooled roots
or capabilities remaining after return; the core
152-byte table remains unchanged.

The runtime has no RuntimeMethodHandle.GetFunctionPointer method. A private
version-pinned native adapter instead verifies the source allowlist, loaded UUID,
final signed candidate-file SHA256, metadata owner/name/token and executable
range before comparing its proven code pointer field. Build15 verifies this for
GetBroadcastVersion and rejects mismatched targets. It does not establish a
portable IL2CPP layout or callback ABI for every mapped source target.

The native mapper resolves296 ordinary exact candidates and leaves two coroutine
MoveNext selectors unbound. Its296 successful relocation probes use a declared
layout; final emitted hook subsets must be revalidated. No full patch batch is
installed. The replacement-facade full source compile currently exposes962
method-body diagnostics; live source compatibility and loader/component/delegate
integration remain active work.


Build16 adds real native dictionaries and explicit managed predicate algorithms
over live native lists. Native key views/enumeration, Unicode keys, typed access,
removal/clear and predicate mutation guards pass in the actual game. This is not
IL2CPP delegate creation. A separate40-byte OriginalV1 function table passes the
actual NativeAOT-to-native original call; an original owned fixture additionally
proves native exception identity survives the managed call and scope cleanup.


Build17's separate40-byte iterator host table and32-byte callback table bridge
registered native ArrayList enumerator identities to NativeAOT source iterators.
The main-thread adapter owns carrier/current roots, preserves ordinary native
behavior for unregistered objects, catches managed callback errors before native
return and raises native exceptions only after the managed callback returned.
Actual-game manual invocation passes. General nesting, Unity scheduling and
engine-owner cancellation remain separate required work.


Build18 includes a separate32-byte method-reflection extension and exact closed
Type.GetMethod validation (owner, return class and staticness), preserving real
native DestroyableSingleton<T> inheritance. The real InstanceExists call returns
false in the pre-lobby test; Instance is skipped and is not execution evidence.
Source facade generation, input-pin schema, metadata-only readers and Roslyn
attribute-name adaptation are reproducible from tools/facades, with21 original
synthetic regressions. Inputs and diagnostics containing game metadata stay
outside Git.


Build20 verifies exact public constructors through ConstructorInfo, actual
closed generic Unity component/clone calls, native Action source callbacks and
Unity-driven source coroutines with real wait objects and cancellation. Proxy
root disposal preserves a retained native Action; explicit Close tombstones its
source, and later normal GC/automatic sweep reclaims weak routing. Role gameplay
coverage remains zero and the complete EHR source is still not loaded. Latest
external replacement-facade source diagnostics are70, with typed delegates,
collections, engine-only helpers and production bootstrap/components outstanding.

Build21 verifies actual ButtonClickedEvent AddListener/RemoveListener and native
params boxing. Its engine HTML-color parser check failed: the public internal
call resolver is present but that internal call is absent. A separate read-only
probe verified the native Color32 class and its four Byte fields; no guessed
entrypoint was invoked.

Build22 passes the complete actual-game startup suite. An independent documented
HTML-color compatibility implementation now passes all22 documented named colors,
four hexadecimal formats, malformed inputs and null through genuine native Color
construction and ToHtmlStringRGBA round trips. Evidence distinguishes this
implementation from the unavailable engine parser. The automatic weak sweep
also reclaims all four delegate tombstones after normal runtime collections.

Original routes can now register additional ordinary methods after exact pinned
native association, rejecting changed/aliased identities. Actual build22 proves
the second IsVersionModded route, wrong-RVA rejection, idempotent registration,
alias rejection and exactly one bypass per call through both invocation entry
points. The explicit-ref entry's scalar copyback path remains separately tested
by owned fixtures; this real-game check has no ref parameters. Existing function
tables retain their sizes. Full-source replacement compilation is still
incomplete; full EHR role gameplay and physical-device installation remain pending.
