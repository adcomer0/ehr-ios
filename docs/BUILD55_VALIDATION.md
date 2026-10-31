# Build 55: native itch.io provider

The selected build replaces iOS Apple credential acquisition with native itch.io
authentication and retains the original game's account/permission completion.
The existing build-52 managed source selection is unchanged. The draggable
build-54 status badge now also opens the itch.io sign-in screen.

This is a tested implementation awaiting a real human sign-in attempt, not a
verified backend login or account/progression safety claim. No live key was
provided or used during development. No account was linked, merged, reset or
created by these tests. The official game/container was not modified.

## Owned checks

- The configured Python regression suite passed **334 tests**. It includes the
  new source-pinned input, builder, protected-install and auth fixtures.
- The compiled production runtime with an owned fake SDK passed **524 checks**:
  real-result routing, original-once callbacks, cancellation/late/duplicate
  events, keyless same-acquisition retry, nil-failure UI, silent renewal and
  final-completion provenance.
- The exact production provider with owned runtime/UI substitutes passed
  **498 checks**, including neutral notifications, cache wiping, renewed
  credentials, temporary-guest-only forwarding, thread/serial handoff and
  numeric diagnostic whitelists.
- The actual sign-in UI policy passed **443 checks** and its simulator UIKit
  fixture passed **76 checks**. Credentials, Keychain and HTTP were mocked.
  These cover secure entry, default-off Remember, cleanup, full-completion-only
  persistence, PKCE/state/redirect handling and bounded responses.
- Strict iOS ARM64 compilation passed. All **18** method facts mapped for the
  exact source; three entry hooks were checked before signing.

These fixtures do not substitute for a real identity, callback round trip,
expired session, lost connection or account-permission dialog on an iPhone.

## Actual signed runtime

The final candidate passed the matching full-source iOS-on-Mac XCTest run. Its
four source candidate binaries stayed unchanged; startup loaded **5,049** options
and **292** permitted bindings. The selected itch.io provider prepared and
enabled, with zero real SDK login calls, captured attempts or account-completion
calls during startup.

The actual SDK's default-value callback marshaler preserved the owned test
result and conserved roots (**6,755 before and after**). The public delegate
factory successfully bound and classified the original silent callback against
the existing game manager. No new game owner was constructed; no game callback,
real login or credential was invoked/read by this proof. The existing iterator,
host-start, touch, audio and cleanup checks also passed.

The protected installer requires those provider and callback-factory proofs in
addition to its normal signing, binary, profile and exact-device gates.

## Delivery and limits

The final signed build is staged locally. Installation is pending the test
iPhone's developer connection; neither phone received build 55 during this
validation. The original test phone remains on build 54 and the additional phone
on build 52. No pairing, security or account setting was changed to work around
wireless discovery.

Manual test-key entry is available in this build. Browser OAuth code is present
but unconfigured because no registered public client/redirect was supplied.
Invalid/unknown identities do not trigger automatic account creation or linking.
Use a separate identity for the first real result. See [player and implementation
details](ITCH_SIGN_IN.md) and [known gameplay issues](KNOWN_ISSUES.md).
