#!/usr/bin/env python3
"""Privately map the exact reviewed iOS host-factory inlining adapter.

Read-only source inspection; emits declarations/pins, never code or assets.
This is an exact source-hash adaptation, not a general inlining detector.
"""
import argparse
import json
import mmap
from pathlib import Path
from game_start_iterator_hook_inputs import selectors,SOURCE_SHA,METADATA_SHA,UUID,INLINE_PROOF
from map_harmony_native_targets import build_report,NestedMetadata
from map_native_methods import MachO,digest,TypeNames


def prepare(framework,metadata_path,pins):
    if digest(framework)!=SOURCE_SHA or digest(metadata_path)!=METADATA_SHA:raise ValueError("Reviewed game source hash differs")
    for key,path in (("framework",framework),("metadata",metadata_path)):
        expected=pins["input_pins"][key]
        if expected["sha256"]!=digest(path) or expected["size"]!=path.stat().st_size:raise ValueError("Pinned source size/hash differs")
    with framework.open("rb") as f,mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as image:
        native=MachO(image)
        if native.uuid!=UUID or pins.get("framework_uuid")!=UUID:raise ValueError("Reviewed source UUID differs")
        metadata=NestedMetadata(metadata_path.read_bytes());report=build_report(native,metadata,selectors())
        raw=native.words(0x5834610,1)[0]
        if raw>>29!=1 or ((raw&0x1fffffff)>>1)!=40081:raise ValueError("Reviewed host allocation type cell differs")
        # The pinned native metadata registration was independently validated by
        # map_native_methods; verify its registered type maps to the same owner.
        from map_native_methods import find_module,find_registrations
        registrations,_,_=find_registrations(native,metadata,find_module(native,metadata,"Assembly-CSharp.dll"))
        if len(registrations)!=1:raise ValueError("Ambiguous native metadata registration")
        reg=registrations[0];types=TypeNames(native,metadata,reg)
        pointer=native.words(reg["types"]+40081*8,1)[0]
        if native.words(pointer,1)[0]!=1187 or metadata.type_name(1187)!=INLINE_PROOF["hostType"]:raise ValueError("Host type cell owner differs")
        for name,expected in ((INLINE_PROOF["parentType"],[("<>1__state","System.Int32"),("<>2__current","System.Object"),("<>4__this","AmongUsClient")]),
            (INLINE_PROOF["hostType"],[("<>1__state","System.Int32"),("<>2__current","System.Object"),("<>4__this","AmongUsClient"),("<start>5__2","System.DateTime")])):
            indices=[i for i in range(len(metadata.types)) if metadata.type_name(i)==name]
            if len(indices)!=1:raise ValueError("Ambiguous native iterator")
            row=metadata.types[indices[0]];actual=[]
            for index in range(row[8],row[8]+row[18]):
                field=metadata.record("fields",12,index,"<Iii");actual.append((metadata.string(field[0]),types.at_index(field[1])))
            if actual!=expected:raise ValueError("Reviewed native iterator fields differ")
    report["input_pins"]={key:pins["input_pins"][key] for key in ("framework","metadata")}
    report["inline_factory_proof"]=INLINE_PROOF
    return report

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("framework","metadata","pins","output"):parser.add_argument("--"+name,type=Path,required=True)
    args=parser.parse_args();output=args.output.resolve()
    if any((p/".git").exists() for p in (output.parent,*output.parents)):parser.error("Generated game map must remain outside Git")
    report=prepare(args.framework.resolve(),args.metadata.resolve(),json.loads(args.pins.read_text()))
    output.parent.mkdir(parents=True,exist_ok=True)
    with output.open("x") as stream:json.dump(report,stream,indent=2);stream.write("\n")
    output.chmod(0o600)
if __name__=="__main__":main()
