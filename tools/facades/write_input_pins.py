#!/usr/bin/env python3
"""Record digests after independently verifying the upstream/input provenance."""
from __future__ import annotations
import argparse,hashlib,json
from pathlib import Path

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['references','native-definitions','source-profile','selectors']:parser.add_argument('--'+name,type=Path,required=name in ['references','native-definitions'])
    parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    inputs={'references':args.references,'nativeDefinitions':args.native_definitions,'sourceProfile':args.source_profile,'selectors':args.selectors}
    result={'formatVersion':1,'upstreamCommit':'ce23f0d050f617a59507e5bb0fbfff751d4b5134','inputs':{name:{'sha256':hashlib.sha256(path.read_bytes()).hexdigest()} for name,path in inputs.items() if path is not None}}
    args.output.write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
