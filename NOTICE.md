# Source provenance and third-party notices

Modification notice, 2026-10-28: this snapshot includes adaptations for iOS, NativeAOT, static dispatch and account-protection boundaries. It is a modified port of the pinned EHR source, not an upstream release.

This repository combines original compatibility/runtime/tooling code with selected and adapted Endless Host Roles C# source under GPL-3.0. The complete GPL text is in LICENSE. EHR's original authors and contributors retain their copyrights; source headers are preserved.

Upstream: https://github.com/Gurge44/EndlessHostRoles, v8.0.3, commit `ce23f0d050f617a59507e5bb0fbfff751d4b5134`.

`source-app/manifest.json` identifies every compiled C# input by relative path and SHA256. It represents development build 48 and is reused unchanged through native build 51. Compared with pinned upstream, the selected source contains original EHR files, adaptations for iOS/AOT/static dispatch and original generated/handwritten port support. Modified areas include static registration/dispatch, platform/input/audio/UI adaptation, explicit lifetime handling and account-protection exclusions. The source snapshot and adaptation tools make these changes reviewable; they do not claim to be an unmodified upstream EHR release.

Generated game API facades contain type/member declarations, enums and original gateway wrappers for interoperability. They do not contain decompiled game method implementations. Game binaries, decrypted launchers, raw metadata dumps and game assets are not included. Among Us and related marks belong to Innersloth; no affiliation or endorsement is claimed.

The resource catalog lists 224 exact upstream paths/logical names/hashes. Their bytes (images, audio, fonts and data) are deliberately not rehosted here. Acquire them from the pinned upstream checkout and review their applicable notices; provenance alone is not a blanket license grant for third-party assets.

Public package dependencies are pinned by `tools/build_source_application.py` and the snapshot manifest: BepInEx.Core, HarmonyX, JetBrains.Annotations and GitInfo. NuGet resolves their transitive dependencies, including MonoMod components. Their packages and licenses remain with their respective publishers; compiled dependency binaries are not distributed here. The use of BepInEx Core APIs does not embed its Unity plugin loader, and the iOS runtime path does not execute desktop JIT/dynamic patch generation.
