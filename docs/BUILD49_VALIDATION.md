# Development build 49 validation

Validated on 2026-10-28 against the pinned Among Us iPhoneOS 2026.9.29 (3)
framework, Unity 2022.3.62f3, and EHR v8.0.3. This candidate changes the native
bridge and reuses the validated build-48 NativeAOT library: all 796 selected C#
inputs and the 224-resource catalog remain unchanged. It requires no runtime JIT.

## Why this candidate exists

Physical build 48 hosted an Online lobby and exposed EHR settings, but starting
the game still produced a black screen. Its numeric diagnostic showed two active
coroutines, immediate retirement of completed entries and no callback failures.
The earlier capacity exhaustion was absent from this reproduction.

The pinned parent game-start iterator directly constructs its native host
iterator, bypassing the patched host factory. Build 49 adds a narrow adapter at
that exact yield so the existing EHR host-start callbacks can run. See
[the adapter](IOS_GAME_START_ITERATOR.md) for owner, state, activation and
exception handling.

## Passed

- Strict iPhone ARM64 compilation and signed iOS-on-Mac full startup: 5,049
  options, 292 active permitted bindings, zero unavailable targets and no dynamic
  code flags. The six account/consent exclusions remain intact.
- Adapter preparation and activation in the actual signed runtime. Startup
  invoked neither the real parent `MoveNext` nor the real host factory.
- Actual-runtime owned adapter probe: 46 checks and six internal factory-seam
  calls, successful reference-field replacement, cancellation and failure
  cleanup, and identical native root counts before and after. It constructs
  owned iterator/carrier objects and permits matching null owners only through
  its internal test seam. No real game owner, original `MoveNext`, real host
  factory, Unity object, account or network operation is invoked, and no
  executable memory is written at runtime.
- Compiled synthetic adapter fixtures cover exact owner/state checks, one-call
  original and factory behavior, inactive/worker forwarding, reentrant mutation,
  inactive replacement rejection and exception/root ownership. The production
  path always requires matching non-null game owners.
- Real-runtime retention of 1,024 completed native carriers beside an active
  owned carrier, without filling the 256-entry registry. Late `MoveNext` calls
  stay false and registry/root counts return to baseline.
- Actual UnityAction ownership, touch scalar/identity, muted audio and complete
  resource-loader probes. Failure cleanup disables the adapter before source
  teardown and leaves no active source state, current-yield roots or association
  weak roots.
- The signed Mac runtime suite passed with all four candidate executables
  unchanged. It performed no Terms, account or game UI actions.

The protected upgrade tool requires the matching signed startup and owned
adapter proof for a candidate compiled with this adapter. Maps, game binaries,
profiles, device identifiers and raw runtime reports stay outside Git.

## Still unverified

Build 49 has not yet been verified in a physical lobby. The owned probes do not
establish real-owner game start, intro, a complete round, meetings/victory,
vanilla-peer joining or every role's behavior. Settings lag may have other causes.

Physical build 48 stopped repeating the Apple sheet after one attempt, but its
normal backend result was still EOS 7000. Backend authentication, online
discovery, account/progression safety and protection from bans remain unresolved.
The retry guard changes the failure flow only. Valuable accounts remain outside
testing; no authentication success or online permission is fabricated.
