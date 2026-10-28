> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

This delta fixes three stale selected shared runtime implementations discovered
by the first full-image passive bind. The alignment audit compared41 selected
own files with canonical sources. ActionRuntime lacked the previously tested
families export and delegate identity reuse; TypedActionRuntime lacked delegate
identity reuse; NativeEngineColors lacked the previously tested documented
compatibility parser route. align_shared_runtime.py selects the canonical own
implementations and HtmlColorCompatibility, preserving the generated full-source
namespace surface/aliases. Its report lists every selected/canonical hash.

SourceUnityAction.cs supplies the corresponding genuine zero-argument
UnityEngine.Events.UnityAction constructor, implicit CLR Action conversion,
Invoke, explicit Close and native UnityEvent.RemoveListener. It uses the same
already proved Action-family native table; no new native ABI was invented. The
canonical UnityActionRuntime.cs targets flattened generated names and cannot be
copied directly into this source-namespace surface. The prior complete source
compiled but its unchanged UnityActionDelegateFix.AddListener(Action) body called
itself. A metadata-only IL audit proves that self-call in Release32 and its
absence in the corrected RoleInfo33 build. Native callback lifecycle still
requires explicit unsubscribe/Close where source owners retain callbacks;
disposing a proxy alone does not cancel native listeners.

The new source_unity_action_self_test export creates a separate genuine native
UnityEvent, tests the unchanged source extension, temporary-proxy release,
equal-delegate removal, invocation, Close/no-op and source-registry cleanup. It
does not touch a scene button, source Main, accounts or the network. Native actual
runtime proof remains the parent's next passive test. The header documents the
10-word proof contract.

build_source_application.py now verifies all23 exact exports used by the native
production binder plus application error/signature/DispatchV2/JSON/coroutine
exports. The separate generated native-export-audit.json reads current binder
source and verifies all29 required exports including SourceUnityAction's test.
ArtifactAudit verifies exact224 resources, no game references and the corrected
source extension binding without loading EHR.

The corrected RoleInfo33 project also includes the sibling's exact six mobile
source adaptations, protected account spans/six callback exclusions, source JSON
contexts and host-only MCI policy. It compiles all786 source files and publishes
ios-arm64 NativeAOT. The build and export checks passed, but Main.Load, options
completion and gameplay were not executed by these tools.

Reproduction pointer: RoleInfo33/source-inputs.json is the explicit selected
compile/resource manifest with hashes. Canonical tools/build_source_application.py
verifies and builds it. tools/freeze_source_inputs.py copies only verified source
and resource bytes to a durable outside-Git artifact and rewrites the manifest so
later staging changes cannot invalidate source selection. This source snapshot
does not claim bit-identical native output or execute the plugin. Regeneration
from raw metadata follows the canonical tool chain described in PIPELINE33.md.
