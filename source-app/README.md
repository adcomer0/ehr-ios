# Selected iOS source

Modified iOS/AOT source snapshot, 2026-10-31. See [provenance and modification notice](../NOTICE.md).

`compiled/<index>/<filename>.cs` contains the 796 exact C# files selected for the current development build. The numeric index disambiguates names and preserves compile ordering. `manifest.json` pins their bytes and the public NuGet package versions; it contains no absolute machine paths. The build-52 system-chat and delayed-name guards remain selected. See [known issues](../docs/KNOWN_ISSUES.md) for current physical validation and limits.

The optional EHR website directory is off by default. Its native gate must separately allow the current signed-in, ownership-verified session before any listing or `/confirmauth` request. Only the fixed EHR listing endpoint receives the game's original EOS bearer; the itch.io credential is never passed into this C# assembly. Room-management tokens stay in RAM and are bound to the creating lobby generation. A gated main-thread recovery tick resumes a missing listing after sign-in renewal, preserving request backoff and coalescing duplicate ticks. The transport rejects redirects and cookies, limits responses to 8 KiB and requests to ten seconds, and does not log credentials, codes or response bodies. Local owned fixtures exercise the selected directory body with fake game objects and a fake HTTP handler; they do not establish live service acceptance.

`tools/source_port/prepare_lobby_directory.py` derives six selected files from the exact protected snapshot. Build 60 adds log-only slash-command redaction to the five generic chat/RPC log sites, covering verification codes without changing command arguments or network payloads. The transform preserves the six protected callback exclusions, the protected `/level` command, and unrelated lifecycle/callback behavior. The older account-protection adapter remains available for its original profile. See [directory support](../docs/IOS_LOBBY_DIRECTORY.md) for contracts and validation.

Build 64 removes the join prefix's clipboard-code log through
`tools/source_port/prepare_join_privacy.py` and adds the separate numeric
coroutine-failure export to selected source 778. Its reusable implementation
remains in `managed/ProductionCoroutines.cs`; the host/callback tables stay
72/32 bytes. See [the diagnostic ABI](../docs/IOS_COROUTINE_FAILURE.md).

The 224 resources are catalogued by pinned upstream path, logical name and SHA256. Resource bytes are not included. `tools/materialize_source_snapshot.py` verifies the upstream Git revision, contained tracked resource paths and every source/resource hash, then writes a local absolute-path manifest outside Git. That manifest is accepted by the existing NativeAOT builder.

The snapshot is the compiled selection authority for review/rebuild. Reusable generators and port runtime sources also appear in tools/, managed/ and native/. Editing those copies alone does not change a file selected from this snapshot; deliberately regenerate or update the selection and its hashes.

This is source for an incomplete research build, not proof of working gameplay. See [building](../docs/BUILDING.md) and [known issues](../docs/KNOWN_ISSUES.md).
