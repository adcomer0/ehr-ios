#!/usr/bin/env python3
"""Append pinned startup adaptations to the complete JSON-ready source project.

This original join tool never executes the plugin, changes upstream files, or
downloads a game assembly. The output is a local build-input artifact.
"""
from __future__ import annotations
import argparse,hashlib,json,importlib.util
from pathlib import Path
import xml.etree.ElementTree as ET
import adapt_source_startup as startup

def digest(data):return hashlib.sha256(data).hexdigest()
def prepare(project,output,application,canonical,registration_adapter,registration_adapter_sha256):
    if output.exists():raise ValueError('Fresh output directory required')
    root=ET.parse(project).getroot();items=list(root.iter('Compile'))
    paths=[]
    for item in items:
        path=Path(item.get('Include',''))
        if not path.is_absolute():path=project.parent/path
        paths.append(path.resolve())
    # The input must already contain the actual production bridge and JSON source
    # context, not a compiler-only coroutine placeholder or reflection fallback.
    for required in ('ProductionCoroutines.cs','EHRPortableJsonContext.cs','SourcePatchOwner.cs','EHRSourceApplication.cs','NativePatchTargets.cs'):
        if sum(p.name==required for p in paths)!=1:raise ValueError('Missing/duplicate production source '+required)
    output.mkdir(parents=True)
    changes=[]
    selections={'OptionHolder.cs':'options','EnumHelper.cs':'enum-helper','Commander.cs':'role-enum','Telekinetic.cs':'role-enum'}
    for basename,kind in selections.items():
        selected=[(item,path) for item,path in zip(items,paths) if path.name==basename]
        if len(selected)!=1:raise ValueError('Ambiguous source '+basename)
        item,path=selected[0];data=path.read_bytes();result,proof=startup.transform(data,digest(data),kind)
        target=output/'source'/basename;target.parent.mkdir(exist_ok=True);target.write_bytes(result)
        proof.update(input=str(path),output=str(target));target.with_suffix('.cs.provenance.json').write_text(json.dumps(proof,indent=2)+'\n')
        item.set('Include',str(target));changes.append(proof)
    for basename in ('EHRSourceApplication.cs','SourcePatchOwner.cs'):
        match=[item for item,path in zip(items,paths) if path.name==basename]
        replacement=application/'managed'/basename
        if not replacement.is_file():raise ValueError('Application source missing')
        match[0].set('Include',str(replacement))
    # These production exports are newer than the all-seven component stage.
    runtime=canonical/'managed/SourceReuse/Facades/SourceComponentRuntime.cs'
    selected=[item for item,path in zip(items,paths) if path.name=='SourceComponentRuntime.cs']
    if len(selected)!=1 or not runtime.is_file():raise ValueError('Production component runtime selection is ambiguous/missing')
    selected[0].set('Include',str(runtime))
    signature=canonical/'managed/SourcePort/NativePatchSignature.cs'
    if not signature.is_file():raise ValueError('Production native signature export missing')
    if not any(path.name==signature.name for path in paths):ET.SubElement(ET.SubElement(root,'ItemGroup'),'Compile',Include=str(signature))
    # The official all-client MCI GUID excludes vanilla clients. This explicit
    # host-only adaptation is supplied/pinned by the owner of the native build.
    if digest(registration_adapter.read_bytes())!=registration_adapter_sha256:raise ValueError('Host-only adapter tool hash mismatch')
    spec=importlib.util.spec_from_file_location('host_only_registration_adapter',registration_adapter)
    adapter=importlib.util.module_from_spec(spec);spec.loader.exec_module(adapter)
    selected=[(item,path) for item,path in zip(items,paths) if path.name=='AmciRegistration.cs']
    if len(selected)!=1:raise ValueError('Ambiguous host registration source')
    item,path=selected[0];data=path.read_bytes();result,proof=adapter.transform(data,digest(data))
    target=output/'source/AmciRegistration.cs';target.write_bytes(result);item.set('Include',str(target))
    proof.update(input=str(path),output=str(target));changes.append(proof)
    target.with_suffix('.cs.provenance.json').write_text(json.dumps(proof,indent=2)+'\n')
    # Resolve unchanged relative items against the caller's input project.
    for item,path in zip(items,paths):
        if not Path(item.get('Include')).is_absolute():item.set('Include',str(path))
    # Resource paths are expanded and named by build_source_application.capture.
    for item in root.iter('EmbeddedResource'):
        value=item.get('Include','')
        if value and not Path(value).is_absolute():item.set('Include',str(project.parent/value))
    ET.indent(root);ET.ElementTree(root).write(output/'EHR.csproj',encoding='unicode')
    report={'schema':'ehr.source-startup-overlay.v1','inputProject':str(project),'inputProjectSha256':digest(project.read_bytes()),'changes':changes,'MainLoadExecuted':False,'sourceApplicationSha256':digest((application/'managed/EHRSourceApplication.cs').read_bytes())}
    (output/'startup-overlay.json').write_text(json.dumps(report,indent=2)+'\n')
    return report
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--application-root',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--canonical-root',type=Path,required=True);p.add_argument('--host-only-adapter',type=Path,required=True);p.add_argument('--host-only-adapter-sha256',required=True);a=p.parse_args()
    try:prepare(a.project.resolve(),a.output.resolve(),a.application_root.resolve(),a.canonical_root.resolve(),a.host_only_adapter.resolve(),a.host_only_adapter_sha256)
    except (OSError,ValueError,ET.ParseError) as error:p.exit(2,str(error)+'\n')
    return 0
if __name__=='__main__':raise SystemExit(main())
