#!/usr/bin/env python3
"""Reproduce source-only IL2CPP registry/bootstrap/dispatch in a fresh stage.

Compiles pinned EHR against its existing managed reference packages, does not
load its assembly, and omits resources and copy/deployment targets. No native
binding or gameplay availability is implied by a successful build.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import feature_inventory as inventory

ROOT = Path(__file__).resolve().parent
DOTNET = Path(os.environ.get('DOTNET', 'dotnet'))


def project_xml(repo, source_paths, generated):
    root = ET.parse(repo / 'EHR.csproj').getroot()
    for child in list(root):
        if child.tag in ('Import', 'Target'):
            root.remove(child)
        elif child.tag == 'ItemGroup':
            for item in list(child):
                if item.tag in ('Compile', 'EmbeddedResource', 'None'):
                    child.remove(item)
            if not len(child):
                root.remove(child)
    props = ET.SubElement(root, 'PropertyGroup')
    for key, value in {
        'EnableDefaultCompileItems': 'false', 'EnableDefaultEmbeddedResourceItems': 'false',
        'CopyLocalLockFileAssemblies': 'false', 'AssemblyName': 'EHR',
        'Version': '8.0.3', 'PackageVersion': '8.0.3', 'GitVersion': 'false',
    }.items():
        ET.SubElement(props, key).text = value
    # Keep the original inactive Mono branch valid without copying bindings.
    for hint in root.findall(".//Reference[@Include='Assembly-CSharp']/HintPath"):
        hint.text = str(repo / 'GameLibs/Assembly-CSharp.dll')
    target = ET.SubElement(root, 'Target', Name='EHRStageNoDependencyCopy', AfterTargets='ResolveReferences')
    group = ET.SubElement(target, 'ItemGroup')
    ET.SubElement(group, 'ReferenceCopyLocalPaths', Remove='@(ReferenceCopyLocalPaths)')
    group = ET.SubElement(root, 'ItemGroup')
    for path in [*source_paths, *generated]:
        ET.SubElement(group, 'Compile', Include=str(path))
    ET.indent(root)
    return ET.tostring(root, encoding='unicode')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=inventory.UPSTREAM_DEFAULT)
    parser.add_argument('--dotnet', type=Path, default=DOTNET)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    if inventory.git(repo, 'rev-parse', 'HEAD') != inventory.PIN or inventory.git(repo, 'status', '--porcelain', '--untracked-files=no'):
        raise ValueError('Source build requires the clean pinned EHR checkout')
    if output.exists() and any(output.iterdir()):
        raise ValueError('Output directory must be fresh or empty')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'LICENSE.upstream-EHR').write_bytes((repo / 'LICENSE').read_bytes())
    (output / 'NOTICE.txt').write_text('Derived source overlays and generated EHR registries/callback catalogs reference EndlessHostRoles by Gurge44 and contributors, GPL-3.0. Upstream commit: ' + inventory.PIN + '\nNo Among Us game resources or proprietary game implementation are included. The compiled own EHR mod assembly is a reference-profile verification artifact.\n')
    env = os.environ.copy()
    commands = []
    generator = output / 'Generator'
    shutil.copytree(ROOT / 'RegistryGenerator', generator, ignore=shutil.ignore_patterns('bin', 'obj'))

    def run(command, log):
        commands.append([str(item) for item in command])
        with (output / log).open('w') as stream:
            subprocess.run([str(item) for item in command], cwd=ROOT, env=env, stdout=stream,
                           stderr=subprocess.STDOUT, check=True)

    def generate(*arguments, log):
        run([args.dotnet, 'run', '--project', generator, '--', *arguments], log)

    generate(repo, 'IL2CPP', output / 'Registry', log='registry.log')
    generate('--bootstrap', repo, 'IL2CPP', output / 'Bootstrap', log='bootstrap.log')
    run([sys.executable, ROOT / 'wire_aot_registry.py', '--upstream', repo,
         '--source-overlay', output / 'Bootstrap/source', '--output', output / 'Wiring'], 'wiring.log')
    source_names = inventory.git(repo, 'ls-files', '*.cs').splitlines()
    source_names = [p for p in source_names if not p.startswith('CTA/')]
    overlays = [output / 'Wiring', output / 'Bootstrap/source', repo]
    sources = [next(path / name for path in overlays if (path / name).exists()) for name in source_names]
    compile_dir = output / 'Compile'
    compile_dir.mkdir()
    project = compile_dir / 'EHR.csproj'
    generated = [output / 'Registry/EHRAotRegistry.g.cs', output / 'Bootstrap/EHRSourceBootstrap.g.cs']
    project.write_text(project_xml(repo, sources, generated))
    run([args.dotnet, 'restore', project, '-p:Configuration=IL2CPP'], 'restore.log')
    references = output / 'reference-items.json'
    with references.open('w') as stream:
        command = [str(args.dotnet), 'msbuild', str(project), '-p:Configuration=IL2CPP',
                   '-t:ResolveReferences', '-getItem:ReferencePath', '-v:quiet']
        commands.append(command)
        subprocess.run(command, cwd=ROOT, env=env, stdout=stream, check=True)
    # Validate structured MSBuild output before it is used as metadata paths.
    assert json.loads(references.read_text())['Items']['ReferencePath']
    generate('--selectors', repo, 'IL2CPP', output / 'Dispatcher', references,
             output / 'Wiring', output / 'Bootstrap/source', log='dispatcher.log')
    overlays.insert(0, output / 'Dispatcher/source')
    sources = [next(path / name for path in overlays if (path / name).exists()) for name in source_names]
    runtime = output / 'StaticPatchRuntime.cs'
    runtime.write_text((ROOT.parents[1] / 'managed/SourcePort/StaticPatchRuntime.cs').read_text())
    generated += [output / 'Dispatcher/EHRStaticPatchCatalog.g.cs', runtime]
    policy = output / 'EHRSourceAccountPolicy.cs'
    policy.write_text((ROOT.parents[1] / 'managed/SourcePort/EHRSourceAccountPolicy.cs').read_text())
    generated.append(policy)
    project.write_text(project_xml(repo, sources, generated))
    manifest = [{'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                for path in [*sources, *generated]]
    (output / 'compile_sources.json').write_text(json.dumps(manifest, indent=2) + '\n')
    run([args.dotnet, 'build', project, '-c', 'IL2CPP', '--no-restore', '-v:minimal'], 'build.log')
    assembly = compile_dir / 'bin/IL2CPP/net6.0/EHR.dll'
    generate('--verify-assembly', assembly, output / 'Registry/registry_coverage.json',
             output / 'compiled_validation.json', log='compiled-validation.log')
    evidence = {
        'schema': 'ehr.static-il2cpp-source-build.v1', 'upstreamCommit': inventory.PIN,
        'sourceFiles': len(sources), 'profile': 'IL2CPP', 'assemblyLoaded': False,
        'nativeTargetsBound': 0, 'gameplayVerified': False, 'commands': commands,
        'sourceManifestSha256': hashlib.sha256((output / 'compile_sources.json').read_bytes()).hexdigest(),
        'scope': 'Full pinned IL2CPP source plus explicit registries/bootstrap/direct callbacks compiled against the original managed references; PE metadata coverage verified. No game resources or runtime dependency assemblies copied.',
    }
    (output / 'build_evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(output / 'build_evidence.json')


if __name__ == '__main__':
    main()
