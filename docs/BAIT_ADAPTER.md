> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Callback-driven native Bait adapter

This stage contains an actual IL2CPP adapter implementation and its existing
runtime diagnostic bridge. It has compiled for ARM64 iOS 17. It has not yet been
executed in a live multiplayer round. It is a manually assigned Bait subset,
not a complete EHR port.

The separate interceptor must call the original game `MurderPlayer` first and
then call `EHRLiveBridgeOnConfirmedMurder(killer, victim, flags)` on Unity's main
thread. This stage installs no interceptor, uses no instruction offsets, and
patches no executable memory. Alive/dead polling never invents killer identity.

Public APIs are declared in `EHRLiveBridge.h`:

- `EHRLiveBridgeStart()` starts diagnostic sampling and the due-action timer.
- `EHRLiveBridgeConfigureBait(enabled, selectedPlayerId, minSeconds, maxSeconds)`
  returns 1 for accepted configuration and 0 for invalid input. Default is
  disabled and unselected. Player IDs are 0...253; -1 is allowed only disabled.
  Delays are 0...90 seconds. Inverted min/max follows EHR's 150 ms fallback.
- `EHRLiveBridgeCopyBaitStatus()` is safe to read from any thread.
- `EHRLiveBridgeOnConfirmedMurder(void *, void *, uint32_t)` is the interceptor
  callback. Off-main pointers are rejected without delayed dereferencing.
- `EHRLiveBridgeCopySnapshot()` includes `bait` and
  `EHRGameCallbackLastEvent`. The existing snapshot notification still fires.
- `EHRLiveBridgeStop()` cancels timers and releases pending/round GC roots.

The adapter resolves and validates both method signatures from installed
metadata. It requires `MurderPlayer(PlayerControl, MurderResultFlags): void`,
32-bit enum backing, no byref arguments, and
`CmdReportDeadBody(NetworkedPlayerInfo): void`. Protection/error flag values are
read from the actual enum metadata. No flag numbers are guessed.

An event becomes eligible only after the real victim is dead, the local client
is the host in a `Started` session with live `ShipStatus`, and the chosen Bait
player matches. It roots killer, victim, victim data, and the round's ShipStatus
using IL2CPP GC handles. At the due time it checks host, started state, same
rooted round, meeting/exile absence, exact player identities and data identity,
living connected killer, and dead connected victim again. It then invokes the
validated normal reporting method with the managed victim-data reference.

`callbackObserved` stays false until an actual validated confirmed-death
callback arrives. `reportCallsCompleted` means the managed method returned
without an exception; it does not assert a network response or meeting result.
`gameplayMutationPerformed` records whether a report call was attempted.
Settings changes, host loss, unknown state, meeting/exile, round transitions,
and stop discard pending reports conservatively. Victim deduplication lasts
the round, so resurrection/re-kill behavior is outside this subset. No custom
sounds, notifications, forced meetings, EHR add-on interactions or role UI are
implemented. The default diagnostic Instance lookup reads singleton storage
only to avoid auto-creating game objects.

The `uintptr_t` GC-handle transport is opaque: it preserves ARM64 register
values for the confirmed Unity 2022.3.62f3 build and is never interpreted as a
pointer or used in arithmetic.

Build against the canonical portable core (not copied into this stage):

```sh
xcrun --sdk iphoneos clang++ -std=c++17 -fobjc-arc -fobjc-arc-exceptions \
  -target arm64-apple-ios17.0 \
  -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.1.sdk \
  -I /path/to/ehr-ios/native/include \
  -Wall -Wextra -Werror -c EHRLiveBridge.mm -o EHRLiveBridge-ios-arm64.o
```

Also link the canonical `native/EHRHostCore.cpp` into the consuming target. The
existing `EHR_LIVE_BRIDGE_AUTOSTART=0` opt-out remains available if the bootstrap
wants to call `Start()` explicitly.
