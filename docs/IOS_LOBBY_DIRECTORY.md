# Optional EHR website directory

The selected C# snapshot supports the original EHR website listing and `/confirmauth` contracts through an opt-in adapter. “List this lobby on the EHR website” defaults off. A separately compiled native gate must also permit the current ownership-verified, genuinely completed sign-in session. This feature does not grant an account permission or manufacture a verification result.

The managed image exports `int32_t ehr_source_directory_bind_v1(int32_t (*allowed)(void))`. Binding is main-thread only, accepts one non-null callback, is idempotent for the identical callback, and never evaluates permission or performs HTTP during binding. An unbound callback, a non-main caller or any callback result other than `1` denies external requests. The native full-source runtime binds this export only for the optional directory build profile. Passive startup performs no directory requests.

The native game overlay may call `int32_t ehr_source_directory_tick_v1(void)` on its one-second main-thread refresh, only while the directory is bound and currently permitted. The tick returns `2` off-main, and otherwise performs a gated no-op or starts a missing listing worker. It does not restart an active worker, clear retry backoff, or bypass the opt-in/current-lobby checks. This lets listing recover after silent sign-in renewal temporarily withdraws permission. It is not polled by the passive startup probe.

Only an online host on a vanilla region can list a real current lobby. Main-thread coroutines snapshot lobby/player scalar identities and check the native gate, option, host and generation while polling asynchronous work. The HTTP task receives only immutable JSON bytes/strings and cancellation. It never calls a game facade or the native gate from a worker. A changed room, region, host, local identity or permission invalidates its response; it cannot publish a token into a later lobby.

The request contracts remain:

| Operation | Fixed HTTPS endpoint | Authentication and data |
| --- | --- | --- |
| Create listing | `app.gurge44.eu/lobby_created` | Original EOS bearer; room, region, language, EHR version, game ID, host, map, mode, maximum players |
| Update/close | `app.gurge44.eu/update_status` | RAM-only room-management token; room status and player/map/mode counts; no EOS bearer |
| Explicit `/confirmauth CODE` | `app.gurge44.eu/api/verify_ingame` | Bounded code and the requesting player's current friend code, PUID and game ID; no bearer |

All JSON string values are escaped. Redirects, cookies and automatic decompression are disabled. Requests have a ten-second cancellation deadline, a 16 KiB request limit and an 8 KiB streamed response limit, including unknown-length responses. The adapter does not log bodies, credentials or verification codes. Build 60 also redacts slash-command text at all five existing generic chat/RPC log sites, closing the build-59 path that could otherwise log `/confirmauth` codes. This pure log-only operation recognizes a leading slash after whitespace, covering all translated command aliases and case variants without requiring translation initialization. Ordinary chat, actual command text/arguments and network payloads remain unchanged. Create failures back off for thirty seconds; requests share a five-second minimum spacing and updates use the configured ten-to-thirty-second interval. Only a successful, bounded create response can supply the room-management token. Closing uses the former room's token and cannot update current local state. Gate loss cancels outstanding work; a server that already accepted a create before cancellation may retain its entry until its own expiry because the client may never receive a token with which to close it.

The port preserves the six account-protected callback exclusions, the protected `/level` behavior, and the existing multiplayer-send guard. This support sends legitimate requests to EHR's service; live registration, server policy and verification acceptance still require a human test.

Reproducible checks use owned game/HTTP sentinels, not game binaries or external services:

```sh
EHR_DOTNET=/path/to/dotnet python3 -m unittest discover -s tests -p 'test_lobby_directory.py' -v
```

To regenerate from a separate copy of the reviewed protected snapshot, use a fresh output outside Git:

```sh
python3 tools/source_port/prepare_lobby_directory.py \
  --source-root /path/to/protected-source-app \
  --output /path/to/fresh-directory-overlay
```

The tool rejects changed protected pins or repeated application. It writes only the six selected source files, an updated manifest, and an overlay report. It leaves the 796-source count and 224-resource catalog unchanged. The selected source snapshot already contains the adapter; do not apply it a second time. Fixtures compile the actual five selected log statements and original pure command recognizer against an owned capture logger; they verify multilingual/case/whitespace redaction, unchanged ordinary chat, and the unchanged verification HTTP body.
