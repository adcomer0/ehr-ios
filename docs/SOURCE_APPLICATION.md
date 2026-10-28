> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

This original production startup layer joins the pinned EHR v8.0.3 source with
the actual native facade/component/coroutine/delegate/UI adapters. It is separate
from the earlier self-test binder and must be loaded as the single full EHR
NativeAOT image in a fresh process. No fixture Configure/Reset/CloseAll runs as
part of production startup. No base-game assembly reference, runtime JIT, dynamic
class injector or runtime executable write is needed by this startup layer.

The native EHRSourceApplication.h contract is fixed: host16, config56, status64.
Bind follows real native facade/host binding. Prepare requires Core, Delegates,
Components, Touch and passive Target validation (47); it configures the real
BepInEx.Core config/log host and immutable own-sandbox data/module paths, applies
the optional HTTPS signed-update instructions policy once, and prepares all
passive native targets. It does not instantiate roles or run Main.Load. The
optional update instructions are not a remote signature check; installing an iOS
update still requires a rebuilt/resigned app. Do not separately configure the
signed-update singleton before Prepare.

Load also requires production coroutines (63), complete passive target validation
and full source-component profile255. It runs the real source Main.Load exactly
once through SourcePluginHost, performs source Finished subscribers through that
host, binds requested callbacks, then enables permitted native targets last.
Arbitrary unavailable targets fail closed. Explicit platform/account policy
exclusions must be represented by the separately supplied static registration
policy, not by pretending missing native APIs work. A failure is terminal and its
contained error can be copied with copy_error_v1. Active repeated Load returns0
without repeating source effects.

Status source/role/callback fields are declaration counts, never readiness. The
last three uint32 slots observe the actual original Options.IsLoaded assignment,
OptionItem count and completed PostLoadTasks separately. Reading status does not
initialize Options. The options overlay removes only desktop steam_appid.txt
creation; existing source DataPath already points to NativeSourceHost's own data
root. No process chdir, official save import, account reset/link or copied account
data is involved. Generic Enum APIs are statically closed for NativeAOT with the
original ordering and names.

Start before the original TranslationController.Initialize/SplashManager.Start/
VersionShower.Start at the parent's verified pinned entry, with native once and
reentrancy guards. The TranslationController.Initialize postfix starts the
actual settings/roles initialization; a delayed MainMenu.Start entry misses it.
No original method should be replayed. Main.Load creates Coroutines before GUI,
and no required pre-existing MainMenu/Hud object was found in the source load
path. This ordering is source analysis; full native startup must still be tested.

Reproduction:

1. Produce the pinned complete source project with all-seven component, real
   facade, native target catalog and source-generated JSON packages. Preserve the
   explicit source precedence from their reports.
2. Run tools/prepare_source_application.py --project JSON_READY.csproj --output
   FRESH --canonical-root PROJECT --host-only-adapter ADAPTER.py
   --host-only-adapter-sha256 HASH. This pins the parent's host-only registration
   adaptation, selects current production component profile/signature exports,
   adds the four startup overlays, and preserves the selected source command
   bodies. Own account policy source may then be explicitly added to this project.
3. Run tools/build_source_application.py capture --project FRESH/EHR.csproj
   --upstream-root PINNED_UPSTREAM --output OUT/source-inputs.json. The manifest
   is a local artifact with explicit paths/hashes, not a source-Git file.
4. Run the same tool build --manifest OUT/source-inputs.json --output OUT/build
   --dotnet ISOLATED_DOTNET --runtime ios-arm64. Set the caller's isolated
   DOTNET_CLI_HOME/NUGET_PACKAGES. The tool emits the NativeAOT project, checks all
   source/resource hashes again after build, and verifies required native exports.

The builder permits only exact public Core/HarmonyX/Annotations/GitInfo package
pins and rejects game Reference/ProjectReference items, compiler-only unsupported
hosts, untracked resources and duplicate names. It embeds the224 pinned resources
under exact dotted EHR.Resources.* names. GitInfo reads the pinned upstream root,
so Commit/Sha/Tag reflect source ce23f0d.../v8.0.3 rather than the staging folder.
This source identity is distinct from the verified installed iOS framework pin.

Fifteen own-tool regression tests pass. A metadata-only resource/reference audit
verifies exact224 embedded names and no game DLL references without loading or
executing EHR. The full joined781-source ios-arm64 NativeAOT publish succeeded;
dependency/optional desktop Harmony trim/AOT warnings remain. Source JSON warnings
are fixed by the sibling's14-root source-generation package. Full Main startup,
settings completion, native source patch activation, valid lobby behavior and
vanilla join compatibility require actual app/device evidence. Compilation,
export presence and declaration counts do not prove those outcomes.
