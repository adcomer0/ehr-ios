# Pinned EHR source generation

These original Roslyn tools generate explicit role constructors, bootstrap calls,
and direct HarmonyX callback bridges from EHR v8.0.3 at
`ce23f0d050f617a59507e5bb0fbfff751d4b5134`. They write fresh output directories;
the pinned upstream checkout stays unchanged. Generated EHR derivatives retain
the repository's GPL-3.0 license and upstream attribution.

`build_static_il2cpp.py --dotnet /path/to/dotnet --repo /path/to/EndlessHostRoles
--output /fresh/output` compiles the complete selected IL2CPP source against the
upstream managed reference packages and verifies constructor coverage using PE
metadata. It never loads the resulting EHR assembly. These reference-profile
builds establish source compatibility, not iOS NativeAOT or gameplay support.

`../check_source_dispatcher.py --dotnet /path/to/dotnet --output /fresh/output`
generates and executes arithmetic fixtures. They cover prefix ordering,
skip-original behavior, ref/out/state writeback, exception finalizers, nested
calls and disabling previously bound patches, without game assemblies.

The production dispatcher support lives in
`managed/SourcePort/StaticPatchRuntime.cs`. Native bindings must separately
validate exact runtime metadata, native addresses, ABI, ownership and exception
round trips. Coroutine factory addresses are never accepted as MoveNext bodies.
