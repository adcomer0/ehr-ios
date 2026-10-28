#!/usr/bin/env python3
from pathlib import Path
import argparse,hashlib,json,xml.etree.ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--overlay',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();out=a.output.resolve()
if out.exists():raise ValueError('fresh output required')
out.mkdir(parents=True);tree=ET.parse(a.project);found={}
for item in tree.getroot().iter():
 value=item.get('Include');kind=item.tag.split('}')[-1]
 if kind!='Compile' or not value:continue
 path=Path(value);path=path if path.is_absolute() else a.project.parent/path
 if path.name not in ['ClientControlGUI.cs','OperatingSystem.cs']:continue
 if path.name in found:raise ValueError('ambiguous '+path.name)
 found[path.name]=str(path);item.set('Include',str((a.overlay/path.name).resolve()))
if len(found)!=2:raise ValueError('expected exactly2 existing compiled source files')
for item in tree.getroot().iter():
 for key in ['Include','Project']:
  value=item.get(key)
  if value and not value.startswith('/') and '$(' not in value and '*' not in value and item.tag.split('}')[-1] in {'Compile','EmbeddedResource','Import'}:item.set(key,str((a.project.parent/value).resolve()))
tree.write(out/'EHR.csproj',encoding='unicode');(out/'platform-project.json').write_text(json.dumps({'project':str(a.project),'project_sha256':hashlib.sha256(a.project.read_bytes()).hexdigest(),'replaced':found,'newTypesAdded':False},indent=2)+'\n');print(out/'EHR.csproj')
