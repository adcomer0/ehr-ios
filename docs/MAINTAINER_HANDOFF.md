# EHR Among Us: maintainer handoff

This is a source and tooling handoff for the ownership-gated native iOS
build-65 development candidate. It is not an App Store/TestFlight release artifact or evidence of
publisher/distribution approval. The current local profile is development
signing for registered devices. The EHR team handles its release signing and
authorized game-content distribution path.

Use a fresh clone for contributions. Do not merge branches from earlier
experimental repository history into the current main branch.

## App and sign-in

The visible app is **EHR Among Us** with the original [EHR fan icon](ARTWORK.md).
The modern UIKit entry accepts an itch.io API key, submits a real SDK request,
and offers **Create game account** only after a genuine missing-user result and
usable continuation. The app verifies a claimed Among Us entitlement with that same itch.io key
before attempting game authentication. The player confirms creation; original age, storage and
permission prompts remain in charge. **Continue to game** exposes those prompts.

After actual full account completion, the key is saved automatically in this
app's private, nonsynchronized, device-only Keychain service. Later normal login
can reuse it without showing the form. A saved-key bootstrap that reaches the
game before its normal platform-login entry is ready retains that verified
attempt for at most 120 seconds. Normal credential capture or an explicit
Account sign-in may resume it; timers do not retry login. No key is embedded in the build,
returned by the diagnostics or shared with another app's bundle.

**EHR badge → Account → Remove saved login** asks for confirmation, removes only
the app's saved key and forgets its in-memory credential. Pending UI generations
are retired so a late result cannot save the removed key again. Provider work
then stays frozen until the player closes and reopens the app. This does not
delete the game profile, app data or progress, nor claim immediate server logout.
The app does not terminate itself or reset game authentication/permission flags.

Keep the working app's identifier/key service for its updates. The personal
consolidation upgrades the previously working app in place before removing the
separate legacy preview, so its account and remembered key are retained.
That user-authorized cleanup is not part of the protected installer; the public
installer still never uninstalls or resets an app automatically.

The **EHR lobbies** menu opens the official directory inside Safari view, with
website-owned sign-in and user-controlled code copying. It does not read
website credentials or replace stock matchmaking. See [browser contracts](IOS_LOBBY_BROWSER.md).

## Build selection

Use the normal [local build pipeline](BUILDING.md), with your own matching game,
native maps, NativeAOT library, app identifier, certificate and profile. Add:

```sh
--display-name "EHR Among Us" \
--app-icon app/Assets.xcassets/AppIcon.appiconset/AppIcon.png \
--itch-auth-map PRIVATE_ITCH_MAP \
--ehr-directory \
--lobby-search-map PRIVATE_SEARCH_MAP
```

The optional search map exposes **All lobbies** (default) and **EHR lobbies**
in the EHR panel. Refresh Find Game after changing the saved choice. All keeps
the original request; EHR adds the verified per-request filter only after the
same ownership/full-sign-in gate. Global host registration is unchanged.
See [search pools and limits](IOS_LOBBY_SEARCH.md).
The current settings-loading reader must be bound and idle in the passive startup
proof. The iterator-error factory and filter construction proofs are required
by the installer when their build flags are selected.

The source builder also verifies the [official release identity](UPSTREAM_RELEASE_IDENTITY.md)
from the compiled assembly; do not remove the exact source/policy checks or
weaken the host comparator.

The exact framework remains pinned to the documented game baseline; a newer
game needs fresh mapping/ABI validation. The UI/icon changes do not replace the
796 selected managed sources or alter their 224-resource catalog. The signed
Mac runtime and protected install checks remain required after rebuilding. See
[device connection checks](IOS_DEVICE_CONNECTION.md) for wireless delivery.

Manual key entry is the configured path. Browser OAuth code remains available
but hidden when no public OAuth client and matching redirect are configured.
Ownership checks are mandatory for the itch.io provider; there is no production
skip flag. The optional EHR website directory additionally needs completed game
authentication, native predicate binding and the player's listing option enabled.
Settings-generated personal keys have broad itch.io API access; a production
OAuth registration and its accepted credential configuration are a separate
integration task. Do not collect player keys in Git, chat or support screenshots.

## What remains to validate

The isolated build-57 phone observations establish first-profile completion and
a later remembered-key normal login on one test phone. The exact helper also established
a real negative ownership lookup on Mac. After purchase, build 61 on iPhone
established positive entitlement verification, actual EOS success and full
game-account completion. Build 62 then completed a fresh ownership check and
remembered-key login after upgrade, with EOS success/full completion and no
prompt or manual submission. The player then joined another official EHR 8.0.3
host and stayed connected past the former version countdown. Earlier guest play had
one user-reported match with a vanilla peer. These are not coverage of every
role, map, network condition or device. See [known issues](KNOWN_ISSUES.md),
[authentication evidence](ISOLATED_SIGNIN_TEST.md) and the [current validation](BUILD65_VALIDATION.md).

Existing guest-to-platform migration remains intentionally unsupported by the
first-profile route: nonempty or unknown guest identity stops it. Do not remove
that guard or clear a guest identifier to make login proceed. Valuable official
accounts and progression are outside the test evidence; no ban protection or
progress-preservation guarantee is established.

The public repository carries source, original artwork and tooling, preserving
the [GPL license](../LICENSE) and [dependency/provenance notices](../NOTICE.md).
It carries no original game binaries/assets, complete-game IPA, provisioning
profiles, signing material, credentials or private device/account diagnostics.
