# Known issues and build-49 work

This snapshot is incomplete. Physical build 48 reached Online lobby hosting and mod settings, then a black screen after starting the game. Physical build 49 reached a game and the user reported an immediate win. Its trace reached custom intro, ship initialization, game start and game end without new source failures. Player-count and winner-condition interpretation remain pending; a normal multiplayer round, meetings, every role and vanilla-peer combinations remain unverified.

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

## Other boundaries

`GetConnectionData` has a predispatch missing-receiver observation. Its unentered path calls the unchanged original once; this is not evidence that a source handshake body failed. Build 48 also adds generation-guarded settings-build cleanup after completion, disposal or a fault. It cannot remove a replacement generation's coroutine handle. See [settings cleanup](SETTINGS_BUILD_CLEANUP.md).

Most detailed documents are implementation-stage notes, including earlier milestones and fixture commands. This file, README, ARCHITECTURE and BUILDING describe the public snapshot's current scope. Native maps are build-specific, and portability to a new game version requires a fresh ABI/image validation.
