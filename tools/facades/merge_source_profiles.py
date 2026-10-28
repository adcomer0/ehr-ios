#!/usr/bin/env python3
"""Combine metadata-only IL2CPP source-proxy reports; never loads assemblies."""
from __future__ import annotations
import argparse,hashlib,json
from pathlib import Path

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,action='append',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();definitions={};modules=[]
    for path in sorted(args.input,key=lambda p:p.name):
        report=json.loads(path.read_text());image=report['assemblyName']
        modules.append({'image':image,'inputSha256':report['inputSha256'],'reportSha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        for row in report['typeDefinitions']:
            name=row['name']
            if name in definitions:
                if any(part in name for part in ['<Module>','Microsoft.CodeAnalysis.','System.Runtime.CompilerServices.','PrivateImplementationDetails','UnitySourceGeneratedAssemblyMonoScriptTypes_v1','Cpp2ILInjected.']):continue
                raise ValueError('Ambiguous source type across images: '+name)
            definitions[name]=row
    result={'formatVersion':2,'scope':'Source signatures/class-value distinction only; no executable code.',
            'inputSha256':hashlib.sha256(json.dumps(modules,sort_keys=True).encode()).hexdigest(),'modules':modules,'typeDefinitions':list(definitions.values())}
    args.output.write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
