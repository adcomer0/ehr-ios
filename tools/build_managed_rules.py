#!/usr/bin/env python3
"""Build original-source EHR rule slices into a native iOS ARM64 library.

Uses an explicitly selected local Microsoft .NET SDK and the verified, unchanged
GPL EHR checkout. No game assembly, PC loader, JIT, or signing material is input.
The output is a source-reuse foundation, not the complete EHR mod.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from inspect_ios import Entry, Limits, parse_image

ROOT = Path(__file__).resolve().parents[1]
PIN = "ce23f0d050f617a59507e5bb0fbfff751d4b5134"
LINKED = ("Modules/OptionItem/ValueRule.cs", "Patches/ServerVersionPatch.cs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dotnet", type=Path, required=True)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="New directory outside Git")
    parser.add_argument("--nuget-cache", type=Path)
    args = parser.parse_args()
    upstream, output = args.upstream.resolve(), args.output.resolve()
    if output.exists() or output.is_symlink():
        parser.error("Output already exists; choose a new directory")
    if any((parent / ".git").exists() for parent in (output, *output.parents)):
        parser.error("Build outputs must remain outside Git checkouts")
    revision = subprocess.check_output(["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True).strip()
    if revision != PIN:
        parser.error("Upstream is not the inspected EHR v8.0.3 commit")
    subprocess.run(["git", "-C", str(upstream), "diff", "--exit-code", PIN, "--", *LINKED], check=True)
    for relative in LINKED:
        if not (upstream / relative).is_file():
            parser.error("Missing original EHR source: " + relative)
    output.mkdir(parents=True)
    project = output / "SourceReuse"
    shutil.copytree(ROOT / "managed/SourceReuse", project)
    shared = ("StaticPatchRuntime.cs", "EHRSourceAccountPolicy.cs", "NativePatchRuntime.cs", "NativePatchSignature.cs", "NativePatchTargets.cs",
              "Host/NativeSourceHost.cs", "Host/SourceCompatibility.cs",
              "Host/SourceHostSelfTest.cs", "Host/SourcePluginHost.cs",
              "Host/SourceSignedUpdates.cs", "Host/NativeSignedUpdates.cs")
    (project / "SourcePort").mkdir()
    for name in shared:
        (project / "SourcePort" / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "managed/SourcePort" / name, project / "SourcePort" / name)
    # Package sources are fixed to official NuGet. Environment/cache changes
    # apply only to this child process, never to shell/global configuration.
    (project / "NuGet.Config").write_text(
        '<?xml version="1.0"?><configuration><packageSources><clear/>'
        '<add key="nuget" value="https://api.nuget.org/v3/index.json"/>'
        '</packageSources></configuration>\n')
    env = dict(os.environ)
    env.update({"DOTNET_CLI_HOME": str(output / "CLI"),
                "NUGET_PACKAGES": str((args.nuget_cache or output / "NuGet").resolve()),
                "DOTNET_NOLOGO": "1", "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
                "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1", "DOTNET_MULTILEVEL_LOOKUP": "0"})
    sdk = subprocess.check_output([str(args.dotnet.resolve()), "--version"], env=env, text=True).strip()
    command = [str(args.dotnet.resolve()), "publish", str(project / "NativeSourceReuse.csproj"),
               "-c", "Release", "-r", "ios-arm64", "-p:EHRSourceRoot=" + str(upstream),
               "--output", str(output / "Publish")]
    with (output / "publish.log").open("w") as stream:
        subprocess.run(command, env=env, cwd=project, stdout=stream, stderr=subprocess.STDOUT, check=True)
    binary = output / "Publish/NativeSourceReuse.dylib"
    image = parse_image(Entry(binary.name, binary.stat().st_size, lambda: binary.open("rb")), Limits())
    if len(image["slices"]) != 1 or (image["slices"][0]["platform"], image["slices"][0]["architecture"], image["slices"][0]["file_type"]) != ("iOS", "arm64", 6):
        raise ValueError("Compiler output is not the required iOS ARM64 dynamic library")
    manifest = {"schema": "ehr.managed-source-build.v1", "dotnet_sdk": sdk,
        "upstream_commit": revision, "upstream_source_sha256": {
            name: hashlib.sha256((upstream / name).read_bytes()).hexdigest() for name in LINKED},
        "source_port_sha256":{name:hashlib.sha256((ROOT / "managed/SourcePort" / name).read_bytes()).hexdigest() for name in shared},
        "own_source_sha256": {str(p.relative_to(ROOT / "managed/SourceReuse")): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in sorted((ROOT / "managed/SourceReuse").rglob("*")) if p.is_file()},
        "binary": image, "native_aot": True, "base_game_assemblies_input": False,
        "runtime_tested_by_build": False, "full_ehr_available": False,
        "scope": "Unchanged EHR numeric option rules/version patches; generated live API foundation"}
    (output / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"library": str(binary), "manifest": str(output / "build-manifest.json"),
                      "full_ehr_available": False}, indent=2))


if __name__ == "__main__":
    main()
