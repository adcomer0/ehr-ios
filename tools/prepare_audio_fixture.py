#!/usr/bin/env python3
"""Build a pure own PCM fixture plus exact pinned upstream WAV decoder witness."""
from __future__ import annotations
import argparse,hashlib,json,subprocess
from pathlib import Path
import xml.etree.ElementTree as E
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--upstream-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
stage=Path(__file__).resolve().parents[1];repo=a.upstream_root.resolve();out=a.output.resolve()
if out.exists():raise ValueError('fresh fixture output required')
if subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()!='ce23f0d050f617a59507e5bb0fbfff751d4b5134':raise ValueError('pinned source commit required')
source=repo/'Modules/CustomSounds.cs';text=source.read_text();start=text.index('    private class WAV');begin=text.index('{',start);depth=1;end=begin+1
while depth:
    if text[end]=='{':depth+=1
    elif text[end]=='}':depth-=1
    end+=1
legacy=text[start:end].replace('private class WAV','internal class LegacyWav',1).replace('public WAV(byte[] wav)','public LegacyWav(byte[] wav)',1)
out.mkdir(parents=True);(out/'LegacyWav.cs').write_text('// Derived verbatim parser witness from pinned EHR GPL-3.0 source; local fixture only.\nnamespace AudioFixture;\n'+legacy+'\n')
(out/'Program.cs').write_bytes((stage/'tests/WaveFixture.cs').read_bytes())
root=E.Element('Project',Sdk='Microsoft.NET.Sdk');g=E.SubElement(root,'PropertyGroup')
for k,v in {'OutputType':'Exe','TargetFramework':'net10.0','LangVersion':'preview','EnableDefaultCompileItems':'false','PublishAot':'true','InvariantGlobalization':'true'}.items():E.SubElement(g,k).text=v
g=E.SubElement(root,'ItemGroup')
for path in (out/'LegacyWav.cs',out/'Program.cs',stage/'managed/PcmWaveData.cs'):E.SubElement(g,'Compile',Include=str(path))
E.indent(root);E.ElementTree(root).write(out/'AudioFixture.csproj',encoding='unicode')
report={'upstreamCommit':'ce23f0d050f617a59507e5bb0fbfff751d4b5134','sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'legacyWitnessSHA256':hashlib.sha256((out/'LegacyWav.cs').read_bytes()).hexdigest(),'sourceGuardChanged':False,'gameAssemblyReferences':False,'audiblePlaybackRequested':False}
(out/'provenance.json').write_text(json.dumps(report,indent=2)+'\n')
print(out/'AudioFixture.csproj')
