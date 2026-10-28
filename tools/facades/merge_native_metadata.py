#!/usr/bin/env python3
"""Merge metadata-only module reports, retaining the real image for every type."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

def main() -> None:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("directory",type=Path)
    p.add_argument("output",type=Path)
    args=p.parse_args()
    definitions={};modules=[]
    for file in sorted(args.directory.glob("*.json")):
        report=json.loads(file.read_text())
        if not isinstance(report,dict) or not report.get("typeDefinitions"):continue
        image=report["assemblyName"]+".dll"
        modules.append({"image":image,"sha256":report["inputSha256"]})
        for original in report["typeDefinitions"]:
            name=original["name"]
            if name.endswith("]<Module>"):continue
            if name.startswith("[<local>]Cpp2ILInjected."):continue
            if name.startswith("[<local>]UnitySourceGeneratedAssemblyMonoScriptTypes_v1"):continue
            if "<" in name.split("]",1)[-1]:continue # compiler implementation-only, not source-addressable API types
            if name.startswith(("[<local>]Microsoft.CodeAnalysis.","[<local>]System.Runtime.CompilerServices.")):continue
            if name in definitions:raise ValueError("Duplicate native type across images: "+name)
            definitions[name]=dict(original,image=image)
    fingerprint=hashlib.sha256(json.dumps(modules,sort_keys=True).encode()).hexdigest()
    result={"formatVersion":1,"scope":"Metadata names/signatures only; no executable bytes or assembly loading.",
            "inputSha256":fingerprint,"moduleImages":modules,"typeDefinitions":list(definitions.values())}
    args.output.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps({"modules":len(modules),"types":len(definitions),"fingerprint":fingerprint}))
if __name__=="__main__":main()
