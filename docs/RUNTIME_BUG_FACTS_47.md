# Sanitized runtime facts from physical build 47

The full EHR source startup completed, and the previous SetColor callback argument-width failure was absent. Hosting reached the lobby and mod settings. The tester reported lag while changing settings and a black screen after choosing Start Immediately. These observations do not establish complete multiplayer or role compatibility.

The production iterator registry hit its native 256-entry limit. Limit category 18 records contain count 256, usually 1 active source plus 255 terminal tombstones, with no deferred release backlog in those snapshots and gateway roots below its separate 65536 limit. Later source Step failures returned status 8. The final snapshot had already recovered to 82 entries/80 terminal after collection/sweeping; a final low count does not negate the earlier capacity events. The continuous options sender repeatedly yields fresh helper iterators and is a concrete source of carrier churn. No capacity or collector-policy change is included in this handoff.

The newly failing routes map exactly to:

| Native entry | Static source callback | What the evidence establishes |
| --- | --- | --- |
| InnerNet.InnerNetClient.SendAllStreamedObjects | InnerNetObjectSerializePatch.Prefix#59 | Starts the continuous options sender when host and no active sender handle; native capacity records identify this route context. 21 route failures were accumulated. |
| InnerNet.InnerNetClient.FixedUpdate | Modules.FixedUpdateCaller.Postfix#8 | Broad scheduler/lobby/HUD/rate-limiter/player update entry;21 route failures were accumulated. The route alone does not identify which nested source operation failed. |
| GameStartManager.Start | AllMapIconsPatch.GameStartManagerStart_Prefix#87; AllMapIconsPatch.Postfix_AllMapIcons#88; GameStartManagerPatch.GameStartManagerStartPatch.Postfix#131 | One failure returned status 6, flags 127: dispatcher and original participated and a retained native exception escaped. It does not identify the exception's original/callback origin. |

GetConnectionData still has a separate predispatch type-mismatch with phase 10, meaning the thunk saw a missing instance receiver. The unentered path falls back to the unchanged original. This does not prove a source handshake body failed and does not authorize weakening receiver validation or authentication.

Source review also identified a separate settings BuildCoroutines cleanup concern after iterator faults or stale-generation completion. No fix for it is included in this build-47 snapshot, and it is not proven to explain the observed carrier limit or black screen.

No account tokens, account identifiers, signing data, raw object pointers, private artifact paths or personal logs are included here. Authentication failures remain separate; no checks are bypassed.
