#!/usr/bin/env python3
"""Create a new private XCTest overlay for the finite native Action proof."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(source_root, base_test, output):
    source_root=source_root.resolve();base_test=base_test.resolve();output=output.resolve()
    if source_root==output or source_root in output.parents or output==base_test or output in base_test.parents:
        raise ValueError('Output must be independent of the source and base test')
    if any((parent/'.git').exists() for parent in [output,*output.parents]):
        raise ValueError('Private output must be outside Git checkouts')
    own_source=Path(__file__).resolve().parents[1]/'tests/runtime/ActionDelegatePrototype.inc'
    before=digest(base_test);base=base_test.read_text();prototype=own_source.read_text()
    boundary='}\n\n@interface NativeRuntimeTests : XCTestCase'
    anchor='    NSDictionary *gateway = exerciseGateway();'
    proof_anchor='        @"runtimeGateway": gateway,'
    if any(base.count(value)!=1 for value in [boundary,anchor,proof_anchor]) or 'exerciseNativeActionDelegatePrototype' in base:
        raise ValueError('Unexpected or already-extended base XCTest source')
    base='#include <pthread.h>\n'+base.replace(boundary,prototype+'\n'+boundary)
    base=base.replace(anchor,anchor+'\n    NSDictionary *actionDelegate = exerciseNativeActionDelegatePrototype();\n    XCTAssertTrue([actionDelegate[@"success"] boolValue], @"%@", actionDelegate);')
    base=base.replace(proof_anchor,proof_anchor+'\n        @"nativeActionDelegatePrototype": actionDelegate,')
    if digest(base_test)!=before:
        raise ValueError('Base XCTest source changed while generating')
    output.mkdir(parents=True,exist_ok=False)
    overlay=output/'NativeRuntimeActionDelegate.local.mm';overlay.write_text(base)
    manifest={'schema':'ehr.action-delegate-prototype-generation.v1','base_test_sha256':before,
        'prototype_sha256':digest(own_source),'generator_sha256':digest(Path(__file__)),
        'overlay_sha256':digest(overlay),'runtime_execution_performed':False,
        'scope':'Finite native System.Action construction/invoke proof; no general ownership API'}
    (output/'generation-manifest.local.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return {'output':str(output),**manifest}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root',type=Path,required=True)
    parser.add_argument('--base-test',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    try:
        print(json.dumps(generate(args.source_root,args.base_test or args.source_root/'tests/runtime/NativeRuntimeTests.mm',args.output),indent=2))
    except (OSError,UnicodeError,ValueError) as error:
        parser.exit(2,type(error).__name__+': '+str(error)+'\n')


if __name__=='__main__':main()
