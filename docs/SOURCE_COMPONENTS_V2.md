> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

This stage extends the actual Candidate26 source-component bridge. It does not
run Main.Load automatically and does not claim a playable or complete EHR port.
The upstream source pin is v8.0.3, ce23f0d050f617a59507e5bb0fbfff751d4b5134.

Generate a fresh overlay with:

```
python3 tools/prepare_full_component_overlay.py \
  --source-root /path/to/ehr-ios \
  --output /fresh/output \
  --facade-source /path/to/current/GeneratedFacades.g.cs \
  --gui-source /path/to/rendered/ClientControlGUI.cs \
  --test-source /path/to/current/combined/NativeRuntimeTests.mm
```

The source-runtime transformation changes only the actual RuntimeObject lifetime
boundary. Other current FacadeRuntime helpers remain intact. The delegate change
qualifies generic UnityAction names to avoid source-alias collisions. Neither
tool overwrites canonical input. The facade transformer supports flattened and
natural-namespace generator outputs and preserves ordinary native generic paths.
Apply GUI scene ownership after the sibling's UIKit renderer transformation.

The native registry publishes metadata for the seven source classes and the own
probe. Source IDs are Coroutines=1, ErrorText=2, AbstractPagingBehaviour=3,
MeetingHudPagingBehaviour=4, ShapeShifterPagingBehaviour=5,
VitalsPagingBehaviour=6, ClientControlGUI=7; the own probe is 8. The three concrete
pagers have the actual native AbstractPaging parent; all added native instances
preserve the verified MonoBehaviour 32-byte layout, inherited reference bitmap
and descriptor, with no added native instance fields. The native methods are
Unity callback shims, not a complete CLR-to-native reflection mirror. Ordinary
source fields, private lifecycle accessors, and virtual paging calls remain CLR
source code. The borrowed UnityEngine.CoreModule image identity remains an
explicit implementation limit.

The default managed profile compiles original Coroutines and the own probe only.
Define EHR_ALL_SOURCE_COMPONENTS in the full-source project to compile all seven
source factories and accessors. The exported profile mask is 129 for default and
255 for full. Native metadata publication alone does not prove all seven source
classes have run. Source Get/Add/TryCast returns the original managed source
identity. A destroyed source proxy has native token zero and actual Unity bool
false while its existing CLR fields remain accessible. Ordinary disposed native
facades still throw. Do not clear source static Instance fields to simulate null.

Scene registration uses the exact native closed UnityAction carrier. Its source
state's NativeCallbackScope removes the same carrier before Close/Dispose, with
cleanup continued after errors. Native SceneManager methods are resolved at
runtime; no missing facade method declarations are fabricated. The new probe
asserts genuine source Add/Get identity, initialized fields, tombstones, scope
cleanup and collection. Actual Scene subscription requires the live full-source
startup test; this stage has only compiled it.

For BasePlugin.AddComponent owner zero the native bridge creates a genuine
GameObject("EndlessHostRoles-iOS") and invokes DontDestroyOnLoad. Failed persistence
is not reported as success. The optional --owner-probe verifies creation and
actual Unity destruction after explicit teardown. It permanently closes the
empty probe manager, must be the FINAL source-component test, and must never be
run before subsequent Main.Load or against a live plugin. Both async helpers
cancel on failure and timeout. Compile EHRSourcePluginOwnerProbe.mm and expose its
three existing C symbols when enabling that optional probe.

Startup order for the real source host:

1. Bind core gateway, reflection/value/lifetime/type helpers, original-call and
   patch tables; initialize native delegates, production iterators and UIKit.
2. Run the exact pinned class-layout/internal-entry gate and publish native types.
3. Bind the SourceComponent callback table. Bind generated codecs and register
   the all-seven managed profile. Refuse uncompiled source types.
4. Supply SourceComponentHostBridge.AddComponent and .RegisterComponent to the
   real SourceHostOptions, then invoke the once-only Main.Load host lifecycle.

Main.Load assigns Coroutines before ClientControlGUI. GUI.Awake can construct
CustomLogger, whose original code immediately uses Main.coroutines.StartCoroutine.
The production iterator bridge must therefore be ready before loading the GUI.
The component overlay itself never bypasses a failed startup dependency.

Validation completed here: default-profile ios-arm64 NativeAOT publish; native
arm64 iOS17 -Wall -Wextra -Werror for the four changed/new bridge objects; generated
combined XCTest compilation; 103 owned production-invoker/8-type registry checks;
weak gateway raw-Borrow rejection and strong Pin checks against current gateway;
13 checks of the extracted, unchanged production RuntimeObject class. The prior
Candidate26 actual runtime proof covers the original two-source-type bridge.
The v2 full replacement-source compile has only the independently assigned desktop
updater error remaining; all-seven component/Scene/UI/delegate code compiles.
No v2 runtime proof, all-seven lifecycle proof, full role behavior, native assembly
identity parity, complete class/Type/Method allocation-size proof, or device
gameplay claim is made by this package.
