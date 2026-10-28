#!/usr/bin/env python3
"""Generate and run original arithmetic patch fixtures without game assemblies."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dotnet', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    generator = output / 'Generator'
    shutil.copytree(ROOT / 'tools/source_port/RegistryGenerator', generator,
                    ignore=shutil.ignore_patterns('bin', 'obj'))
    tests = output / 'Tests'
    tests.mkdir()
    for name in ('Program.cs', 'Fixture.input.cs', 'DispatcherTests.csproj'):
        shutil.copy2(ROOT / 'tests/source_dispatcher' / name, tests / name)
    runtime = tests / 'StaticPatchRuntime.cs'
    shutil.copy2(ROOT / 'managed/SourcePort/StaticPatchRuntime.cs', runtime)
    shutil.copy2(ROOT / 'managed/SourcePort/EHRSourceAccountPolicy.cs', tests / 'EHRSourceAccountPolicy.cs')
    project = tests / 'DispatcherTests.csproj'
    xml = ET.parse(project)
    for compile_item in xml.findall('.//Compile'):
        if compile_item.attrib.get('Include', '').endswith(('/StaticPatchRuntime.cs', '/EHRSourceAccountPolicy.cs')):
            compile_item.set('Include', Path(compile_item.attrib['Include']).name)
    xml.write(project, encoding='unicode')
    env = os.environ.copy()
    env.setdefault('DOTNET_CLI_HOME', str(output / 'DotnetHome'))
    commands = []

    def run(arguments, log):
        command = [str(args.dotnet.resolve()), *map(str, arguments)]
        commands.append(command)
        with (output / log).open('w') as stream:
            subprocess.run(command, cwd=output, env=env, stdout=stream,
                           stderr=subprocess.STDOUT, check=True)

    run(['run', '--project', generator, '--', '--self-test'], 'generator-checks.log')
    run(['run', '--project', generator, '--', '--dispatcher-fixture',
         tests / 'Fixture.input.cs', tests / 'Generated'], 'fixture-generation.log')
    run(['run', '--project', project], 'dispatcher-checks.log')
    report = {
        'schema': 'ehr.source-dispatcher-checks.v1',
        'success': True,
        'gameAssembliesLoaded': False,
        'fixture': 'Original arithmetic inputs and callbacks; generated direct bridges',
        'commands': commands,
        'runtimeSha256': hashlib.sha256(runtime.read_bytes()).hexdigest(),
        'result': (output / 'dispatcher-checks.log').read_text().strip(),
        'gameplayVerified': False,
    }
    (output / 'checks.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
