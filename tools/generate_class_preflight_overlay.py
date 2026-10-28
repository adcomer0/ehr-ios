#!/usr/bin/env python3
"""Inline OWN read-only preflight into a fresh signed XCTest source overlay."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def one(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Expected one test integration site: ' + old)
    return text.replace(old, new)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--canonical', type=Path, required=True)
    parser.add_argument('--test-source', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    canonical, output = args.canonical.resolve(), args.output.resolve()
    if output == canonical or canonical in output.parents or output in canonical.parents:
        raise ValueError('Output must be outside canonical')
    if output.exists() and any(output.iterdir()):
        raise ValueError('Output must be fresh or empty')
    source = args.test_source or canonical / 'tests/runtime/NativeRuntimeTests.mm'
    original = source.read_text()
    if 'EHRClassLayoutPreflightWithLookup' in original:
        raise ValueError('Class preflight already integrated')
    core = (ROOT / 'native/EHRClassLayoutCore.hpp').read_text().replace('#pragma once\n', '', 1)
    probe = (ROOT / 'native/EHRClassLayoutPreflight.mm').read_text()
    probe = one(probe, '#import "EHRClassLayoutPreflight.h"', '#import <Foundation/Foundation.h>')
    probe = one(probe, '#include "EHRClassLayoutCore.hpp"', core)
    probe = one(probe, '#include "EHRRuntimeGateway.h"', '#include "native/EHRRuntimeGateway.h"')
    anchor = 'namespace {\nvoid *bridgeExport(const char *symbol) {'
    text = one(original, anchor, '// BEGIN original read-only class preflight source\n' + probe + '\n// END original read-only class preflight source\n\n' + anchor)
    anchor = 'NSDictionary *unityScheduling = EHRExerciseIteratorScheduling(self, bridgeExport);'
    text = one(text, anchor, anchor + '\n    NSDictionary *classLayout = EHRClassLayoutPreflightWithLookup(bridgeExport);')
    anchor = 'XCTAssertTrue([unityScheduling[@"success"] boolValue], @"%@", unityScheduling);'
    text = one(text, anchor, anchor + '\n    XCTAssertTrue([classLayout[@"success"] boolValue], @"%@", classLayout);')
    anchor = '@"unityIteratorScheduling": unityScheduling,'
    text = one(text, anchor, anchor + '\n        @"classLayoutPreflight": classLayout,')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'NativeRuntimeTests.mm').write_text(text)
    (output / 'generation-manifest.json').write_text(json.dumps({
        'schema': 'ehr.class-layout-xctest-overlay.v1',
        'inputSource': str(source.resolve()), 'inputSha256': hashlib.sha256(original.encode()).hexdigest(),
        'outputSha256': hashlib.sha256(text.encode()).hexdigest(),
        'nativeAppSourceChanges': False, 'newAppExportsRequired': False, 'classInjectionPerformed': False,
        'gate': 'existing gateway validate_native_method full candidate SHA256 + UUID + expected version RVA30734292',
        'sourceSha256': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in ['native/EHRClassLayoutCore.hpp', 'native/EHRClassLayoutPreflight.mm']},
    }, indent=2) + '\n')
    print(output / 'NativeRuntimeTests.mm')


if __name__ == '__main__':
    main()
