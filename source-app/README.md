# Selected build-52 source

Modified iOS/AOT source snapshot, 2026-10-28. See [provenance and modification notice](../NOTICE.md).

`compiled/<index>/<filename>.cs` contains the 796 exact C# files selected for development build 52. Two files differ from the build-48 selection reused through native build 51: `Utils.cs` and `PlayerJoinAndLeftPatch.cs`. The numeric index disambiguates names and preserves compile ordering. `manifest.json` pins their bytes and the public NuGet package versions; it contains no absolute machine paths. See [the current validation](../docs/BUILD52_VALIDATION.md) for the physical baseline and remaining limits.

The 224 resources are catalogued by pinned upstream path, logical name and SHA256. Resource bytes are not included. `tools/materialize_source_snapshot.py` verifies the upstream Git revision, contained tracked resource paths and every source/resource hash, then writes a local absolute-path manifest outside Git. That manifest is accepted by the existing NativeAOT builder.

The snapshot is the compiled selection authority for review/rebuild. Reusable generators and port runtime sources also appear in tools/, managed/ and native/. Editing those copies alone does not change a file selected from this snapshot; deliberately regenerate or update the selection and its hashes.

This is source for an incomplete research build, not proof of working gameplay. See [building](../docs/BUILDING.md) and [known issues](../docs/KNOWN_ISSUES.md).
