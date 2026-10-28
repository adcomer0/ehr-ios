#!/usr/bin/env python3
"""Generate a dependency-free own audio file/name fixture project outside Git."""
from __future__ import annotations
import argparse,hashlib,json
from pathlib import Path
import xml.etree.ElementTree as E

def prepare(repository,output,kind):
    repository=repository.resolve();output=output.resolve()
    if output.exists():raise ValueError('Fresh fixture output required')
    sources=[repository/'managed/PcmWaveData.cs',repository/'managed/OwnedSoundFiles.cs',repository/('tests/OwnedSoundFixture.cs' if kind=='files' else 'tests/AudioNamesFixture.cs')]
    if kind=='names':sources.append(repository/'managed/SourceAudioNames.cs')
    if not all(p.is_file() for p in sources):raise ValueError('Adopted own source/fixture files required')
    root=E.Element('Project',Sdk='Microsoft.NET.Sdk');group=E.SubElement(root,'PropertyGroup')
    for k,v in {'TargetFramework':'net10.0','AssemblyName':'EHRAudioOwnFixture','OutputType':'Exe','LangVersion':'preview','Nullable':'enable','PublishAot':'true','InvariantGlobalization':'true','EnableDefaultCompileItems':'false'}.items():E.SubElement(group,k).text=v
    group=E.SubElement(root,'ItemGroup')
    for path in sources:E.SubElement(group,'Compile',Include=str(path))
    output.mkdir(parents=True);E.indent(root);E.ElementTree(root).write(output/'EHRAudioOwnFixture.csproj',encoding='unicode')
    (output/'fixture-inputs.json').write_text(json.dumps({'schema':1,'kind':kind,'gameAssemblyReferences':False,'sources':[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sources]},indent=2)+'\n')
    return output/'EHRAudioOwnFixture.csproj'
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--repository-root',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--output',type=Path,required=True);p.add_argument('--kind',choices=['files','names'],required=True);a=p.parse_args()
    try:print(prepare(a.repository_root,a.output,a.kind))
    except (OSError,ValueError) as error:p.exit(2,str(error)+'\n')
if __name__=='__main__':main()
