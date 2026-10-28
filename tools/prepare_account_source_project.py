#!/usr/bin/env python3
"""Compose a pinned account-policy adapter onto already selected source items.

The actual protection rules remain in the independently reviewed supplied tool;
this join preserves all unrelated source-generation/dispatcher adaptations.
"""
from __future__ import annotations
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
import xml.etree.ElementTree as ET

NAMES=('Modules/LobbySharingAPI.cs','Modules/OptionHolder.cs','Modules/OptionItem/OptionItem.cs','Patches/ChatCommandPatch.cs')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('project','upstream-root','adapter','dispatcher-audit','selectors','output'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--adapter-sha256',required=True);a=p.parse_args()
    try:
        if a.output.exists():raise ValueError('Fresh outside-Git output required')
        if sha(a.adapter)!=a.adapter_sha256:raise ValueError('Account adapter tool hash mismatch')
        project=a.project.resolve();output=a.output.resolve();root=ET.parse(project).getroot()
        items=list(root.iter('Compile'));paths=[]
        for item in items:
            path=Path(item.get('Include',''));paths.append((path if path.is_absolute() else project.parent/path).resolve())
        selected={}
        for name in NAMES:
            matches=[(item,path) for item,path in zip(items,paths) if path.name==Path(name).name]
            if len(matches)!=1:raise ValueError('Missing/ambiguous protected source '+name)
            selected[name]=matches[0]
        for name,(item,path) in selected.items():
            target=output/'selected'/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(path.read_bytes())
        command=[sys.executable,str(a.adapter.resolve()),'--upstream',str(a.upstream_root.resolve()),'--dispatcher-audit',str(a.dispatcher_audit.resolve()),'--selectors',str(a.selectors.resolve()),'--source-overlay',str(output/'selected'),'--output',str(output/'protected')]
        subprocess.run(command,check=True)
        for name,(item,path) in selected.items():item.set('Include',str(output/'protected/source'/name))
        group=ET.SubElement(root,'ItemGroup')
        for path in (output/'protected/EHRSourceAccountPolicy.cs',output/'protected/source/EHRProtectedLobbyDirectoryOption.cs'):
            if not path.is_file():raise ValueError('Protected policy supplement missing')
            if any(p.name==path.name for p in paths):raise ValueError('Policy was already added')
            ET.SubElement(group,'Compile',Include=str(path))
        for item,path in zip(items,paths):
            if not Path(item.get('Include')).is_absolute():item.set('Include',str(path))
        ET.indent(root);ET.ElementTree(root).write(output/'EHR.csproj',encoding='unicode')
        report={'schema':'ehr.account-protected-source-join.v1','inputProject':str(project),'inputProjectSha256':sha(project),'adapterSha256':sha(a.adapter),'selectedInputs':{name:{'path':str(path),'sha256':sha(path)} for name,(item,path) in selected.items()},'MainLoadExecuted':False}
        (output/'source-join.json').write_text(json.dumps(report,indent=2)+'\n')
    except (OSError,ValueError,ET.ParseError,subprocess.CalledProcessError) as error:p.exit(2,str(error)+'\n')
    return 0
if __name__=='__main__':raise SystemExit(main())
