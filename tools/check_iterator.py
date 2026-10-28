#!/usr/bin/env python3
"""Compile current-source native carrier overlays and run original fixtures.

This checker never reads or executes a game image. Without --binding-header it
uses conspicuously zero compile-only constants, never an installable binding.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--canonical', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--binding-header', type=Path)
    parser.add_argument('--aot-library', type=Path)
    args = parser.parse_args()
    canonical, output = args.canonical.resolve(), args.output.resolve()
    if output == canonical or canonical in output.parents or output in canonical.parents:
        raise ValueError('Output must remain outside canonical')
    if output.exists() and any(output.iterdir()):
        raise ValueError('Output must be fresh or empty')
    output.mkdir(parents=True, exist_ok=True)
    commands = []

    def run(command, log):
        command = [str(item) for item in command]
        commands.append(command)
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        (output / log).write_text(result.stdout)
        if result.returncode:
            raise RuntimeError('Command failed: ' + result.stdout)
        return result.stdout

    overlay = canonical
    include = ['-I', overlay / 'native', '-I', ROOT / 'native', '-I', ROOT / 'native/include',
               '-I', canonical / 'native', '-I', canonical / 'native/include']
    common = ['-std=c++17', '-fobjc-arc', '-fobjc-arc-exceptions', '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations']
    fixture = output / 'iterator-gateway-fixture'
    run(['xcrun', '--sdk', 'macosx', 'clang++', *common, *include,
         ROOT / 'tests/iterator_gateway_fixture.mm', canonical / 'native/EHRRuntimeOriginalProbe.mm',
         canonical / 'native/EHRRuntimeReflection.mm', canonical / 'native/EHRRuntimeCollections.mm',
         canonical / 'native/EHRRuntimePinnedAssociation.mm', '-framework', 'Foundation', '-o', fixture], 'gateway-build.log')
    if not run([fixture], 'gateway-run.log').startswith('PASS:'):
        raise RuntimeError('Gateway fixture did not report pass')
    aot_passed = False
    if args.aot_library:
        fixture = output / 'iterator-aot-fixture'
        run(['xcrun', '--sdk', 'macosx', 'clang++', *common, *include,
             ROOT / 'tests/iterator_aot_fixture.mm', ROOT / 'native/EHRManagedIteratorAdapter.mm',
             '-framework', 'Foundation', '-o', fixture], 'aot-build.log')
        if not run([fixture, args.aot_library.resolve()], 'aot-run.log').startswith('PASS:'):
            raise RuntimeError('NativeAOT fixture did not report pass')
        aot_passed = True
    sdk = run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], 'sdk.log').strip()
    binding = output / 'binding'
    binding.mkdir()
    if args.binding_header:
        (binding / 'EHRHookBinding.generated.h').write_bytes(args.binding_header.read_bytes())
    else:
        (binding / 'EHRHookBinding.generated.h').write_text('''// COMPILE ONLY. ALL ZERO. NEVER INSTALL OR EXECUTE THIS BINDING.
#pragma once
#include <stdint.h>
static const uint8_t EHRHookImageUUID[16] = {0};
static const uintptr_t EHRMurderTrampolineRVA = 0;
#define EHR_HAS_VERSION_HOOK 1
static const uintptr_t EHRVersionMethodRVA = 0;
static const uintptr_t EHRVersionTrampolineRVA = 0;
#define EHR_HAS_IS_MODDED_HOOK 1
static const uintptr_t EHRIsModdedTrampolineRVA = 0;
#define EHR_HAS_ITERATOR_HOOKS 1
static const uintptr_t EHRIteratorMoveTrampolineRVA = 0;
static const uintptr_t EHRIteratorCurrentTrampolineRVA = 0;
static const uintptr_t EHRIteratorResetTrampolineRVA = 0;
''')
    for name in ['EHRRuntimeGateway', 'EHRManagedIteratorAdapter', 'EHRManagedIteratorProbe', 'EHRNativeHooks', 'EHRManagedRuntime']:
        source = overlay / 'native' / (name + '.mm')
        run(['xcrun', '--sdk', 'iphoneos', 'clang++', *common, '-target', 'arm64-apple-ios17.0',
             '-isysroot', sdk, '-DEHR_HAS_MANAGED_RULES=1', '-I', binding, *include,
             '-c', source, '-o', output / (name + '.o')], name + '-ios-build.log')
    evidence = {
        'schema': 'ehr.iterator-carrier-regression.v1',
        'canonical': str(canonical),
        'gatewayPinBorrowFixturePassed': True,
        'nativeAotOwnedFixturePassed': aot_passed,
        'fiveNativeIOSArm64ObjectsCompile': True,
        'bindingConstantsAreCompileOnly': not bool(args.binding_header),
        'gameImageReadOrExecuted': False,
        'unityStartCoroutineTested': False,
        'commands': commands,
        'ownSourceSha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for folder in ['native', 'managed', 'tests'] for path in sorted((ROOT / folder).rglob('*'))
            if path.is_file() and not {'bin', 'obj'} & set(path.relative_to(ROOT).parts)},
    }
    if args.aot_library:
        evidence['ownAotLibrarySha256'] = hashlib.sha256(args.aot_library.read_bytes()).hexdigest()
    (output / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(output / 'evidence.json')


if __name__ == '__main__':
    main()
