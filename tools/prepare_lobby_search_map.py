#!/usr/bin/env python3
"""Read-only pinned matchmaking seam mapper; no game execution or body output."""
import argparse
import json
import mmap
import os
from pathlib import Path
from lobby_search_hook_inputs import SOURCE_SHA,METADATA_SHA,UUID,CALLSITE,HELPER,selectors,validate_report
from map_harmony_native_targets import build_report,NestedMetadata
from map_native_methods import MachO,digest,unpack


def prepare(framework,metadata,pins):
 if not isinstance(pins,dict) or not isinstance(pins.get("input_pins"),dict):raise ValueError("Lobby search source pins must be an object")
 before=[(p.stat().st_size,p.stat().st_mtime_ns,p.stat().st_ino) for p in (framework,metadata)]
 for key,path,sha in (("framework",framework,SOURCE_SHA),("metadata",metadata,METADATA_SHA)):
  pin=pins.get("input_pins",{}).get(key)
  if not isinstance(pin,dict) or pin.get("sha256")!=sha or pin.get("size")!=path.stat().st_size or digest(path)!=sha:raise ValueError("Lobby search reviewed input differs")
 with framework.open('rb') as f,mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as image,metadata.open('rb') as m,mmap.mmap(m.fileno(),0,access=mmap.ACCESS_READ) as data:
  native=MachO(image)
  if native.uuid!=UUID:raise ValueError("Lobby search UUID differs")
  report=build_report(native,NestedMetadata(data),selectors())
  word=unpack(native.data,'<I',native.va_to_offset(CALLSITE,4))[0];immediate=word&0x3ffffff
  if immediate&0x2000000:immediate-=0x4000000
  if word&0xfc000000!=0x94000000 or CALLSITE+immediate*4!=int(HELPER[6],16):raise ValueError("Lobby search direct request callsite differs")
 report['input_pins']={k:dict(pins['input_pins'][k]) for k in ('framework','metadata')}
 report['search_callsite']={'caller':'HttpMatchmakerManager+<CoRequestGameListFiltered>d__20.MoveNext','callsite_rva':hex(CALLSITE),'return_rva':hex(CALLSITE+4),'target_rva':HELPER[6],'direct_call_verified':True}
 validate_report(pins,report)
 if before!=[(p.stat().st_size,p.stat().st_mtime_ns,p.stat().st_ino) for p in (framework,metadata)] or digest(framework)!=SOURCE_SHA or digest(metadata)!=METADATA_SHA:raise ValueError("Lobby search inputs changed during inspection")
 return report


def main():
 p=argparse.ArgumentParser(description=__doc__)
 for key in ('framework','metadata','pins','output'):p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args();output=a.output.resolve()
 if output.exists() or any((parent/'.git').exists() for parent in (output,*output.parents)):p.error('Choose a fresh output outside Git')
 report=prepare(a.framework.resolve(),a.metadata.resolve(),json.loads(a.pins.read_text()));output.parent.mkdir(parents=True,exist_ok=True)
 fd=os.open(output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
 with os.fdopen(fd,'w') as f:json.dump(report,f,indent=2);f.write('\n')


if __name__=='__main__':main()
