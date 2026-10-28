> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Typed native Action bridge

This optional extension creates real closed IL2CPP `System.Action<T>` delegates for `Int32`, `Byte`, `Single`, and reference arguments. It uses statically compiled callbacks, the existing native object carrier, and caught public reflection construction. It does not inject a class or emit runtime machine code.

## Exact ABI and image gate

Before using the pinned 88-byte MethodInfo protocol, the adapter validates the known ordinary version method through the existing full candidate-framework SHA256/UUID association guard. Public metadata must then identify the exact closed `Action<T>` owner, `.ctor(Object,IntPtr)`, and `Invoke(T)->Void`; the pinned association helper checks both concrete entry addresses against independently classified generic registrations. Unsupported or missing AOT instantiations fail. No fallback creates a guessed body.

The independent clear-framework disassembly established four callback shapes: Int32/Byte use `(self:x0,value:w1,method:x2)`; Single uses `(self:x0,value:s0,method:x1)`; reference uses `(self:x0,value:x1,method:x2)`. Callback metadata identity is checked on every entry. Each shape has one process-lived own MethodInfo record; it is shared across instances of that exact shape. These are version-specific claims, not a portable IL2CPP layout contract.

No managed object pointers cross the C# ABI. Class tokens, owned/borrowed gateway-root tokens, source IDs and registration IDs are opaque. The native-only RootBorrowed helper accepts a real object obtained from a validated native callback frame and creates one independent strong root; its caller releases that root after callback return. C# retains a reference argument before a facade may escape.

## Lifetime and thread rules

A strong C# dictionary owns each source delegate. The actual native Action owns its native Object carrier; the registry owns only a weak handle to that carrier. Every dispatch compares the current weak target, so object movement or address reuse cannot select a cached stale address. Main-queue sweeps remove dead weak entries and forget the source once. Registries are bounded to 256 entries.

Disposing a facade releases only its root. A retained engine/native Action remains callable. Explicit `Close` tombstones its source immediately; later native invocation safely does nothing. Close and all invocation/creation/registry access require the Unity main thread. Worker disposal keeps the existing deferred-root release behavior. No .NET exception may unwind into an IL2CPP frame.

`Delegate.Combine/Remove` are actual native methods. Removal is proven only for the exact retained native delegate instance. Fresh equal CLR method-group conversions currently create distinct native target carriers and therefore do not provide unsubscribe identity parity. Cross-runtime cycles (callback captures an owner facade whose native object owns that callback) require explicit owner lifecycle Close/unsubscribe; a weak carrier alone cannot break them.

## Scope and checks

The actual-runtime payload exercises negative Int32, Byte231, exact Single bits, independent native Object identity, null OptionBehaviour/GameObject references, source exception containment, retained native invocation after proxy Dispose, explicit Close no-op, native Combine/Remove-existing and all owned root cleanup. It creates no GameObject/component and performs no lobby mutation. Actual runtime construction/execution is a separate gate; successful compilation and the own host fixture are not that proof.

The original NativeAOT fixture links the production typed C# callback implementation against an original simulated host. It checks scalar values, escaping reference root ownership, worker rejection, exception containment, proxy disposal, Close and exactly-once reclamation. Run:

```sh
DOTNET_GENERATE_ASPNET_CERTIFICATE=false dotnet publish tests/typed_action_fixture/TypedActionFixture.csproj -c Release -r osx-arm64 --self-contained -o /tmp/ehr-typed-action-fixture
/tmp/ehr-typed-action-fixture/TypedActionFixture
```

Tables are an independent 40-byte host and 48-byte callbacks extension; existing core and zero-argument Action/UnityAction tables remain unchanged. Proof is 80 bytes. Generic closed codecs must be registered explicitly for compiled source argument types. The generator must remove its old host-only `Il2CppSystem.Action<T>` delegate declaration; list callbacks use native `.Invoke`. A separate `System.Action<T>` list overload supports explicit host callbacks.

Not implemented by this extension: Action3 cosmetics callbacks, Func object-to-bool callbacks, Scene/LoadSceneMode UnityAction2, stable fresh-method-group identity, complete callback owner lifecycle wiring, or arbitrary typed/value-struct ABIs.
