# Known issues and current native work

This snapshot is incomplete. Physical build 48 reached Online lobby hosting and mod settings, then a black screen after starting the game. Physical build 49 reached a solo game and an early win, consistent with EHR's low-player end conditions. Its trace reached custom intro, ship initialization, game start and game end without new source failures. Physical build 50 then disconnected the host when a vanilla peer joined. Following build-52 delivery, the user reports playing a match with a vanilla peer. Apple authentication, wider account safety, multiplayer stability and full role behavior remain unresolved or unverified.

## Ownership and EHR website integration

Build 59 requires a claimed Among Us entitlement in the itch.io account behind
the entered key. App Store ownership does not appear in that separate library.
The current client blocks game input until its ownership check passes and keeps
EHR directory requests gated on actual completed game sign-in. The website
listing option defaults off; enable it before using a fresh `/confirmauth` code.
The exact helper verified a real non-owning account as a negative lookup on
Mac. After purchase, build 61 confirmed that account on iPhone, followed by
actual EOS success and full game-account completion.
Client fixtures and signed startup do not establish live EHR website acceptance,
backend policy or authenticated multiplayer stability. See
[ownership](ITCH_SIGN_IN.md) and [website contracts](IOS_LOBBY_DIRECTORY.md).

## Joining another EHR host

Builds through 61 can reject an official 8.0.3 host despite displaying the same
version. The source revision, plugin version and fork match, but a detached
upstream checkout generated `ce23f0d(HEAD)` instead of the official release's
`ce23f0d(main)`. EHR compares the complete tag, so this is a real metadata
mismatch. The build correction uses verified release provenance and preserves
the existing version comparator. After installing build 62, the player confirmed
joining another official 8.0.3 host and staying connected past the previous
five-second disconnect. This does not establish every role or complete-round
compatibility.

## Remembered-key startup timing

An ownership-verified saved login can reach the outer game-login request before
normal credential capture is ready. The earlier provider retired that attempt,
so a later Account sign-in could ask for the key again. The corrected provider
retains the same verified attempt for up to 120 seconds only when no form or
SDK activity exists. Normal capture or explicit Account sign-in can consume it;
expiry, cancellation, clearing and new input fence it. Timers do not retry login.
A genuine missing-profile result without a visible form remains unconfirmed;
there is no automatic account creation.

## Impostor-role scrolling and native search

An owned build-63 OS crash reached an explicit abort in native iterator error
construction, before borrowing/raising the exception. The report does not
identify the initiating source fault or which shared abort prerequisite failed.
Build 64 uses the validated native exception factory with independent pinned
handles and persists bounded coroutine failure facts before raising. The player
then scrolled the impostor roles without exiting to Home Screen, after a short
blocked interval. Returning to the main menu froze until restart. Build 65 adds
a loading indicator, smaller batches, cancellation on tab/menu close and cache
reuse repairs. The initiating fault and menu-freeze cause are not proven; a new
phone test remains necessary. See [build 65 evidence](BUILD65_VALIDATION.md).

The native Find Game request previously lacked the modern per-request EHR mod
filter. Build 64 supplies it only at the verified search callsite, after the
original helper, while retaining the host-only registration needed by the
current vanilla-peer path. Build 64 still displayed an empty list in the phone
test. Build 65 defaults to the original **All lobbies** request and makes the
**EHR lobbies** filter optional in the EHR panel. The pools differ; website-listed
rooms are not necessarily advertised in either one. The official website
directory remains available inside the app. Actual results and joining need a
new player test; do not infer a fix from owned filter construction alone.

## Later gameplay observation

The subsequent host numeric cache contains player join, host-start/ship and
player-spawn progress. It also records null references in
`GameStartManager.Start` / `CheckSettingsDiffs` and ten
`MapRoomDoorsStartPatch.Postfix` cast exceptions. The map-door source attempts
two strict sibling-system casts; those failures need a separate source/bridge
review. No game-end route is recorded. Its disconnect reason is 16 (`Destroy`).
The cache does not contain an explicit build identity. These facts corroborate
gameplay progress and remaining defects without proving the complete round or
which build emitted it. See [the validation limits](BUILD52_VALIDATION.md).

## Vanilla-peer join disconnect

The user created an Online lobby in build 50 and a vanilla client joined. The
modded phone disconnected; the remaining client became host of a vanilla lobby.
The host's disconnect callbacks completed, but their reason was not in that
build's numeric cache. Physical build 51 recorded reason 10,
`DisconnectReasons.Hacking`, verified against the pinned metadata. The popup
described a kick. This identifies the server's category, not the offending
message or rule. The observer records only the original scalar enum at the
existing validated native boundary, alongside numeric status/timing. It does
not log the reason string, packet contents or account identifiers.

One new native `RpcSetName` null-reference exception occurred about 240 ms after
`DisconnectInternal` returned. It matches a four-second delayed name restore
scheduled by the join callback without rechecking lobby validity. This is a
separate cleanup defect and does not explain the initiating disconnect. The
build-52 source rechecks lobby, host, game/client identity and local
player ownership before the delayed restore, and skips it when those current
values no longer match.

The source schedules welcome messages around three seconds after a spawn. Their
send timing is close to the disconnect, and the lower-level system-message send
previously omitted the native chat-mode gate. Build 52 now requires the same
`FreeChatOrQuickChat` mode as native `ChatController.SendChat` before any system
network writer creation or mutation. Missing or failed settings deny the send;
local-only delivery remains available. This parity correction does not prove
which rule caused the server's `Hacking` classification. No permissions are
forced or enforcement disabled. See [the guards](MULTIPLAYER_SEND_GUARDS.md).
Custom-settings sync already rejects vanilla targets; keep that guard. Further
multiplayer tests should use disposable identities after a concrete invalid-send
repair; the valuable family account remains outside testing.

## Confirmed native coroutine capacity pressure

The bounded numeric diagnostic recorded category 18 at count/limit 256, usually with one active source and 255 terminal carrier tombstones. Deferred release backlog was zero in those records and gateway roots were below their separate 65,536 limit. New coroutine registrations failed; repeated sender/scheduler failures followed. Later collection/sweeping reduced the count, so the final snapshot alone hides the earlier exhaustion.

The options sender creates short-lived helper iterators continuously. Build 47 kept completed carrier identities as weak tombstones until collection. Build 48 retires their registry slots immediately after publishing a private terminal marker in the exact validated carrier's existing field. The active limit stays 256, and failed publication retains the safe bounded fallback. Owned stress fixtures retain 1,024 completed carriers beside one active carrier without filling the registry. See [terminal retirement](ITERATOR_RETIREMENT.md) for the runtime validation and evidence limits. This capacity pressure is confirmed; it does not explain every possible black-screen path.

In the build-48 phone reproduction, 2,941 carriers had been created and 2,939 closed and retired, leaving two active entries and no retained terminal entries. No callback failures or capacity guards were recorded. The black screen persisted through a different game-start path.

## Native host-start factory bypass

The phone trace recorded `CoStartGame` and ship initialization, but no `CoStartGameHost` factory route or intro. Inspection of the pinned native parent `MoveNext` confirms it directly constructs the host iterator at its host yields, bypassing the patched method entry. The EHR host-start replacement therefore never runs at that boundary.

Build 49 adds an optional native adapter after the original parent `MoveNext`. It recognizes only the exact host yield, checks matching owners and untouched state, invokes the existing patched host factory once, then publishes an active production iterator through the public reference-field API. Activation, owners and iterator fields are checked again before commit. Other yields remain unchanged. See [the adapter](IOS_GAME_START_ITERATOR.md) and [build-49 validation](BUILD49_VALIDATION.md).

The adapter passed synthetic owner/reentrancy cases and an owned probe in the actual signed runtime. That probe deliberately avoids real game owners and scene/network operations. The separate physical build-49 trace then recorded one successful real-owner replacement and one host-factory call. The custom host coroutine and intro completed, and `ShipStatus.Begin` allowed the original after source role setup. The earlier black screen did not recur in that attempt; this does not certify every player/role/map combination.

## Earlier game-start native exception

Build 47's `GameStartManager.Start` recorded one dispatched failure with retained native exception and original participation. That route has map-icon callbacks and a start callback. The evidence does not identify which original/nested operation produced the exception. Build 48 adds bounded numeric source callback/stage and native method/exception metadata diagnostics while preserving the original exception and call behavior. The build-48 phone reproduction recorded a successful `GameStartManager.Start` and no failure details. See [sanitized route facts](RUNTIME_BUG_FACTS_47.md) and [failure diagnostics](NATIVE_PATCH_FAILURE_DIAGNOSTICS.md).

## Apple/EOS authentication

Apple authorization callbacks can complete, but the original EOS platform login returned 7000 (`EOS_Connect_ExternalTokenValidationFailed`). This proves token validation failed, not a particular audience/expiry/provider cause. The original game then automatically retries platform sign-in, producing repeated Apple sheets. Successful account authentication and progression safety are unverified.

No token contents were read, no success was fabricated and no online/account permission checks were removed. This snapshot includes a default-disabled retry-failure guard. A development build can explicitly opt in after exact runtime metadata preparation succeeds. It routes one synchronous same-owner automatic retry after normal result 7000 to the original native failure handler. The build-48 phone test stopped repeating the Apple sheet after one attempt. Build 49 still recorded one Apple success followed by one EOS 7000 result. The guard does not make the backend accept a token. See [the guard](AUTH_RETRY_GUARD.md). Use disposable test identities; valuable accounts remain outside testing.

Build 50 also recorded Apple success followed by EOS 7000 and a later device-ID
fallback. Physical build 51's 13-event history confirms the Apple request used
enum 11 (`AppleIdToken`), then EOS returned 7000, and the later device-ID
fallback used enum 10. The original last-only field described that fallback.
The bounded observer recorded no unknown types, overwrites or faults. See
[handoff diagnostics](AUTH_HANDOFF_DIAGNOSTICS.md). The rejection cause remains
unproven; publisher/provider configuration may require confirmation.

## itch.io first-profile continuation

The build-55 phone test submitted one key and received one actual EOS result 3
(`InvalidUser`), with local status 0 and no provider faults. The SDK result was
not forwarded into the game's account-creation path in that build; no completed
sign-in was observed. This result identifies a missing product-user path rather
than proving invalid credentials or an Apple rejection.

The next implementation offers an explicit **Create new game profile** action
only for a genuine callback with a usable continuation. Its original game flow
can migrate device guest state, so both confirmation and the actual migration
boundary require the original device guest identifier to be empty. Unknown or
existing guest state stops this route without clearing or transferring data.
The original age, storage and permission prompts remain in charge. Full
completion is a separate observation; the original EOS result 3 is preserved.
See [the provider flow and limits](ITCH_SIGN_IN.md).

The build-56 phone attempt then returned local 7 / EOS 3 at the confirmation
precheck, before any original callback or migration entry. A separately signed
**EHR Sign-in Test** app was then installed to test fresh storage while retaining
the old guest and the unchanged guard.

On that test phone, build 57 reached the real full-account endpoint after the
explicit first-profile action and passed guest guard, preserving EOS result 3.
A later recorded run reused the remembered credential without a form or manual
submission, returned EOS success (0), and again reached full game completion.
This supports the isolated app's normal account and saved-key paths; it does
not validate existing-guest migration, valuable-account safety, every renewal
or authenticated multiplayer. See [the phone evidence](ISOLATED_SIGNIN_TEST.md).

## Other boundaries

`GetConnectionData` has a predispatch missing-receiver observation. Its unentered path calls the unchanged original once; this is not evidence that a source handshake body failed. Build 48 also adds generation-guarded settings-build cleanup after completion, disposal or a fault. It cannot remove a replacement generation's coroutine handle. See [settings cleanup](SETTINGS_BUILD_CLEANUP.md).

Most detailed documents are implementation-stage notes, including earlier milestones and fixture commands. This file, README, ARCHITECTURE and BUILDING describe the public snapshot's current scope. Native maps are build-specific, and portability to a new game version requires a fresh ABI/image validation.
