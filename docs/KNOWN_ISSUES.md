# Known issues and build-51 work

This snapshot is incomplete. Physical build 48 reached Online lobby hosting and mod settings, then a black screen after starting the game. Physical build 49 reached a solo game and an early win, consistent with EHR's low-player end conditions. Its trace reached custom intro, ship initialization, game start and game end without new source failures. Physical build 50 then disconnected the host when a vanilla peer joined. Authentication and a normal multiplayer round remain unresolved.

## Vanilla-peer join disconnect

The user created an Online lobby in build 50 and a vanilla client joined. The
modded phone disconnected; the remaining client became host of a vanilla lobby.
The host's disconnect callbacks completed, but their reason was not in that
build's numeric cache. Build 51 records only the original `DisconnectReasons`
enum at the existing validated native boundary, alongside numeric status/timing.
It does not log the reason string, packet contents or account identifiers.

One new native `RpcSetName` null-reference exception occurred about 240 ms after
`DisconnectInternal` returned. It matches a four-second delayed name restore
scheduled by the join callback without rechecking lobby validity. This is a
separate cleanup defect and does not explain the initiating disconnect.

The source schedules welcome messages around three seconds after a spawn. Their
send timing is close to the disconnect, and the lower-level system-message send
has no free-chat permission guard. Permission rejection is a hypothesis until
the disconnect reason and permissions are established. No permission checks
have been removed or forced, and no message behavior has been changed on that
hypothesis. Custom-settings sync already rejects vanilla targets; keep that guard.

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
fallback. Its last-observed credential enum belongs to that later fallback;
it does not establish the enum used for the rejected Apple request. Build 51
retains a 32-event numeric history to preserve that distinction. See
[handoff diagnostics](AUTH_HANDOFF_DIAGNOSTICS.md). The rejection cause remains
unproven; publisher/provider configuration may require confirmation.

## Other boundaries

`GetConnectionData` has a predispatch missing-receiver observation. Its unentered path calls the unchanged original once; this is not evidence that a source handshake body failed. Build 48 also adds generation-guarded settings-build cleanup after completion, disposal or a fault. It cannot remove a replacement generation's coroutine handle. See [settings cleanup](SETTINGS_BUILD_CLEANUP.md).

Most detailed documents are implementation-stage notes, including earlier milestones and fixture commands. This file, README, ARCHITECTURE and BUILDING describe the public snapshot's current scope. Native maps are build-specific, and portability to a new game version requires a fresh ABI/image validation.
