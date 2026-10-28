#!/usr/bin/env python3
"""Run owned route regressions against current canonical native gateway source.

No game executable, framework, binary metadata, account or signing input is used.
The fixture installs its owned runtime API explicitly. An optional own NativeAOT
fixture library proves the four-function table round trip as well.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent if SCRIPT_DIR.name == 'tools' else SCRIPT_DIR


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--canonical', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--aot-library', type=Path)
    args = parser.parse_args()
    canonical, output = args.canonical.resolve(), args.output.resolve()
    if output == canonical or canonical in output.parents or output in canonical.parents:
        raise ValueError('Build output must remain outside canonical')
    if output.exists() and any(output.iterdir()):
        raise ValueError('Output must be fresh or empty')
    output.mkdir(parents=True, exist_ok=True)
    gateway = canonical / 'native/EHRRuntimeGateway.mm'
    fixture = ROOT / 'tests/original_route_fixture.mm'
    text = gateway.read_text()
    start = text.index('extern "C" EHRRuntimeStatus ehr_runtime_find_class(')
    end = text.index('extern "C" EHRRuntimeStatus ehr_runtime_object_class(', start)
    required = set(re.findall(r'\bapi\.([a-z_]+)\s*\(', text[start:end]))
    supplied = set(re.findall(r'\ba\.([a-z_]+)\s*=', fixture.read_text()))
    missing = required - supplied
    if missing:
        raise ValueError('Current class lookup needs new owned fixture callbacks: ' + ', '.join(sorted(missing)))
    commands = []

    def run(command, log):
        commands.append([str(item) for item in command])
        result = subprocess.run([str(item) for item in command], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        (output / log).write_text(result.stdout)
        if result.returncode:
            raise RuntimeError('Owned test command failed: ' + result.stdout)
        return result.stdout

    common = ['xcrun', '--sdk', 'macosx', 'clang++', '-std=c++17', '-fobjc-arc', '-fobjc-arc-exceptions',
              '-g', '-Wall', '-Wextra', '-Werror', '-I', ROOT / 'native', '-I', ROOT / 'native/include',
              '-I', canonical / 'native', '-I', canonical / 'native/include']
    native_probe = canonical / 'native/EHRRuntimeOriginalProbe.mm'
    # Candidate pins are deliberately absent in this owned fixture. Compile
    # the real adapter too; it must remain unsupported without those pins.
    association = canonical / 'native/EHRRuntimePinnedAssociation.mm'
    reflection = canonical / 'native/EHRRuntimeReflection.mm'
    collections = canonical / 'native/EHRRuntimeCollections.mm'
    binary = output / 'original-route-fixture'
    run([*common, '-Wno-deprecated-declarations', fixture, native_probe, association, reflection, collections,
         '-framework', 'Foundation', '-o', binary], 'native-build.log')
    if not run([binary], 'native-run.log').startswith('PASS:'):
        raise RuntimeError('Owned native fixture did not report success')
    aot_passed = False
    if args.aot_library:
        adapter = ROOT / 'native/EHRManagedOriginalAdapter.mm'
        binary = output / 'original-aot-fixture'
        run([*common, '-Wno-deprecated-declarations', ROOT / 'tests/original_aot_fixture.mm', adapter, native_probe, association, reflection, collections,
             '-framework', 'Foundation', '-o', binary], 'aot-build.log')
        if not run([binary, args.aot_library.resolve()], 'aot-run.log').startswith('PASS:'):
            raise RuntimeError('Owned NativeAOT fixture did not report success')
        aot_passed = True
    names = ['native/EHRRuntimeGateway.mm', 'native/EHRRuntimeGateway.h',
             'native/EHRRuntimeOriginal.h', 'native/EHRRuntimeOriginal.inc',
             'native/EHRRuntimeOriginalProbe.mm', 'native/include/EHROriginalInvocationGate.hpp']
    evidence = {'schema': 'ehr.current-source-original-route-regression.v1', 'canonical': str(canonical),
        'nativePassed': True, 'nativeAotFixturePassed': aot_passed, 'gameImageExecuted': False,
        'currentClassLookupCallbacksCovered': sorted(required), 'commands': commands,
        'canonicalSourceSha256': {name: hashlib.sha256((canonical / name).read_bytes()).hexdigest() for name in names}}
    (output / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(output / 'evidence.json')


if __name__ == '__main__':
    main()
