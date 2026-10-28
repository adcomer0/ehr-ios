#!/usr/bin/env python3
"""Align reviewed shared own implementations without replacing source facades."""
from __future__ import annotations
import argparse,hashlib,json
from pathlib import Path
import xml.etree.ElementTree as ET

SHARED={'FacadeRuntime.cs','LiveArrays.cs','LiveLists.cs','NativeLifetime.cs','NativeValues.cs','LiveObjects.cs','LiveDictionaries.cs','ManagedPredicates.cs','LiveSequenceBuffers.cs','NativeTypeNames.cs','NativeMethods.cs','NativeConstructors.cs','NativeGenericMethods.cs','NativeReflectedCalls.cs','NativeParams.cs','NativeEngineColors.cs','LiveSets.cs','ActionRuntime.cs','LiveAsyncHandles.cs','TypedActionRuntime.cs','LiveSystemTypes.cs','OriginalRuntime.cs','NativeStateMachineView.cs','NativeCallbackScope.cs','ComplexDelegateRuntime.cs','NativeTouchGUI.cs','ProductionCoroutines.cs','SourceComponentRuntime.cs','SourceComponentConstruction.cs','SourceStateRegistry.cs','SourceComponentFacades.cs','SourceSceneEvents.cs','SourceComponentCatalog.g.cs','SourceLifecycleProbe.cs','NativeSourceHost.cs','SourceCompatibility.cs','SourceHostSelfTest.cs','SourcePluginHost.cs','SourceSignedUpdates.cs','NativeSignedUpdates.cs','SourcePatchOwner.cs','EHRSourceApplication.cs','EHRSourceAccountPolicy.cs'}
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('project','canonical-root','application-root','output'):p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args()
    try:
        project=a.project.resolve();output=a.output.resolve();canonical=a.canonical_root.resolve()
        if output.exists():raise ValueError('Fresh output required')
        paths={}
        for path in (canonical/'managed').rglob('*.cs'):
            if 'obj' in path.parts or 'bin' in path.parts:continue
            paths.setdefault(path.name,[]).append(path)
        root=ET.parse(project).getroot();rows=[];selected=set()
        for item in root.iter('Compile'):
            value=item.get('Include')
            if not value or '$(' in value:raise ValueError('Explicit resolved source paths required')
            path=Path(value);path=(path if path.is_absolute() else project.parent/path).resolve()
            item.set('Include',str(path))
            if path.name not in SHARED:continue
            candidates=paths.get(path.name,[])
            if len(candidates)!=1:raise ValueError('Ambiguous/missing canonical shared implementation '+path.name)
            target=candidates[0];rows.append({'name':path.name,'selected':str(path),'selectedSHA256':sha(path),'canonical':str(target),'canonicalSHA256':sha(target),'changed':sha(path)!=sha(target)})
            item.set('Include',str(target));selected.add(path.name)
        if not {'ActionRuntime.cs','TypedActionRuntime.cs','NativeEngineColors.cs'}.issubset(selected):raise ValueError('Required shared runtime sources missing')
        group=ET.SubElement(root,'ItemGroup')
        for target in (canonical/'managed/SourceReuse/Facades/HtmlColorCompatibility.cs',a.application_root.resolve()/'managed/SourceUnityAction.cs'):
            if not target.is_file():raise ValueError('Required production helper missing')
            if target.name in selected or any(Path(n.get('Include')).name==target.name for n in root.iter('Compile')):raise ValueError('Duplicate helper')
            ET.SubElement(group,'Compile',Include=str(target))
        for item in root.iter('EmbeddedResource'):
            value=item.get('Include')
            if not value:continue
            if '$(' in value:raise ValueError('Resolved resource paths required')
            path=Path(value);item.set('Include',str((path if path.is_absolute() else project.parent/path).resolve()))
        output.mkdir(parents=True);ET.indent(root);ET.ElementTree(root).write(output/'EHR.csproj',encoding='unicode')
        (output/'shared-runtime-audit.json').write_text(json.dumps({'schema':'ehr.shared-runtime-alignment.v1','inputProject':str(project),'inputProjectSHA256':sha(project),'rows':rows,'changedCount':sum(r['changed'] for r in rows),'generatedSourceFacadeReplaced':False,'MainLoadExecuted':False},indent=2)+'\n')
    except (OSError,ValueError,ET.ParseError) as error:p.exit(2,str(error)+'\n')
    return 0
if __name__=='__main__':raise SystemExit(main())
