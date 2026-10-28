# Known issues in development build 47

This snapshot is incomplete. A physical test reached Online lobby hosting and mod settings, encountered lag, then a black screen after Start → Start Immediately. Full rounds, victory/meeting transitions, every role and vanilla-peer combinations remain unverified.

## Confirmed native coroutine capacity pressure

The bounded numeric diagnostic recorded category 18 at count/limit 256, usually with one active source and 255 terminal carrier tombstones. Deferred release backlog was zero in those records and gateway roots were below their separate 65,536 limit. New coroutine registrations failed; repeated sender/scheduler failures followed. Later collection/sweeping reduced the count, so the final snapshot alone hides the earlier exhaustion.

The options sender creates short-lived helper iterators continuously. The bridge keeps completed carrier identities as weak tombstones until collection. Their capacity/lifecycle design needs correction; simply treating every status 8 as the same limit or raising every bound is not a diagnosis. This capacity pressure is confirmed; it does not explain every possible black-screen path.

## Game-start native exception

`GameStartManager.Start` recorded one dispatched failure with retained native exception and original participation. That route has map-icon callbacks and a start callback. The evidence does not yet identify which original/nested operation produced the exception. See [sanitized route facts](RUNTIME_BUG_FACTS_47.md).

## Apple/EOS authentication

Apple authorization callbacks can complete, but the original EOS platform login returned 7000 (`EOS_Connect_ExternalTokenValidationFailed`). This proves token validation failed, not a particular audience/expiry/provider cause. The original game then automatically retries platform sign-in, producing repeated Apple sheets. Successful account authentication and progression safety are unverified.

No token contents were read, no success was fabricated and no online/account permission checks were removed. A separate default-disabled retry-failure UX experiment is staged privately and is **not part of this snapshot**. It would not make the backend accept a token. Use disposable test identities; valuable accounts remain outside testing.

## Other boundaries

`GetConnectionData` has a predispatch missing-receiver observation. Its unentered path calls the unchanged original once; this is not evidence that a source handshake body failed. Source review also identified settings-build cleanup after coroutine faults as an independent concern; a later experimental fix is not included here.

Most detailed documents are implementation-stage notes, including earlier milestones and fixture commands. This file, README, ARCHITECTURE and BUILDING describe the public snapshot's current scope. Native maps are build-specific, and portability to a new game version requires a fresh ABI/image validation.
