#!/usr/bin/env python3
"""Pinned callback269 Int32 codec read with explicit byte-value adaptation."""
import argparse,hashlib,json,xml.etree.ElementTree as ET
from pathlib import Path
EXPECTED='c88ed5682cddd5a60bf3c6cb04ead9c66423ffda2780975c25c1479574693c94'
OLD='''internal static void __EHRStaticCallback_269(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        PlayerControl __ehrp0 = __ehrFrame.GetInstance<PlayerControl>();
        byte __ehrp1 = __ehrFrame.GetArgument<byte>("bodyColor");'''
NEW=OLD.replace('__ehrFrame.GetArgument<byte>("bodyColor")','unchecked((byte)__ehrFrame.GetArgument<int>("bodyColor"))')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def adapt(text):
 if text.count(OLD)!=1 or NEW in text:raise ValueError('pinned269 read anchor changed')
 changed=text.replace(OLD,NEW)
 if changed.replace(NEW,OLD)!=text:raise ValueError('source body changed')
 return changed

def prepare(project,output):
 project=project.resolve();output=output.resolve()
 if output.exists():raise ValueError('fresh output required')
 tree=ET.parse(project);root=tree.getroot();selected=[]
 for item in root.iter('Compile'):
  value=item.get('Include','');p=Path(value);p=p if p.is_absolute() else (project.parent/p).resolve()
  if p.name=='PlayerJoinAndLeftPatch.cs':selected.append((item,p))
 if len(selected)!=1:raise ValueError('one selected PlayerJoinAndLeftPatch required')
 item,source=selected[0]
 if sha(source)!=EXPECTED:raise ValueError('selected source pin changed')
 changed=adapt(source.read_text());output.mkdir(parents=True);target=output/'PlayerJoinAndLeftPatch.cs';target.write_text(changed);item.set('Include',str(target))
 for tag in ['Compile','EmbeddedResource','Content','None','AdditionalFiles','Reference','ProjectReference','Import']:
  for element in root.iter(tag):
   for attribute in ['Include','Update','Project']:
    value=element.get(attribute)
    if not value or '$(' in value or '@(' in value or (tag=='Reference' and attribute=='Include'):continue
    path=Path(value)
    if not path.is_absolute():element.set(attribute,str((project.parent/path).resolve()))
   for child in element:
    if child.tag=='HintPath' and child.text and '$(' not in child.text and not Path(child.text).is_absolute():child.text=str((project.parent/child.text).resolve())
 result=output/'EHR.csproj';tree.write(result,encoding='unicode')
 manifest={'schema':'ehr.set-color-argument.v1','inputProject':str(project),'inputProjectSha256':sha(project),'inputSource':str(source),'inputSourceSha256':sha(source),'outputSourceSha256':sha(target),'outputProjectSha256':sha(result),'targetId':4044753517333114937,'nativeMethod':'PlayerControl.SetColor(System.Int32)','sourceCallback':'EHR.SetColorPatch.Postfix#269','exactOldAnchor':OLD,'exactNewAnchor':NEW,'sourceByteCallbackBodyUnchanged':True,'sentinel255Preserved':True,'conversion':'unchecked Int32 to Byte; low8bits, identity on0..255','genericFrameCastChanged':False,'nativeHooksChanged':False,'authenticationChanged':False,'accountPolicyChanged':False,'runtimeGameInvoked':False}
 (output/'set-color-argument.json').write_text(json.dumps(manifest,indent=2)+'\n');return result
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();print(prepare(a.project,a.output))
