#!/usr/bin/env python3
"""Legacy pinned43 helper upgrade only.

Skip this tool for fresh canonical regeneration: prepare_touch_shortcuts.py
already includes all four current identity/failure helpers. The old SHA guard
intentionally rejects a current helper rather than applying this upgrade twice.
"""
import argparse, hashlib, json, xml.etree.ElementTree as ET
from pathlib import Path
EXPECTED='c7e954f137e8a674c0b600f667bf41ec7741926e7713d4aa9b8e01a0ac61bb26'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def prepare(project,output):
 project=project.resolve();output=output.resolve();stage=Path(__file__).resolve().parents[1]
 if output.exists():raise ValueError('fresh output required')
 tree=ET.parse(project);root=tree.getroot();selected=[]
 for item in root.iter('Compile'):
  value=item.get('Include','');path=Path(value)
  if not path.is_absolute():path=(project.parent/path).resolve()
  if path.name=='IOSTouchShortcuts.cs':selected.append((item,path))
  if path.name=='IOSTouchControlFailureGate.cs':raise ValueError('gate already selected')
 if len(selected)!=1:raise ValueError('one selected own shortcut helper required')
 item,path=selected[0]
 if sha(path)!=EXPECTED:raise ValueError('selected shortcut helper changed')
 output.mkdir(parents=True)
 changes=[]
 for name in ['IOSTouchShortcuts.cs','IOSTouchControlFailureGate.cs']:
  source=stage/'managed'/name;target=output/name;target.write_bytes(source.read_bytes())
  if name=='IOSTouchShortcuts.cs':item.set('Include',str(target))
  else:ET.SubElement(ET.SubElement(root,'ItemGroup'),'Compile',Include=str(target))
  changes.append({'path':str(target),'sha256':sha(target)})
 # Preserve all unrelated explicit project inputs when relocating the project.
 for tag in ['Compile','EmbeddedResource','Content','None','AdditionalFiles','Reference','ProjectReference','Import']:
  for element in root.iter(tag):
   for attribute in ['Include','Update','Project']:
    value=element.get(attribute)
    if not value or '$(' in value or '@(' in value or (tag=='Reference' and attribute=='Include'):continue
    p=Path(value)
    if not p.is_absolute():element.set(attribute,str((project.parent/p).resolve()))
   for child in element:
    if child.tag=='HintPath' and child.text and '$(' not in child.text and not Path(child.text).is_absolute():child.text=str((project.parent/child.text).resolve())
 target=output/'EHR.csproj';tree.write(target,encoding='unicode')
 manifest={'schema':'ehr.ios-touch-identity.v1','projectInput':str(project),'projectInputSha256':sha(project),'helperInput':str(path),'helperInputSha256':sha(path),'projectOutputSha256':sha(target),'helpers':changes,'nativeHooksAdded':0,'gameInvokedByPreparation':False,'productionFailurePolicy':'sealed-hidden-clear-scalar-state-no-retry','identityProbeDoesNotAccessProductionState':True}
 (output/'touch-identity.json').write_text(json.dumps(manifest,indent=2)+'\n');return target
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--project',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args();print(prepare(a.project,a.output))
