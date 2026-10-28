#!/usr/bin/env python3
"""Generate a private XCTest overlay checking automatic real Action weak GC cleanup."""
import argparse
import hashlib
from pathlib import Path


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();source=args.source_root.resolve();output=args.output.resolve()
    try:
        if output==source or source in output.parents or any((p/'.git').exists() for p in [output,*output.parents]):
            raise ValueError('Output must be a new directory outside source and Git')
        base=(source/'tests/runtime/NativeRuntimeTests.mm').read_text()
        own=Path(__file__).resolve().parents[1]/'tests/runtime/ActionWeakCollection.inc'
        boundary='}\n\n@interface NativeRuntimeTests : XCTestCase'
        anchor='    lastHooks = hooks ? hooks() : @{};'
        proof='        @"managedSourceReuse": managed,'
        if any(base.count(value)!=1 for value in [boundary,anchor,proof]) or 'exerciseActionAutomaticWeakCollection' in base:
            raise ValueError('Unexpected or already-extended base XCTest')
        base=base.replace(boundary,own.read_text()+'\n'+boundary)
        base=base.replace(anchor,'    NSDictionary *actionWeakCollection = exerciseActionAutomaticWeakCollection(self);\n    XCTAssertTrue([actionWeakCollection[@"success"] boolValue], @"%@", actionWeakCollection);\n'+anchor)
        base=base.replace(proof,proof+'\n        @"actionAutomaticWeakCollection": actionWeakCollection,')
        output.mkdir(parents=True,exist_ok=False)
        target=output/'NativeRuntimeActionWeakCollection.local.mm';target.write_text(base)
        print(str(target));print(hashlib.sha256(target.read_bytes()).hexdigest())
    except (OSError,UnicodeError,ValueError) as error:
        parser.exit(2,type(error).__name__+': '+str(error)+'\n')


if __name__=='__main__':main()
