> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Exact native thunk planning

`tools/generate_native_thunk_plans.py` joins the pinned Harmony selectors, exact source CLR type report, callback audit and one or more exact native binding-facts reports. It reads the original clear framework/metadata, verifies their SHA/UUID against every facts document, validates enum underlying metadata, and writes only a new outside-Git private JSON plan. It emits no executable thunk or runtime availability claim.

Pass both ordinary296 audit facts and the separate coroutine factory/body association facts. Coroutine selectors select only their actual `:MoveNext` body facts. Factory CLR receiver/result types are preserved as diagnostic input and never used for the body: source binding uses an owning `Il2CppSystem.Object` receiver and Boolean result, with state-machine owner-field support still required explicitly. Ordinary hidden context is a last declared `const void *` parameter whose bits are preserved, which may be null and is never dereferenced. Public method/native association and actual typed entry execution remain gates for every plan.

Primitive scalar widths and enum underlying types are explicit. References use borrowed-object-to-owned-root semantics. Ref/out parameters require exact public element class/attributes and bounded nonoverlapping copyback storage; Out does not read caller storage. Reference ref/out is rejected. Mixed, unproven, overlapping, large indirect/sret and value-receiver forms remain blocked until a separate proven adapter exists. No C++ struct is inferred from its type name.

Optional `--type-layouts` expects schema `ehr.native-abi-layout-facts.v1`, matching framework_sha256/metadata_sha256/framework_uuid, and `types` mapping canonical type names to observed public-API value facts. Each type has evidence_kind=observed_public_api, value_size, alignment, contains_references, blittable, and fields containing type/value_offset/is_static. These must come from actual public runtime metadata observations with a documented value-offset basis; the planner never fabricates them. HFA classification recursively flattens exact fields and accepts only contiguous one-to-four homogeneous float/double atoms with exact total size. Compiler sizeof/alignof/offsetof assertions, own ARM64 ABI fixtures and actual target execution remain required after planning.

CLI:

```sh
python3 tools/generate_native_thunk_plans.py \
  --selectors /private/selectors.json --source-types /private/source_target_types.json \
  --dispatcher-audit /private/static_dispatch_audit.json \
  --binding-facts /private/ordinary-binding-audit-facts.local.json \
  --binding-facts /private/coroutine-binding-audit-facts.local.json \
  --framework /owner/UnityFramework --metadata /owner/global-metadata.dat \
  --output /outside-git/native-thunk-abi-plans.local.json
```

The current private run describes all298 target bodies with no missing selector. Its six value-dependent selectors need Guid, Color, Discord.Activity and InnerNet.PlayerId facts; two state-machine wrappers need actual owner/state fields. There are no current value-type receivers and no current Harmony ___field injections. These are planning observations, not completed feature/runtime gates.

Binder review requirements remain separate from signature planning:

- Preserve existing built-in original IDs1/2 for their exact methods; the native registry rejects method aliases.
- `NativePatchRuntime.Configure` registers routes before every later codec/value check; preparation is not a fully atomic native registration transaction. Keep dispatch/hook activation gated until complete validation.
- Current `InstanceFields` is unpopulated. Any future ___field form must bind exact fields, track writes and flush before original plus after postfix/finalizer, including exception paths; otherwise reject it.
- Original ref writes must reach source finalizers and caller copyback even if original throws. Native outputs must be copied before raising the surviving native exception after the NativeAOT frame has returned.
- A managed failure cannot justify blindly retrying original; it may already have executed. Expose/observe an exact per-dispatch body-entered outcome or define a fail/raise policy that cannot double-run it.
- NativeGameException roots and owned result/ref roots need deterministic transfer/release. Original cleanup errors should not accidentally replace the original exception/ref state. Own fixtures currently exercise only scalar no-ref/no-native-exception patch routes; actual byref/native-exception paths still need proof.
- Current token-only dispatcher has no receiver output slot. A mutable value receiver, especially ref __instance replacement, requires a separate explicit copyback capability before enabling such targets.

Synthetic checks use `python3 -m unittest discover -s tests -p test_native_thunk_plans.py -v`; they cover exact scalar/enum widths, reference-ref rejection, missing layouts, recursive HFAs, overlap/large value rejection, actual coroutine owner/result override, Out input rules and field binding gates. They perform no game execution or device operation.
