# Known issues and build-48 work

This snapshot is incomplete. Physical build 47 reached Online lobby hosting and mod settings, encountered lag, then a black screen after Start → Start Immediately. Build 48 contains the fixes and additional diagnostics below; their presence is not evidence that those symptoms are resolved. Full rounds, victory/meeting transitions, every role and vanilla-peer combinations remain unverified.

## Confirmed native coroutine capacity pressure

The bounded numeric diagnostic recorded category 18 at count/limit 256, usually with one active source and 255 terminal carrier tombstones. Deferred release backlog was zero in those records and gateway roots were below their separate 65,536 limit. New coroutine registrations failed; repeated sender/scheduler failures followed. Later collection/sweeping reduced the count, so the final snapshot alone hides the earlier exhaustion.

The options sender creates short-lived helper iterators continuously. Build 47 kept completed carrier identities as weak tombstones until collection. Build 48 retires their registry slots immediately after publishing a private terminal marker in the exact validated carrier's existing field. The active limit stays 256, and failed publication retains the safe bounded fallback. Owned stress fixtures retain 1,024 completed carriers beside one active carrier without filling the registry. See [terminal retirement](ITERATOR_RETIREMENT.md) for the runtime validation and evidence limits. This capacity pressure is confirmed; it does not explain every possible black-screen path.

## Game-start native exception

`GameStartManager.Start` recorded one dispatched failure with retained native exception and original participation. That route has map-icon callbacks and a start callback. The evidence does not yet identify which original/nested operation produced the exception. Build 48 adds bounded numeric source callback/stage and native method/exception metadata diagnostics while preserving the original exception and call behavior. See [sanitized route facts](RUNTIME_BUG_FACTS_47.md) and [failure diagnostics](NATIVE_PATCH_FAILURE_DIAGNOSTICS.md).

## Apple/EOS authentication

Apple authorization callbacks can complete, but the original EOS platform login returned 7000 (`EOS_Connect_ExternalTokenValidationFailed`). This proves token validation failed, not a particular audience/expiry/provider cause. The original game then automatically retries platform sign-in, producing repeated Apple sheets. Successful account authentication and progression safety are unverified.

No token contents were read, no success was fabricated and no online/account permission checks were removed. This snapshot includes a default-disabled retry-failure guard. A development build can explicitly opt in after exact runtime metadata preparation succeeds. It routes one synchronous same-owner automatic retry after normal result 7000 to the original native failure handler. Metadata preparation has passed against the actual runtime without sign-in; live failure-UI behavior remains unverified. It does not make the backend accept a token. See [the guard](AUTH_RETRY_GUARD.md). Use disposable test identities; valuable accounts remain outside testing.

## Other boundaries

`GetConnectionData` has a predispatch missing-receiver observation. Its unentered path calls the unchanged original once; this is not evidence that a source handshake body failed. Build 48 also adds generation-guarded settings-build cleanup after completion, disposal or a fault. It cannot remove a replacement generation's coroutine handle. See [settings cleanup](SETTINGS_BUILD_CLEANUP.md).

Most detailed documents are implementation-stage notes, including earlier milestones and fixture commands. This file, README, ARCHITECTURE and BUILDING describe the public snapshot's current scope. Native maps are build-specific, and portability to a new game version requires a fresh ABI/image validation.
