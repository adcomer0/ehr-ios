# Native itch.io sign-in

The optional `--itch-auth-map` build selects itch.io instead of the game's iOS
Apple credential acquisition. It remains an experimental integration: compiling
and testing the adapter does not establish that the game's service accepts a
particular itch.io credential, preserves progression or permits this client.

## Ownership requirement

The configured iOS app requires the itch.io credential's account to have a
claimed Among Us entitlement. An itch.io account or accepted EOS login alone
is not proof of owning the game. The native preflight sends the same credential
only to `https://api.itch.io/profile/owned-keys`, filtered to Among Us game
`257677`. It follows bounded pagination and requires a matching numeric game
identifier in an actual owned-key record. It performs no purchase, claim or
file download. The game identifier is from the
[official Among Us itch.io page](https://innersloth.itch.io/among-us); the
[itch.io API contract](https://itch.io/docs/api/serverside) defines the owned-key
query and its `profile:owned` scope.

Manual keys, remembered keys, browser credentials and renewals all go through
this check before the bundled EOS SDK receives the credential for game
authentication. The EHR website receives separate EOS/session credentials and
never receives the itch.io key. Browser OAuth requests
`profile:me profile:owned`. A nonempty short page is not treated as the end of
results. Invalid keys, missing scope, malformed data, redirects, network errors
and service failures fail closed with distinct messages; they are not reported
as a missing purchase. No entitlement means none was returned in the claimed
library: an unclaimed purchase, gift or bundle may need claiming first.

The app's opaque ownership screen blocks game input until verification passes,
including the temporary-account route. Cancellation or removing the saved login
restores that screen. It leaves the game's account and permission flags intact;
once ownership passes, native account/age/consent prompts can run normally.
The screen is an app-side requirement, not a server attestation. The EHR service
continues to decide whether its own verification and listing requests succeed.

## Player flow

In **EHR Among Us**, enter a personal itch.io API key in the secure sign-in
field and tap **Sign in**. Use a separate test identity for initial tests.
The compact EHR badge also has an **Account** screen, with a **Sign in** action
when an idle, unsigned-in flow can be resumed. Personal keys have broad itch.io API access; never put
one in chat, issues, source, build arguments or diagnostics. Each player using
itch.io needs their own identity. A vanilla peer can continue using the official
game and its existing login without installing EHR.

An actual EOS `InvalidUser` result (3) can mean this identity needs its first
game profile. When the actual callback includes a usable continuation, the UI
offers **Create game account**. Nothing is created until the player taps
that action. The original game then controls creation, age and account prompts;
use **Continue to game** when prompted. The offer expires after 90 seconds.
Cancelling or expiring before confirmation discards the retained candidate;
once confirmed, subsequent game prompts remain controlled by the original game.
The opaque continuation is never written to disk or printed.

This separate-profile route requires the game's existing device guest identifier
to be empty, checked again immediately before its migration method. An existing
guest or an unknown state stops the route. It does not clear, delete, transfer
or merge that guest's data to make creation proceed.

The app remembers the key automatically after the original game's full
account-completion method actually runs. Accepting the key alone does not save
it. Request buffers are bounded and wiped after use; the successful session
also retains an in-memory credential for renewal. Persistent storage is
restricted to this app's own Keychain service and default access group, without
synchronization, using `WhenUnlockedThisDeviceOnly`. The official game's
account container and Keychain items are not imported or modified.

On subsequent normal login, the app can use its own saved key without showing
the entry form. This reuses the existing itch.io game identity. Keys are not
shared with another bundle, including the older EHR app. The branded build 58
upgrades the working build-57 identity in place, preserving its private storage.
Build 57 has one observed later-run saved-key login with no form/manual
submission, EOS success and actual full-account completion. Build 61 confirmed
real ownership after purchase and a later actual EOS/full-account success; see
[the phone evidence](ISOLATED_SIGNIN_TEST.md). Build 62 repeated a remembered-key
login after upgrade: fresh ownership check, EOS success/full completion, zero
prompts/manual submissions. See [current validation](BUILD62_VALIDATION.md).

If ownership succeeds before the game is ready to capture its normal login,
the saved-key flow can wait up to 120 seconds for that same attempt. A normal
capture or **Account → Sign in** resumes it without another key entry. The wait
does not retry login on a timer, extend its deadline or create a game profile.
Expiry retires the auth attempt while keeping the independent license result.

To remove the remembered credential, open **Account → Remove saved login** and
confirm. This deletes only this app's saved key, wipes its in-memory credential,
and cancels its pending sign-in flow. Late callbacks cannot save the key again.
Then manually close and reopen the app to enter another key. It does not delete
the game account or progress, unlink accounts, or immediately log the native
SDK out of its current session. A failed Keychain deletion is reported without
claiming removal succeeded. The app does not terminate itself or reset its data.

Browser sign-in is implemented but requires a registered public OAuth client
and matching redirect. Its row is hidden without that configuration; manual
entry remains usable. The browser uses an authorization code, fresh S256
PKCE/state, the `profile:me profile:owned` scopes and an exact registered callback. Token
exchange uses ephemeral HTTPS with response bounds and refuses redirects. No
client secret is embedded.

These are distinct credential sources. A settings-generated personal key is
not automatically equivalent to an OAuth-issued key for every service. No
account linking, merging, automatic identity creation or ownership override is
part of this integration. A new itch.io identity does not automatically acquire
an Apple account's purchases or progress. See the [itch API](https://itch.io/docs/api/serverside)
and [OAuth documentation](https://itch.io/docs/api/oauth).

## Native boundary

The normal provider entry preserves the original outer login checks and captures
the exact success delegate and failure action supplied to
`LoginWithCorrectPlatformImpl`. Early renewal binds the pinned original silent
method through the public delegate factory. The runtime validates each single
invocation, target owner and pinned callback method. Original initialization and
delegate field writes use caught runtime APIs and normal reference barriers.

The adapter obtains the existing platform's Connect interface and calls the
bundled SDK's `EOS_Connect_Login` with actual `ItchioKey` credentials. SDK image,
code fingerprint, method associations and native/managed callback layouts must
match the reviewed game. No Apple credential object or injected runtime class
is used. Real successful SDK callbacks, and a genuine `InvalidUser` callback after
the explicit new-profile action, are marshaled through the original SDK and
delivered once to the captured game delegate. The adapter never fabricates
a successful result, sets logged-in flags or manually calls a completion method.

The original game performs storage, age, consent and permission handling. A
passive observer recognizes its real full-account completion only after the
unmodified method returns. After the explicitly confirmed first-profile path,
the original EOS result remains 3 even when this final endpoint completes;
completion is tracked separately rather than inventing an EOS success. An EOS
acceptance result alone is shown as
**Credentials accepted; finish any account prompts in the game**. Silent renewal
requires the same live owner and credential as a previous observed full login.
It binds the game's existing silent callback through the public delegate
factory and forwards genuine renewal results. The original temporary-guest
renewal branch is preserved only after the same native guest-status check.
Failures and cancellations do not switch back to Apple acquisition. A rejected
or cancelled normal acquisition can retain a bounded, keyless context so an
explicit retry from the EHR button can resume that same pending flow. Owner,
callback identity and native in-flight state must still match; the adapter does
not clear native authentication or permission flags to unlock a new flow.
The selected development build writes a bounded numeric result snapshot to its
own cache for diagnosis. It contains fixed counters and status values, without
keys, user identifiers, callback payloads or arbitrary exception text.

## Local build selection

Generate an outside-Git map for the exact existing game inputs:

```sh
python3 tools/prepare_itch_auth_map.py \
  --framework FRAMEWORK --metadata METADATA --pins SOURCE_PIN_REPORT \
  --output PRIVATE_ITCH_MAP
```

Add `--itch-auth-map PRIVATE_ITCH_MAP` to the full-source builder. Do not activate
the legacy Apple retry guard or select the old Apple handoff observer in that
build. Optional browser configuration uses
`--itch-oauth-client-id PUBLIC_CLIENT_ID` and a registered
`--itch-oauth-redirect-uri OWN_BUNDLE.itch://oauth/callback`. These identify the
OAuth application; they are not player credentials. The candidate does not take
ownership of the official game's URL scheme.

The protected installer requires matching signed Mac startup, passive provider
preparation, zero real login/account actions during that test and a passed
original-SDK default-value marshaling/root-conservation proof, in addition to
its existing binary, profile, identity and device checks. Real backend acceptance
requires a separate human sign-in test. No valuable account should be used to
establish that first result.
