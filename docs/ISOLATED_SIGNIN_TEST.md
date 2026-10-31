# Separate app for the first-profile test

This document records the historical build-57 isolation experiment. Build 58
renames and upgrades that same working identity to **EHR Among Us**. For its
current automatic remembering and Account controls, see
[the current player flow](ITCH_SIGN_IN.md). Labels and Remember instructions
below describe the earlier test UI.

The build-56 phone attempt returned local status 7 with EOS `InvalidUser` (3).
Its numeric snapshot has zero original callback/marshaler calls and zero
migration-boundary calls. The rejection occurred at confirmation's existing
guest check, before the adapter entered account creation. No profile completion
was observed.

Build 57 uses a new, separately provisioned app identifier and the display name
**EHR Sign-in Test**. It is an additional app, leaving the existing EHR app and
its guest data in place. The runtime, account guards and managed source are
unchanged from build 56. This tests the existing first-profile route; it does
not implement migration of an existing guest into an itch.io account.

Build 59 adds mandatory ownership verification before using those credentials.
The build-57 observations below did not test ownership and are historical
account-flow evidence only; see [the current requirement](ITCH_SIGN_IN.md).

## Storage boundary

The signed test app claims only its own default keychain group, with no shared
keychain or application groups. Its effective group differs from the existing
EHR app and the official game. Apple documents that these default groups
isolate each app's keychain items. The sign-in UI additionally derives its key
service from the current bundle identifier, with no previous-service fallback.
See [Apple's keychain access-group documentation](https://developer.apple.com/documentation/Security/sharing-access-to-keychain-items-among-a-collection-of-apps).

No existing app is uninstalled, renamed, reset or copied into this app's data
container. No credential, saved player data or Keychain item is imported. The
profile covers the exact test phone and Mac; no private signing or device
identity is a public build input.

Fresh local storage does not prove a particular remote account history. If the
SDK still supplies a guest identity, the unchanged strict guard refuses the
route. The adapter does not clear it to proceed. The original startup's failed
DeviceID login path does not automatically create a guest; the separate
temporary-account choice can do so.

## Player test

After installation, open **EHR Sign-in Test** and use the existing test itch.io
key. Keep Remember off. Tap **Use test key**, then **Create new game profile**
if offered, and **Continue to game** to reach the original age/account prompts.
Keep this test outside the temporary-guest play path. Report only the numeric
Status/EOS result or whether **Signed in** appears; never share the key.

The current original game's guest flow has mapping, merge and credential
deletion branches. Simply removing the guard is not a safe implementation of
separate profiles. Supporting an existing guest needs a separate reviewed flow
with appropriate identity, query-result and user-choice checks.

## Validation checkpoint

- The 11 focused builder tests and the 41 combined builder, protected-install
  and signing tests passed. `--display-name` preserves the normal default and
  rejects blank, oversized or control-containing labels before reading inputs.
- Native inputs match the build-56 snapshot; its 844 runtime, 477 policy and
  103 UIKit checks remain the unchanged-code baseline.
- The separately signed build-57 Mac runtime passed, with four unchanged
  candidate binaries, 5,049 options and 292 bindings. The provider prepared with
  zero credential submissions, SDK login or migration operations.
- Actual SDK callback marshaling conserved roots (6,844 before and after), and
  the original silent delegate bound to the existing game owner without
  constructing another owner or operating an account.

The first protected initial-install attempt found the phone unreachable and
performed no installation. Installation and completed phone sign-in remain
pending at this checkpoint. The initial installer requires this exact new
bundle to be absent and never launches it automatically.

For local staging, add `--display-name "EHR Sign-in Test"` and supply a distinct
own `--bundle-id` with a matching provisioning profile to the normal builder.
Do not change the installed EHR app's identity in place. See
[the provider](ITCH_SIGN_IN.md) and [build-56 evidence](BUILD56_VALIDATION.md).

## Subsequent phone observations

Build 57 was installed and its version confirmed on the exact test phone over
USB. OS app metadata also confirmed that the original EHR app remained at build
56. No app was uninstalled or launched automatically; no account UI or
credential entry was operated by tooling.

The player reported creating the new account. The app's bounded numeric cache
recorded the explicit new-profile confirmation, one genuine original callback,
one passed migration guard with no rejection, and the actual full-account
endpoint. Local status was 0, and the original EOS result remained 3. Remember
was off for that attempt; its save count was 0.

The player then reported that remembered-key sign-in worked. A later recorded
run had one capture and SDK request, no form presentation or manual submission,
one saved/session acquisition, EOS success (0), and actual full completion.
The previous run's form/submission counters were nonzero. The source's key
ownership paths and these reset counters support remembered-key normal login;
the cache does not include a process UUID or independently prove an OS reboot.

The UI's save count was again 0 in that later run because it made no new
Keychain write. Its UI-only completion fields stayed at their initial values
because no controller was presented; the runtime recorded full completion.
No key, account identifier or opaque callback handle was read from the device.

These are observations on one test phone. Existing-guest migration, sharing a
key between the two apps, every future renewal, valuable-account safety and
authenticated multiplayer remain outside this evidence. Keep future updates
of this working app on its existing app identifier and private key service.
