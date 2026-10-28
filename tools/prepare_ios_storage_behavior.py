#!/usr/bin/env python3
"""Use existing sandbox DataRoot on iOS; do not change cleanup or account policy."""
from pathlib import Path
import argparse,hashlib,json,xml.etree.ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();out=a.output.resolve()
if out.exists():raise ValueError('fresh output required')
(out/'source').mkdir(parents=True);tree=ET.parse(a.project);records=[]
rules={
 'AddSteamID.cs':('if (OperatingSystem.IsAndroid()) return;','if (OperatingSystem.IsAndroid() || OperatingSystem.IsIOS()) return;'),
 'Utils.cs':('OperatingSystem.IsAndroid() ? Main.DataPath : Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)','(OperatingSystem.IsAndroid() || OperatingSystem.IsIOS()) ? Main.DataPath : Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)'),
 'PlayerJoinAndLeftPatch.cs':('OperatingSystem.IsAndroid() ? Main.DataPath : Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)','(OperatingSystem.IsAndroid() || OperatingSystem.IsIOS()) ? Main.DataPath : Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)')}
seen=set()
for item in tree.getroot().iter():
 value=item.get('Include')
 if item.tag.split('}')[-1]!='Compile' or not value:continue
 path=Path(value);path=path if path.is_absolute() else a.project.parent/path
 if path.name not in rules:continue
 if path.name in seen:raise ValueError('ambiguous '+path.name)
 seen.add(path.name);s=path.read_text();before=s;old,new=rules[path.name]
 if s.count(old)!=1:raise ValueError('pinned platform anchor changed in '+str(path))
 s=s.replace(old,new)
 if s.replace(new,old)!=before:raise ValueError('non-platform source mutation')
 target=out/'source'/path.name;target.write_text(s);item.set('Include',str(target));records.append({'input':str(path),'input_sha256':hashlib.sha256(before.encode()).hexdigest(),'output':str(target),'output_sha256':hashlib.sha256(s.encode()).hexdigest()})
if seen!=set(rules):raise ValueError('expected all3 compiled files')
for item in tree.getroot().iter():
 for key in ['Include','Project']:
  value=item.get(key)
  if value and not value.startswith('/') and '$(' not in value and '*' not in value and item.tag.split('}')[-1] in {'Compile','EmbeddedResource','Import'}:item.set(key,str((a.project.parent/value).resolve()))
tree.write(out/'EHR.csproj',encoding='unicode');(out/'storage-overlay.json').write_text(json.dumps({'schema':'ehr.ios-source-storage-overlay.v1','files':records,'cleanupDryRunAgePromptAndFolderChecksUnchanged':True,'androidCleanupEarlyReturnUnchanged':True,'iOSDataRootUsesExistingMainDataPath':True,'steamOnlyFileSkippedOnIOS':True,'accountsOrAuthenticationChanged':False,'actualFilesystemOperationsPerformed':False},indent=2)+'\n');print(out/'EHR.csproj')
