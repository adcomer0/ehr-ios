#!/usr/bin/env python3
"""Preserve pinned map-picker callback body; bind its declared native base."""
import argparse,hashlib,json,xml.etree.ElementTree as ET
from pathlib import Path
EXPECTED='5bc92cf909e635526d0e05bace9a8795fbd52539dd8e56979b44fa97204e779a'
CHANGES=[('public static void Postfix_Initialize(CreateGameMapPicker __instance)','public static void Postfix_Initialize(GameOptionsMapPicker __instance)'),('internal static void __EHRStaticCallback_191(global::EHR.EHRStaticPatchFrame __ehrFrame)\n    {\n        CreateGameMapPicker __ehrp0 = __ehrFrame.GetInstance<CreateGameMapPicker>();','internal static void __EHRStaticCallback_191(global::EHR.EHRStaticPatchFrame __ehrFrame)\n    {\n        GameOptionsMapPicker __ehrp0 = __ehrFrame.GetInstance<GameOptionsMapPicker>();')]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def adapt(text):
 before=text
 for old,new in CHANGES:
  if text.count(old)!=1:raise ValueError('pinned callback anchor changed')
  text=text.replace(old,new)
 restored=text
 for old,new in reversed(CHANGES):
  if restored.count(new)!=1:raise ValueError('ambiguous adapted anchor')
  restored=restored.replace(new,old)
 if restored!=before:raise ValueError('callback body or unrelated source changed')
 return text

def prepare(project,output):
 project=project.resolve();output=output.resolve()
 if output.exists():raise ValueError('fresh output required')
 tree=ET.parse(project);root=tree.getroot();selected=[]
 for item in root.iter('Compile'):
  value=item.get('Include','');p=Path(value);p=p if p.is_absolute() else (project.parent/p).resolve()
  if p.name=='MapPickerMenuPatch.cs':selected.append((item,p))
 if len(selected)!=1:raise ValueError('one selected map-picker source required')
 item,source=selected[0]
 if sha(source)!=EXPECTED:raise ValueError('selected map-picker source changed')
 changed=adapt(source.read_text());output.mkdir(parents=True)
 target=output/'MapPickerMenuPatch.cs';target.write_text(changed);item.set('Include',str(target))
 for tag in ['Compile','EmbeddedResource','Content','None','AdditionalFiles','Reference','ProjectReference','Import']:
  for element in root.iter(tag):
   for attribute in ['Include','Update','Project']:
    value=element.get(attribute)
    if not value or '$(' in value or '@(' in value or (tag=='Reference' and attribute=='Include'):continue
    path=Path(value)
    if not path.is_absolute():element.set(attribute,str((project.parent/path).resolve()))
   for child in element:
    if child.tag=='HintPath' and child.text and '$(' not in child.text and not Path(child.text).is_absolute():child.text=str((project.parent/child.text).resolve())
 targetProject=output/'EHR.csproj';tree.write(targetProject,encoding='unicode')
 manifest={'schema':'ehr.map-picker-base-receiver.v1','inputProject':str(project),'inputProjectSha256':sha(project),'inputSource':str(source),'inputSourceSha256':sha(source),'outputSource':str(target),'outputSourceSha256':sha(target),'outputProjectSha256':sha(targetProject),'exactReversibleChanges':CHANGES,'targetId':10472262462983385326,'nativeMethod':'GameOptionsMapPicker.SetupMapButtons(System.Int32)','nativeRva':'0x1c04144','sourceCallback':'EHR.Patches.GameOptionsMapPickerPatch::Postfix_Initialize#191','callbackBodyAndGuardsUnchanged':True,'nativeHooksChanged':False,'authenticationChanged':False,'accountPolicyChanged':False,'runtimeGameInvoked':False}
 (output/'map-picker-receiver.json').write_text(json.dumps(manifest,indent=2)+'\n');return targetProject
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();print(prepare(a.project,a.output))
