> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Bounded native Action bridge

`EHRManagedActionAdapter.mm` and `ActionRuntime.cs` connect an actual IL2CPP
zero-argument `System.Action` to a rooted NativeAOT `System.Action` callback.
The separate versioned tables exchange opaque source/registration IDs and
gateway object roots. They exchange no managed object or metadata pointer.

Construction uses the real managed Object and Action constructors through the
caught gateway, a real boxed IntPtr created entirely inside native code, and
exact exported Delegate field metadata/setters. One 88-byte native callback
MethodInfo record is initialized only after the signed-framework full hash,
runtime UUID, and pinned version-method association gate succeeds. Both native
entry fields refer to the statically compiled callback. That record then
remains immutable and alive until process exit, independent of individual
delegate lifetime. The original finite constructor/Invoke execution proof is
documented separately in `NATIVE_ACTION_DELEGATE_PROOF.md`.

## Ownership and dispatch

Each registration creates a unique actual `System.Object` carrier. The returned
Action root belongs to its caller; the Action's real `m_target` strongly retains
the carrier. Temporary pins used during construction are released. Native
routing retains one public weak GC handle to the carrier and no strong root.
The NativeAOT dictionary owns the source callback under an opaque monotonically
allocated ID.

On each invocation, native code compares callback self with the current target
of each registered weak handle. It never accepts a cached object address. A
collected/reused address cannot retain the old source association. A moved
current weak target can be found by the bounded linear scan. The pinned image's
native Action call protocol still supplies the carrier through its native
`method_code`; the bridge makes no portable moving-GC delegate ABI claim.

Calls from workers are contained before GC/managed execution. Main-thread
calls validate runtime readiness and hidden metadata identity before dispatch.
Recursive drive is contained. Every NativeAOT callback catches source
exceptions; native code records its status and returns normally to IL2CPP.
Native construction also catches C++ exceptions before the host-table boundary.

`Close()` immediately tombstones the callback and forgets its dictionary entry
once. A native Action retained by an engine owner then safely no-ops. The weak
native tombstone remains until the carrier is collected. A bounded sweep runs
on the main queue every second while entries exist; weak-dead entries free
their weak handle and forget any still-active callback exactly once. Sweeps
check runtime readiness before GC access and do not free runtime handles after
teardown. Native and managed registries each cap at 256 entries.

`Il2CppSystem.Action` owns one normal facade root. It inherits normal facade
Dispose/finalization, including deferred worker releases. Disposing this proxy
releases only its root: an engine owner retaining the actual native Action
keeps invoking the source. Explicit main-thread `Close` alone tombstones the
source, including when its original proxy is already disposed. A wrapper
created from an existing owned token has no new source registration. Normal
weak collection reclaims registrations once native owners disappear. Callbacks that capture
their own native root can form a cross-runtime retention cycle, so those
owners must explicitly close their registration.

## Integration

Apply the new-file patch, then `production-action-wiring.patch`. The wiring
adds the native adapter/probe to the helper and runs `EHRManagedActionSelfTest`
after the live facade tables are bound. NativeAOT automatically includes the
new C# file through the existing project. Rebuild the NativeAOT library before
building the next signed candidate. The root proof key is
`managedSourceReuse.nativeAotActions`.

The native proof calls the real source callback through Action.Invoke, verifies
a contained source exception and its recorded status, disposes the source
proxy while a retained native Action still invokes the source, closes both
callbacks, invokes the retained native Action after close, then checks all
owned delegate tokens are stale and the source dictionary is empty. It reports
weak tombstones separately because conservative stack scanning can keep
carriers live during that synchronous call. Public native diagnostic exports
`EHRManagedActionRegistrationCount`, `EHRManagedActionActiveCount`, and
`EHRManagedActionSweep` permit a later main-queue XCTest to verify collection
after the constructing frames have returned. A collection request alone does
not guarantee that conservative roots have disappeared.

For native collection/parameter codecs, register the zero-argument wrapper as:

```csharp
Register<Il2CppSystem.Action>(new ReferenceCodec<Il2CppSystem.Action>(
    "mscorlib.dll", "System", "Action", static token => new(token)));
```

Generic Action/Func, UnityAction, event add/remove, and source signature
conversion are separate work. This implementation does not subscribe events
or claim those typed callback ABIs.

## Verification

The native files compile for iOS ARM64 with warnings treated as errors. A
compiled original C++ routing fixture passes 275 checks covering live weak
identity, address reuse, a changed target address, recursive drive, self-close,
contained errors, exactly-once forget/free, and capacity recovery.

```sh
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -I native/include \
  tests/action_registry_fixture.cpp -o /tmp/EHRActionRegistryFixture
/tmp/EHRActionRegistryFixture
```

The actual production `ActionRuntime.cs` also passes an osx-arm64 NativeAOT
fixture with its original simulated host: source effects 2, contained exception,
proxy disposal preserving a native owner's callback, closed late invocation
no-op, source dictionary empty, owned roots released,
worker rejection, two weak entries swept, and two source forget operations.
That host fixture does not simulate or claim game-runtime execution.

```sh
DOTNET_CLI_HOME=/path/to/ehr-ios-delegate-stage/DotnetHome \
NUGET_PACKAGES=/path/to/workspace/Tools/EHR-dotnet/nuget \
DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_GENERATE_ASPNET_CERTIFICATE=false \
/path/to/dotnet publish \
  tests/action_registry_fixture/ActionRegistryFixture.csproj \
  -c Release -r osx-arm64 --self-contained -o OwnAotFixturePublish
./OwnAotFixturePublish/ActionRegistryFixture
```

Private fixture results:

```text
/path/to/local-reports/action-registry-own-cpp-proof.local.json
/path/to/local-reports/action-registry-own-nativeaot-proof.local.json
```

The real Candidate17 native constructor/callback protocol proof passed. The
production NativeAOT-to-IL2CPP source round trip passed Candidate20 actual XCTest,
including proxy disposal preserving a retained native callback. Its asynchronous
weak-collection overlay observed2 weak tombstones→0 through the automatic sweep
after3 normal collection requests; active0 and final explicit sweep removed0.
Event subscription and typed delegate families remain separate work.
