# EHR iOS — native integration research

An experimental, all-local iOS port of [Endless Host Roles](https://github.com/Gurge44/EndlessHostRoles), intended to let an iPhone host EHR games for vanilla Among Us players. **This is a research prototype. One match with a vanilla peer is now user-reported working; authentication and other runtime failures remain unresolved. It is not a finished release.**

## How it works

EHR's C# source is compiled ahead of time with **.NET NativeAOT** into an ARM64 native library. An **Objective-C++ bridge** connects it to the existing game's Unity IL2CPP runtime through validated runtime APIs and build-pinned native adapters. Generated static registries and typed prefix/postfix dispatch replace desktop runtime patch discovery. Exact, build-specific ARM64 entry hooks are applied to a local framework copy before signing.

There is no BepInEx Unity/IL2CPP plugin loader running on the phone and no embedded .NET JIT. Some BepInEx Core configuration/logging APIs and Harmony-compatible source descriptors remain as compile-time/AOT dependencies. This is not a Windows DLL copied into an iOS app. See [the architecture](docs/ARCHITECTURE.md) for the ABI, ownership, coroutine, hook and loader details.

## Current state: build-52 message guards, physical game start reached

- The full selected EHR source compiles for `ios-arm64`: 796 C# inputs; the 224 resource names/hashes are catalogued separately.
- Signed startup on an Apple Silicon Mac loads EHR once, initializes 5,049 options and activates 292 permitted bindings from 298 metadata targets. Six account/consent-related patches are deliberately excluded.
- A physical iPhone can open an Online lobby, configure settings and reach a game in build 49. The user confirmed that test was solo; its early win is consistent with EHR's low-player end conditions. The trace reached intro, ship initialization, game start and game end.
- In build 50, a vanilla peer joined and the modded host disconnected; the remaining vanilla client became host. Build 51 recorded server reason 10 (`Hacking`), without identifying its exact rule. Build 52 adds the omitted native chat-mode gate before optional system-message sends and revalidates a delayed name restore. Following that delivery, the user reports playing a match with a vanilla peer. This supports one multiplayer path; it does not certify stability or all roles. See [the guards and evidence](docs/MULTIPLAYER_SEND_GUARDS.md).
- Build 48's phone diagnostic showed immediate retirement of completed coroutine slots, two active entries and no recorded callback failures during the black screen. The earlier 256-entry exhaustion did not recur in that reproduction.
- The pinned native game inlines host-start iterator construction, bypassing EHR's patched host factory. Build 49 adapts the exact native yield through the existing EHR factory and callbacks. The phone recorded one replacement and one host-factory call, with no adapter or source callback failures.
- Apple authorization is followed by EOS result 7000. The explicitly enabled development retry guard stopped the repeated sheets during the phone test, but successful backend authentication remains unresolved.
- Build 51's bounded numeric history confirms the correct Apple credential type before EOS 7000, followed by a separate guest fallback. It preserves the original calls and collects no token contents or account IDs. Successful sign-in remains unresolved in build 52. See [authentication diagnostics](docs/AUTH_HANDOFF_DIAGNOSTICS.md).
- UIKit touch controls, mobile input, audio, static source components and bounded numeric diagnostics are implemented. Compiled role source is not evidence that every role works in play.
- The startup status control is a compact `EHR` badge at the top center, leaving the game's upper-right settings area clear. Tap it for status and exports, or drag it to another position. Its position stays within the safe area when the screen rotates.

Read [known failures and evidence](docs/KNOWN_ISSUES.md). No protection against bans or account/progression loss is established. Use a disposable test identity; keep valuable accounts outside testing.

Build 49 passed signed iOS-on-Mac startup, its owned native game-start adapter probe and the real-runtime 1,024-retained-carrier check, plus touch/audio/cleanup probes. The separate phone observation confirms one real-owner host-start path. See [the validation scope](docs/BUILD49_VALIDATION.md); complete rounds, peers and all roles still need testing.

Build 52 passed fresh NativeAOT compilation, signed Mac runtime checks and 297
owned regression tests. Its extracted chat-mode guard passed 4,032 owned cases;
the isolated authentication-recorder probe passed 87 checks without sign-in.
See [build-52 validation](docs/BUILD52_VALIDATION.md) and the earlier
[build-51 observations](docs/BUILD51_VALIDATION.md). Upgrades from 49 to 50,
50 to 51 and 51 to 52 were verified over Wi-Fi on the test iPhone.

## Repository contents

| Path | Purpose |
|---|---|
| `source-app/` | Selected build-52 C# source snapshot and portable input manifest |
| `managed/` | Port runtime, facades, static dispatch and source adaptation support |
| `native/` | Original launcher, IL2CPP gateway, typed hooks, ownership and UIKit adapters |
| `tools/` | Source preparation, metadata mapping, native generation, signing and validation tools |
| `tests/` | Owned fixtures, metadata audits and signed-runtime XCTest harness |
| `app/` | Earlier standalone SwiftUI/Bait simulation lab; not the full game port |

The snapshot includes adapted GPL EHR source and original port code, preserving source headers. [Provenance and dependencies](NOTICE.md) distinguish these from generated game API declarations.

**No Among Us binaries/assets, IPA, provisioning profiles, signing keys, device identifiers, credentials or raw device/account logs are distributed here.** EHR resource assets are also omitted; obtain the exact pinned upstream checkout locally. The repository contains a fresh reviewed source snapshot, not private development history.

## Build and review

Start with [BUILDING.md](docs/BUILDING.md). The managed snapshot can be materialized against the pinned upstream resources and compiled with .NET 10 NativeAOT. Building a signed game also requires a legitimate local game installation, Xcode, your own Apple developer provisioning, and locally generated native maps. A complete one-command signed-game rebuild is not yet provided.

Baseline: EHR v8.0.3, commit `ce23f0d050f617a59507e5bb0fbfff751d4b5134`; inspected game bundle `2026.9.29 (3)`, Unity `2022.3.62f3`, metadata 31. Runtime mappings are specific to that framework fingerprint. Re-map and validate other versions; do not reuse RVAs blindly.

Contributions from EHR and Among Us mod developers are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). This project is independent of and not endorsed by EHR, Among Us or Innersloth.

## License

GPL-3.0; see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). Game content is not licensed or supplied by this project. External resource/dependency terms remain their respective owners' terms.
