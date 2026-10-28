#!/usr/bin/env python3
"""Freeze verified public/source-generated build inputs into a local artifact.

No game assembly inputs are accepted by the full-source manifest schema. These
snapshots and their caller-supplied paths belong outside source Git.
"""
from __future__ import annotations
import argparse,hashlib,json
from pathlib import Path
from build_source_application import verify
def freeze(manifest_path,output):
    if output.exists():raise ValueError('Fresh snapshot output required')
    data=manifest_path.read_bytes();manifest=json.loads(data);verify(manifest)
    plan=[]
    for kind in ('sources','resources'):
        for index,item in enumerate(manifest[kind]):
            original=Path(item['path']);content=original.read_bytes()
            if hashlib.sha256(content).hexdigest()!=item['sha256']:raise ValueError('Input changed while snapshotting')
            target=output/kind/str(index)/original.name;plan.append((target,content))
            item['originalPath']=item['path'];item['path']=str(target.resolve())
    for target,content in plan:target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content)
    verify(manifest);path=output/'source-inputs.json';path.write_text(json.dumps(manifest,indent=2)+'\n')
    proof={'schema':'ehr.frozen-source-inputs.v1','originalManifestSHA256':hashlib.sha256(data).hexdigest(),'snapshotManifestSHA256':hashlib.sha256(path.read_bytes()).hexdigest(),'sourceCount':len(manifest['sources']),'resourceCount':len(manifest['resources']),'allBytesVerified':True,'MainLoadExecuted':False,'baseGameDllReferences':False}
    (output/'snapshot-proof.json').write_text(json.dumps(proof,indent=2)+'\n');return proof
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    try:freeze(a.manifest.resolve(),a.output.resolve())
    except (OSError,ValueError,KeyError) as error:p.exit(2,str(error)+'\n')
    return 0
if __name__=='__main__':raise SystemExit(main())
