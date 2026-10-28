> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Protected iOS source profile

The profile excludes six exact source callback descriptors and removes the optional EHR website directory's EOS credential producer. Official game authentication, permission checks, ban checks, XP, purchases, and save implementations are unchanged. `/level` remains recognized and explains that this test profile does not change player levels.

The reviewed upstream is `Gurge44/EndlessHostRoles` commit `ce23f0d050f617a59507e5bb0fbfff751d4b5134`, IL2CPP profile. `tools/source_port/account_protection_policy.json` records all reviewed source hashes and the exact callback/selector identities. The adapter requires that clean commit, all 17 file hashes, and matching dispatcher and selector inventories. A changed pin fails rather than broadening exclusions.

## Descriptor policy

`EHRSourceAccountPolicy.TryExclude(string callbackId, out string reason)` returns true only for:

| Descriptor | Source behavior excluded |
| --- | --- |
| `EHR.Modules.PrivacyPolicyScreenShowPatch::Prefix#15` | Replaces native consent controls and lowers vanilla accepted privacy-policy version. |
| `EHR.Modules.PrivacyPolicyScreenClosePatch::Postfix#16` | Writes and saves that vanilla privacy-policy version. |
| `EHR.ChatControllerAwakePatch::Postfix#41` | Forces Quick Chat restrictions to Free Chat. This callback's additional chat presentation changes are also excluded. |
| `EHR.RunLoginPatch::Prefix#54` | Forces `canOnline=true` under a mod debugger or missing mod consent. Its bundled updater notice also disappears. |
| `EHR.CheckOnlinePermissionsPatch::Prefix#60` | Zeros native `banPoints`. |
| `EHR.GameStartManagerBeginPatch+GameStartManagerStartPatch::Prefix#138` | Writes and saves native minimum-player onboarding flags. |

The root registration path must call this pure policy before preparing each callback. Record reasons in a separate `PolicyExcluded` dictionary. Filter individual descriptors, preserving other callbacks sharing a selector. Empty callback sets must never activate their source handler. Passive metadata preparation does not authorize a handler. The policy does not intercept or replace any native login or permission implementation. Normal native checks continue to run.

## Optional directory and commands

The adapter replaces only the `LobbySharingAPI` class body, preserving `LastRequestTimeStamp`, `LastRoomCode`, `NotifyLobbyStatusChanged(LobbyStatus)`, the enum, and the separate `ExitGamePatch` declaration. The replacement performs no credential read, request, response parsing, room-token logging, or coroutine scheduling. Broad role/game/lobby lifecycle callbacks remain present.

Option 19422 becomes a text row: “EHR website lobby directory: unavailable (account-protected iOS)”. Its default is false. The row's virtual `GetValue()` always returns zero, including after old preset values are loaded through nonvirtual setters or `SetAllValues`. Its update interval is hidden. A narrow `OptionItem.GetName` special case exposes this honest label because the original method is nonvirtual. `/ConfirmAuth` is still recognized and returns the unavailable message locally; it sends no directory-verification request.

Only the `/level` command body changes. It replies “This iOS test profile does not change player levels.” Its registration, neighboring commands, ordinary game XP, and EHR achievements remain unchanged. The original command called the native level RPC; persistent XP modification was not established by that RPC alone.

## Reproduce and compose

Run from the canonical project after applying this package:

```sh
python3 tools/source_port/adapt_account_protection.py \
  --upstream /path/to/workspace/GH/Gurge44/EndlessHostRoles \
  --dispatcher-audit /path/to/ehr-ios-feature-stage/DispatcherIL2CPPReadyV2/static_dispatch_audit.json \
  --selectors /path/to/ehr-ios-feature-stage/DispatcherIL2CPPReadyV2/native_target_selectors.json \
  --output /path/to/local-reports/AccountProtectedSourceNEW
python3 -m unittest discover -s tests -p test_account_protection.py -v
```

Output must be a fresh directory outside Git. The generated `source/` files are a derived overlay, not replacements in the pinned checkout. Add both supplemental sources listed in `account-protection-adaptation.json` to the full-source build. The package contains original tools/policy/tests; full derived upstream files remain private outside Git.

An optional `--source-overlay` composes changes outside the exact protected spans. Pinned spans are normalized to each composed file's LF or CRLF convention; all bytes outside the replaced spans, including generated callback tails, are preserved. If an earlier transform changed protected span text, adaptation fails. Apply this transform before callback/JSON rewrites that touch those spans, then feed the resulting source to later transforms. The standalone command does not run a build, activate hooks, change game state, read accounts, or contact a server.

## Audit boundary

`docs/SOURCE_ACCOUNT_AUDIT.json` distinguishes concrete native-state writes from EHR's own achievements, moderation lists, settings, temporary files, and logs. The reviewed achievements DTO contains an ordinary shortened hash-derived player ID and EHR achievement values; it contains no EOS authentication token. Preset uploads use ordinary friend/PUID identifiers. These are still player-related data, but they are not login credentials. Those integrations are unchanged by this narrow policy.

The purchase-query patch's apparent grant statements are commented out, and its active constant guard returns to the original. No active purchase grant was found there. No vanilla save deletion or direct vanilla XP/currency reset was found in the scoped pinned source review. That is an audit finding, not a guarantee about game servers, account enforcement, future source, or every runtime interaction.

Tests exercise exact descriptor decisions, source pin failure, per-callback filtering, CRLF/composed-source preservation, rejected changed anchors, credential-producer removal, unchanged command recognition, and compiled original fixtures for legacy false values and local command responses. They make zero account/game/network calls. Actual full-source build and device validation remain separate integration gates.
