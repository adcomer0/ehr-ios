> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Stable source delegate identity

Equal CLR delegates within the same native family reuse one source registration and the current native weak carrier. Each conversion constructs an independent real native delegate object/root using that carrier and the same process-lived callback MethodInfo. No strong cache of native delegate proxies is introduced. Zero System.Action and UnityAction use separate family keys; typed callbacks use CLR delegate runtime type and normal delegate equality. Native typed reuse also requires exact argument class and ABI equality.

Both Dispose and finalization remain proxy-root-only. Explicit Close on any source registration alias tombstones the shared source and makes all native aliases no-op. Weak collection removes both callback and identity mappings once. Create may sweep a dead carrier; a successful reconstruction reinstates the equal source mapping after that sweep, without retaining a dead native carrier. This does not break callback-captured native-owner cycles.

The isolated actual-runtime test converts fresh equal method groups, then uses real Delegate.Remove for System.Action and Action<Int32>, and real UnityEvent.RemoveListener for UnityAction on an independent ButtonClickedEvent. It verifies a distinct source target is unaffected, alias proxy Dispose does not cancel its source, explicit alias Close does cancel its source, and all temporary roots/source entries are released. It does not subscribe to scene events. The parent must run this test against the actual framework; build-only and simulated-host checks are separate evidence.

Own C++ source tests cover lookup/reuse selection, explicit tombstone, reconstruction with a distinct registration, dead weak sweep and exactly-once forget/free. The original NativeAOT fixture exercises the production typed C# equality cache against a simulated host whose create reuses source identity; it makes no IL2CPP execution claim.

Owner lifecycle cleanup must unsubscribe and Close on genuine component destruction, scene transition or plugin unload. Proxy Dispose is deliberately not an owner lifetime signal. An equal callback may have multiple engine subscriptions; a shared explicit Close cancels all aliases, so Close belongs to the owning callback scope and must run after that scope unsubscribes.
