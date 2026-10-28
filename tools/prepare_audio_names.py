#!/usr/bin/env python3
"""Replace only reviewed iOS audio helpers with exact custom-first name handling."""
from __future__ import annotations
import argparse,hashlib,json
from pathlib import Path
import xml.etree.ElementTree as E

BASE={'SourceAudioPlayback.cs':'d4ae2ddbb94bb4608a18dc29f923cdca551bdd7e81ec8b299d6289357c3021f1','OwnedSoundFiles.cs':'f84e691e1269f0bc1e7d894af31885197db589f5f5697174bfd3ea37b3bf3826'}
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def prepare(project,output):
    project=project.resolve();output=output.resolve()
    if output.exists():raise ValueError('Fresh output directory required')
    tree=E.parse(project);root=tree.getroot();found={};own=Path(__file__).resolve().parents[1]/'managed'
    for item in root.iter('Compile'):
        value=item.get('Include','')
        if not value or any(c in value for c in '$*?'):raise ValueError('Explicit compile paths required')
        path=Path(value);path=(project.parent/path).resolve() if not path.is_absolute() else path.resolve()
        item.set('Include',str(path))
        if path.name=='SourceAudioNames.cs':raise ValueError('Name adapter already selected')
        if path.name not in BASE:continue
        if path.name in found or sha(path)!=BASE[path.name]:raise ValueError('Exact reviewed40 audio helper source required')
        found[path.name]=str(path);item.set('Include',str(own/path.name))
    if set(found)!=set(BASE):raise ValueError('Both reviewed production audio helpers required')
    for item in root.iter('EmbeddedResource'):
        value=item.get('Include','')
        if not value or '$' in value:raise ValueError('Explicit resources required')
        path=Path(value);item.set('Include',str((project.parent/path).resolve() if not path.is_absolute() else path.resolve()))
    E.SubElement(E.SubElement(root,'ItemGroup'),'Compile',Include=str(own/'SourceAudioNames.cs'))
    output.mkdir(parents=True);E.indent(root);tree.write(output/'EHR.csproj',encoding='unicode')
    report={'schema':1,'inputProject':str(project),'inputProjectSha256':sha(project),'reviewedBaseHelpers':BASE,'selectedInputHelpers':found,'outputHelpers':{p.name:sha(p) for p in own.glob('*.cs')},'upstreamOrRpcSourceChanged':False,'existingExactCustomFirst':True,'uniqueCaseInsensitiveAuthoredFallback':True,'canonicalExistingCustomBeforeExtraction':True}
    (output/'audio-name-overlay.json').write_text(json.dumps(report,indent=2)+'\n');return output/'EHR.csproj'
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    try:print(prepare(a.project,a.output))
    except (OSError,ValueError,E.ParseError) as error:p.exit(2,str(error)+'\n')
if __name__=='__main__':main()
