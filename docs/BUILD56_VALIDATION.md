# Build 56: explicit first-profile continuation

The first physical build-55 itch.io attempt returned actual EOS `InvalidUser`
(3), with local status 0, one SDK request and one callback, and no provider
faults. That build stopped before account creation; completed sign-in was not
observed. The key and callback handles were not read or logged by tooling.

Build 56 adds **Create new game profile** for a genuine callback with a usable
continuation. This is an explicit player action; merely entering a key does not
create a profile. The original game performs creation, age, storage and
permission handling. The offer expires after 90 seconds. No account linking,
guest deletion or transfer is added by the adapter.

## Preserving the native flow

The original game can migrate a device guest into a platform profile. This route
requires its original device guest identifier getter to return null/empty both
at confirmation and immediately before the native migration method. Existing
or unknown guest state stops the route; no guest identifier or permission flag
is cleared to make it proceed.

A rejected migration boundary records the failure and raises an actual owned
IL2CPP exception, preventing the native caller from continuing into its save.
Allowed and unrelated calls enter the original method once. A cancelled
confirmed flow keeps its migration guard across manager replacement until its
genuine late final endpoint or process exit; it cannot become an unguarded old
callback.

Completion requires the actual original full-account endpoint and the same
confirmed origin's passed migration check. The EOS result remains 3; the
adapter does not replace it with success. Optional credential persistence and
renewal remain gated by observed full completion.

## Validation

- All **335** configured regression tests passed, with the reviewed local source
  inputs and .NET tooling supplied; none were skipped.
- The production runtime with owned SDK substitutes passed **844** checks,
  including continuation freshness, no automatic creation, original-once
  delivery, cancellation, expiry, owner replacement and migration rejection.
- The exact coordinator fixture passed explicit-action, stale-button, key
  wiping, completion-provenance and native-failure propagation cases.
- The UI policy passed **477** checks; its actual UIKit simulator fixture
  passed **103** checks. Keys, HTTP and Keychain were substituted in these tests.
- Strict iOS ARM64 compilation and all **20** exact method facts / **four**
  hook contracts passed.

The final revised signed candidate passed its matching iOS-on-Mac XCTest run.
Its four candidate binaries stayed unchanged, with **5,049** options and **292**
permitted bindings. Provider startup had zero real login, confirmation or
migration operations. Original SDK callback marshaling conserved roots
(**6,784 before and after**), and the original silent delegate bound against the
existing game owner. No new game owner was constructed.

The protected installer requires the new untouched-startup fields as well as
the existing binary, signature, profile, exact-device and runtime proofs. The
selected **796** managed sources and **224** resource catalog entries are
unchanged.

## Remaining live test

The first install attempt for this revised build found the test iPhone
unreachable and performed no installation. Build 55 remains the last confirmed
phone version at this validation checkpoint. A real first-profile attempt,
backend acceptance and completed sign-in remain unverified. No identity was
created, linked or merged by the development tests or tools.

Use a separate test identity. See [the player flow](ITCH_SIGN_IN.md) and
[known issues](KNOWN_ISSUES.md). Browser OAuth remains unconfigured.
