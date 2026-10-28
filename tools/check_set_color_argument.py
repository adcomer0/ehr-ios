#!/usr/bin/env python3
"""Small compiled production-frame + exact adapted-wrapper fixture, no game."""
import argparse,hashlib,json,os,subprocess,xml.etree.ElementTree as ET
from pathlib import Path

def check(project,source_root,output,dotnet):
 project=project.resolve();source_root=source_root.resolve();output=output.resolve();stage=Path(__file__).resolve().parents[1]
 if output.exists():raise ValueError('fresh output required')
 selected=[]
 for item in ET.parse(project).getroot().iter('Compile'):
  value=item.get('Include','');p=Path(value);p=p if p.is_absolute() else(project.parent/p).resolve()
  if p.name=='PlayerJoinAndLeftPatch.cs':selected.append(p)
 if len(selected)!=1:raise ValueError('one selected source required')
 source=selected[0].read_text();start=source.index('internal static void __EHRStaticCallback_269(');end=source.index('\n    }\n',start)+len('\n    }');callback=source[start:end]
 if 'unchecked((byte)__ehrFrame.GetArgument<int>("bodyColor"))' not in callback:raise ValueError('adapted exact wrapper required')
 output.mkdir(parents=True)
 generated=output/'ActualCallback269Fixture.cs';generated.write_text('''using PlayerControl=EHR.OwnBindingFixture.OwnReceiver;
namespace EHR.OwnBindingFixture;
// Own CLR receiver and capture action, no native engine emulation. Only the
// generated argument-binding wrapper below is copied from the selected source.
internal sealed class OwnReceiver {}
internal static class ActualCallback269Fixture
{
 internal static int Calls;
 internal static byte Seen;
 private static void Postfix(OwnReceiver receiver,byte bodyColor){Seen=bodyColor;Calls++;}
'''+callback+'\n}\n')
 root=ET.Element('Project',Sdk='Microsoft.NET.Sdk');group=ET.SubElement(root,'PropertyGroup')
 for k,v in {'TargetFramework':'net10.0','OutputType':'Exe','EnableDefaultCompileItems':'false','Nullable':'enable'}.items():ET.SubElement(group,k).text=v
 group=ET.SubElement(root,'ItemGroup');files=[stage/'tests/ArgumentConversionFixture.cs',generated,source_root/'managed/SourcePort/StaticPatchRuntime.cs',source_root/'managed/SourcePort/EHRSourceAccountPolicy.cs']
 for f in files:ET.SubElement(group,'Compile',Include=str(f))
 fixture=output/'Fixture.csproj';ET.ElementTree(root).write(fixture,encoding='unicode')
 command=[str(dotnet),'run','--project',str(fixture),'-c','Release','--nologo'];r=subprocess.run(command,capture_output=True,text=True,env=os.environ.copy());(output/'fixture.log').write_text(r.stdout+r.stderr)
 if r.returncode:raise RuntimeError('fixture failed: '+(r.stdout+r.stderr)[-4000:])
 proof=json.loads(next(line for line in r.stdout.splitlines() if line.startswith('{')));proof['sourcePins']={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+[selected[0]]};(output/'proof.json').write_text(json.dumps(proof,indent=2)+'\n');return output/'proof.json'
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--source-root',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--output',type=Path,required=True);p.add_argument('--dotnet',type=Path,required=True);a=p.parse_args();print(check(a.project,a.source_root,a.output,a.dotnet))
