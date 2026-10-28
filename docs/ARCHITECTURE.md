# EHR iOS source port

This is an experimental local port of [EHR v8.0.3](https://github.com/Gurge44/EndlessHostRoles/tree/ce23f0d050f617a59507e5bb0fbfff751d4b5134). The EHR C# source is compiled ahead of time for iOS arm64. Objective-C++ connects that code to the actual game's IL2CPP runtime. There is no BepInEx runtime loader, runtime Harmony detouring, JIT, or remote host server.

The full source compiles and starts in a signed game candidate. It is **not a finished playable port**: physical-device testing has reached lobby hosting and mod settings, but settings lag and a black screen when starting a game remain. Source compilation, binding validation, startup, and multiplayer behavior are separate milestones.

## Execution path

```text
Actual game IL2CPP method
  -> typed ARM64 entry thunk installed before signing
  -> native validation and rooted call frame
  -> NativeAOT static EHR prefix/postfix/finalizer dispatcher
  -> generated C# live facades -> Objective-C++ IL2CPP gateway
  -> actual game objects and methods
```

The entry mapper resolves full image/type/method signatures against the selected game's metadata and native code. It does not reuse Windows addresses. Build inputs, framework hash/UUID, entry instructions, runtime method association and argument layouts are pinned and checked. Unsupported signatures fail explicitly. The tested game uses Unity 2022.3.62f3 and metadata 31; these facts do not establish compatibility with another game build.

The real BepInEx.Core configuration and logging classes are reused; an explicit source-compatible host supplies the plugin lifecycle. Generated static registries replace role/type discovery and runtime patch generation. Roslyn resolves Harmony target attributes and callback signatures; generated wrappers carry prefix skip-original behavior, ref/out/result/state values, ordering, Prepare decisions and finalizers into the static dispatcher. The current catalog contains 298 native target candidates and 334 source callbacks; these counts describe mapped code, not tested role behavior. Six account/privacy/progress-changing callbacks are deliberately excluded by the source policy.

An original call goes through caught IL2CPP runtime invocation under a one-shot permit for the exact registered target/method. Its entry thunk consumes that permit and calls the preserved original trampoline. This prevents the original call from redispatching its own patches while allowing genuine nested calls. Native exceptions remain rooted, return through NativeAOT as wrappers/status, and are raised in native code after managed frames have returned. The original-participation proof prevents retrying an original that already ran after a later failure.

## Objects, components and coroutines

The generated facades resemble the game's C# surface but hold opaque owned tokens, not native object pointers. The gateway validates types, signatures, value layouts and reference writes. Strong roots, weak associations and deferred release bridge the separate .NET NativeAOT and IL2CPP collectors. A source-visible native exception may own an independent root.

Seven EHR component types use statically generated factories and lifecycle dispatch. Native MonoBehaviour shells are registered through a small, build-pinned IL2CPP class adapter with verified metadata layouts and pre-sign internal entry hooks. Source instances bind to their native shells through weak self associations. Real Unity lifecycle callbacks invoke the source; destruction closes callback scopes and source state. This does not make arbitrary runtime class injection available.

CLR IEnumerator instances use registered native enumerator carriers. Only registered identities route to source callbacks; ordinary game enumerators pass through. Unity performs the actual scheduling, nested iterator and native yield handling. Delegates similarly use compiled callback bridges and explicit owner scopes. Closing a coroutine retires source state once, while weak terminal identity tombstones remain until native collection. Physical testing has exposed exhaustion of the 256-entry carrier registry with mostly terminal entries; this remains a known defect rather than grounds for claiming long-session stability.

The desktop client-control presentation has a UIKit touch backend; its source action bodies and host/phase guards are retained. The main game and settings UI still use actual game objects. Other narrow iOS adaptations cover input, storage, signed-update handoff, audio and AOT JSON contracts. They are pinned source transforms, not a replacement game simulation.

## Build and verification

The toolchain uses an Apple Silicon Mac, Xcode/iPhoneOS SDK, .NET 10 NativeAOT for ios-arm64, Python source/metadata tools, and Roslyn generators. `tools/prepare_source_application.py` prepares the source project; `tools/freeze_source_inputs.py` captures exact selected sources and resource logical names; `tools/build_source_application.py` produces the NativeAOT module. Facade and static-registry generation are under `tools/facades` and `tools/source_port`. `tools/build_game_probe.py` assembles and signs the local candidate using the native mapper and pre-sign entry patcher.

Own-source fixtures test ABI/ownership/dispatch independently. App-hosted XCTest verifies actual runtime objects, original invocation, components, delegates, coroutines and source startup. Numeric diagnostics distinguish predispatch rejection, source failure, original participation and capacity limits; they intentionally omit account payloads and raw object pointers. Passing these tests does not establish every EHR role, game mode, game transition or vanilla-client combination.

The repository contains original integration code, source adaptation tools, the selected EHR C# snapshot, and generated API declarations/wrappers. The separately obtained official game binaries/assets, raw game DLL/metadata dumps and private native hook reports, signing identities/profiles, device identifiers and private diagnostics are not publication inputs. The installed source game remains untouched; the local candidate uses its own launcher and signed copy. Authentication and official account/progress checks are not bypassed. EHR-derived work follows the upstream GPL-3.0 license; third-party notices remain applicable.
