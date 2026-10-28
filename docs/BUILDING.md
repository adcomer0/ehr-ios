# Building and validating the research snapshot

The managed source snapshot is portable. Native game assembly still requires local, build-specific generation and your own signing inputs; this repository does not yet provide a one-command rebuild of the final signed game. Build outputs and local manifests belong outside Git.

## Requirements

Use an Apple Silicon Mac with Xcode/iPhoneOS SDK, Python 3.11+, and a .NET 10 SDK capable of `ios-arm64` NativeAOT publication. The tested development environment used Xcode 27.1 and .NET SDK 10.0.403. Install the SDK/toolchain locally; it is not vendored here. Public NuGet package versions are pinned in the source manifest and builder.

Native work also requires a legitimate locally installed game matching the documented framework fingerprint. No game inputs are downloaded by this repository. An iPhone simulator cannot execute the original device-only UnityFramework. The signed runtime harness uses iOS-on-Mac and can separately target a provisioned physical device.

## Materialize and compile the selected EHR source

Obtain upstream source separately:

```sh
git clone https://github.com/Gurge44/EndlessHostRoles.git ../EndlessHostRoles
git -C ../EndlessHostRoles checkout ce23f0d050f617a59507e5bb0fbfff751d4b5134
```

From this repository, choose an output location outside all Git checkouts and set your SDK executable:

```sh
export EHR_DOTNET="$(command -v dotnet)"
export EHR_OUTPUT="$HOME/ehr-build-local"

python3 tools/materialize_source_snapshot.py \
  --upstream-root ../EndlessHostRoles \
  --output "$EHR_OUTPUT/source-inputs.json"

python3 tools/build_source_application.py build \
  --manifest "$EHR_OUTPUT/source-inputs.json" \
  --output "$EHR_OUTPUT/Managed47" \
  --dotnet "$EHR_DOTNET" \
  --native-binder native/EHRFullSourceRuntime.mm \
  --omit-debug-symbols
```

Use fresh output paths. The materializer checks the exact upstream commit, tracked contained resource paths and every C# and resource hash. It does not copy resource assets into this repository or access a game/account. `build-proof.json` records the resulting library hash and required exports; a successful source build does not establish gameplay correctness. To review only the emitted project, add `--emit-only` to the builder.

`source-app/manifest.json` selects the actual 796 C# inputs for build 47. The separate reusable `managed/` tree and source-transform tools are not automatically substituted for those files. Intentional edits require updating the selection/hashes and revalidating the generated dispatcher/native contracts.

## Native generation and signing

The native pipeline is implemented in these tools:

1. `inspect_ios.py` / `map_native_methods.py`: inspect a caller-provided game and metadata/native associations.
2. `map_harmony_native_targets.py`, `source_port/generate_native_patch_catalog.py`, `generate_native_thunk_plans.py`, `generate_native_typed_thunks.py`: generate exact target, ABI and typed-hook inputs. Source/static-registry generators live under `tools/source_port/` and `tools/facades/`.
3. `patch_native_entries.py`: validate and relocate supported ARM64 entry instructions in a fresh local framework copy before signing.
4. `build_game_probe.py`: assemble the original launcher, native helpers and NativeAOT module with the local game content; sign and verify the candidate.
5. `tests/runtime/run_native_runtime_test.py`: test a separate signed candidate copy; verify that the source candidate's four binaries stayed unchanged.
6. `install_protected_iphone.py`: upgrade only the explicitly selected test app after matching the passed Mac proof and exact-device/profile checks.

Run each tool with `--help` for its actual input schema. Intermediate native maps, component-class association reports and generated thunk inputs are produced locally from the selected game and source inventory. They are not bundled as private reports or raw game metadata. Automating their entire regeneration from the public snapshot remains contribution work.

Signing tools require explicit `--team-id` and `--bundle-id` values. `--team-name` can add an exact organization assertion. Use a separate test app identity and your own provisioning; the official game's bundle identity is rejected. No certificate/profile/device values are supplied. See [portable tooling](PORTABLE_TOOLING.md) for parameter flow. Do not uninstall the official game, import its container, reset account data or bypass consent/authentication to work around failures.

## Checks and evidence

Owned native fixtures and a portable test subset can run without game inputs. The full development suite includes tests that need prior source-pipeline fixtures, generated native headers or a configured .NET SDK. `bash tools/run_checks.sh` invokes the broad suite and will expose those missing dependencies; it is not advertised as a clean-clone all-green command.

The development build had 237 Python-suite tests pass with explicitly supplied local pipeline fixtures, 1,620 extracted color-wrapper checks and a compiled argument audit covering 334 callbacks/168 reads with no remaining mismatches. Signed Mac runtime startup also passed, separately from the physical failures. Those historical results do not certify a newly modified public build or every EHR role.

See [known issues](KNOWN_ISSUES.md) and [architecture](ARCHITECTURE.md). Never upload raw device/account diagnostics when reporting a result.


A reviewed game-free smoke subset is:

```sh
python3 -m unittest discover -s tests -p test_set_color_argument.py -q
python3 -m unittest discover -s tests -p test_source_application_tools.py -q
python3 -m unittest discover -s tools/facades -p test_generate_facades.py -q
python3 -m unittest discover -s tools/source_port -p test_native_patch_catalog.py -q

dotnet run --project tests/FailureGateFixture.csproj -c Release \
  --artifacts-path "$EHR_OUTPUT/FailureGateChecks"
```

The four Python commands cover 84 tests; the .NET fixture covers 212 checks. They use owned fixtures and do not sign, launch, install or operate a game/account. Additional portable signing/installer tests use synthetic identities; real signing/runtime validation remains separate.
