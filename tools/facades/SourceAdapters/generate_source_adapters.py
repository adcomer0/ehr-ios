#!/usr/bin/env python3
"""Emit three explicit AOT/root-token source adaptations; never edit upstream."""
from __future__ import annotations
import argparse,hashlib,json,subprocess
from pathlib import Path
import xml.etree.ElementTree as ET

COMMIT='ce23f0d050f617a59507e5bb0fbfff751d4b5134'
CAST='''#if IL2CPP
using Il2CppInterop.Runtime.InteropTypes;
namespace EHR;
public static class Il2CppCastHelper
{
    public static T CastFast<T>(this Il2CppObjectBase obj) where T:Il2CppObjectBase
        =>obj.Cast<T>();
    public static bool TryCastFast<T>(this Il2CppObjectBase obj,out T casted) where T:Il2CppObjectBase
    {
        casted=obj is null?null!:obj.TryCast<T>()!;
        return casted is not null;
    }
}
#endif
'''
def digest(data:bytes)->str:return hashlib.sha256(data).hexdigest()
def generate(project:Path,upstream:Path,output:Path,input_pins:dict):
    observed=subprocess.check_output(['git','-C',str(upstream),'rev-parse','HEAD'],text=True).strip()
    if observed!=COMMIT:raise ValueError('upstream commit pin mismatch')
    root=ET.parse(project).getroot();sources=[];report=[]
    output.mkdir(parents=True,exist_ok=True)
    for item in root.iter('Compile'):
        name=item.get('Include')
        if not name:continue
        source=(project.parent/name).resolve()
        if not source.is_file():raise ValueError('missing explicit Compile input: '+str(source))
        text=None;kind=None
        if source.name=='CastHelper.cs':
            original=upstream/'Modules/Il2CppHelpers/CastHelper.cs';text=CAST;kind='replace raw pointer/expression constructor with actual typed runtime cast'
        elif source.name=='ButtonClickCrashFix.cs':
            original=upstream/'Modules/Il2CppHelpers/ButtonClickCrashFix.cs'
            text=source.read_text(encoding='utf-8-sig').replace('__instance.Pointer != IntPtr.Zero','__instance.Token != 0 && EHR.Generated.FacadeRuntime.TokenIsValid(__instance.Token)')
            if text.count('EHR.Generated.FacadeRuntime.TokenIsValid')!=2:raise ValueError('button pointer pattern changed')
            kind='check gateway-owned root token rather than expose native managed pointer'
        elif source.name=='ExtendedPlayerControl.cs':
            original=upstream/'Modules/ExtendedPlayerControl.cs'
            text='using Il2CppException = EHR.Generated.NativeGameException;\n'+source.read_text(encoding='utf-8-sig');kind='source catch aliases the actual owning native game exception wrapper'
        if text is not None:
            relative=str(original.relative_to(upstream))
            if input_pins.get(relative)!=digest(source.read_bytes()):raise ValueError('selected source SHA pin mismatch: '+relative)
            destination=output/'source'/source.name;destination.parent.mkdir(exist_ok=True);destination.write_text(text)
            report.append(dict(file=relative,adaptation=kind,upstreamSha256=digest(original.read_bytes()),selectedInputSha256=digest(source.read_bytes()),outputSha256=digest(destination.read_bytes())))
            item.set('Include',str(destination.resolve()))
        else:item.set('Include',str(source))
    if len(report)!=3:raise ValueError('expected exactly three source adapters')
    for item in root.iter():
        if item.tag in ('EmbeddedResource','Reference') and item.get('Include'):
            path=Path(item.get('Include'))
            if not path.is_absolute() and (project.parent/path).exists():item.set('Include',str((project.parent/path).resolve()))
        if item.tag=='HintPath' and item.text:
            path=Path(item.text)
            if not path.is_absolute():item.text=str((project.parent/path).resolve())
    ET.indent(root);ET.ElementTree(root).write(output/'EHR.csproj',encoding='unicode')
    result=dict(upstreamCommit=COMMIT,scope='Three source adaptations only, no gameplay parity claim',adapters=report)
    (output/'source-adapters.json').write_text(json.dumps(result,indent=2)+'\n');return result
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--project',type=Path,required=True);parser.add_argument('--upstream-root',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--input-pins',type=Path,required=True,help='Reviewed selected-source SHA256 by upstream relative path, including any static-dispatch overlay');args=parser.parse_args()
    print(json.dumps(generate(args.project.resolve(),args.upstream_root.resolve(),args.output.resolve(),json.loads(args.input_pins.read_text())),indent=2))
if __name__=='__main__':main()
