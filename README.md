# EHR iOS — native integration research

An experimental, all-local iOS port of [Endless Host Roles](https://github.com/Gurge44/EndlessHostRoles), intended to let an iPhone host EHR games for vanilla Among Us players. **This is a research prototype. Authentication fails, menus can lag, and starting a game can produce a black screen. It is not a finished playable release.**

## How it works

EHR's C# source is compiled ahead of time with **.NET NativeAOT** into an ARM64 native library. An **Objective-C++ bridge** connects it to the existing game's Unity IL2CPP runtime through validated runtime APIs and build-pinned native adapters. Generated static registries and typed prefix/postfix dispatch replace desktop runtime patch discovery. Exact, build-specific ARM64 entry hooks are applied to a local framework copy before signing.

There is no BepInEx Unity/IL2CPP plugin loader running on the phone and no embedded .NET JIT. Some BepInEx Core configuration/logging APIs and Harmony-compatible source descriptors remain as compile-time/AOT dependencies. This is not a Windows DLL copied into an iOS app. See [the architecture](docs/ARCHITECTURE.md) for the ABI, ownership, coroutine, hook and loader details.

## Current state: development build 47

- The full selected EHR source compiles for `ios-arm64`: 796 C# inputs; the 224 resource names/hashes are catalogued separately.
- Signed startup on an Apple Silicon Mac loads EHR once, initializes 5,049 options and activates 292 permitted bindings from 298 metadata targets. Six account/consent-related patches are deliberately excluded.
- A physical iPhone can open an Online lobby and configure settings. Starting a game remains unreliable; end-to-end gameplay and vanilla-peer compatibility have not been validated.
- The device diagnostic caught the native coroutine registry reaching its 256-entry limit with 255 terminal entries retained. Apple authorization is separately followed by EOS result 7000; successful account sign-in is unverified.
- UIKit touch controls, mobile input, audio, static source components and bounded numeric diagnostics are implemented. Compiled role source is not evidence that every role works in play.

Read [known failures and evidence](docs/KNOWN_ISSUES.md). No protection against bans or account/progression loss is established. Use a disposable test identity; keep valuable accounts outside testing.

## Repository contents

| Path | Purpose |
|---|---|
| `source-app/` | Actual build-47 C# source snapshot and portable input manifest |
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
