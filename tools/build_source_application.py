#!/usr/bin/env python3
"""Capture/rebuild a pinned full-source NativeAOT item manifest; no base game DLLs.

Generated manifests belong outside source Git: they contain caller-provided local
paths and hashes. This original tool contains no game content or private paths.
"""
from __future__ import annotations
import argparse,hashlib,json,os,subprocess,re
from pathlib import Path
import xml.etree.ElementTree as ET

COMMIT='ce23f0d050f617a59507e5bb0fbfff751d4b5134'
PACKAGES={'BepInEx.Core':'6.0.0-be.785','HarmonyX':'2.10.2','JetBrains.Annotations':'2026.2.0','GitInfo':'3.3.4'}
REQUIRED_EXPORTS=('ehr_action_bind_families','ehr_action_bind_gateway','ehr_complex_delegate_bind_gateway','ehr_generated_bind_engine_colors','ehr_generated_bind_extensions','ehr_generated_bind_gateway','ehr_generated_bind_lifetime','ehr_generated_bind_methods','ehr_generated_bind_reflection','ehr_generated_bind_source_components','ehr_generated_bind_type_names','ehr_generated_source_component_profile_v1','ehr_original_bind_gateway','ehr_source_application_bind_v1','ehr_source_application_load_v1','ehr_source_application_prepare_v1','ehr_source_application_status_v1','ehr_source_bind_coroutines_v1','ehr_source_bind_patch_host','ehr_source_bind_patch_targets_v1','ehr_source_host_bind_v1','ehr_touch_ui_bind_v1','ehr_typed_action_bind_gateway','ehr_source_application_copy_error_v1','ehr_source_patch_dispatch_v2','ehr_source_patch_signature_v1','ehr_source_patch_failure_v1','ehr_source_json_self_test_v1','ehr_source_coroutines_self_test','ehr_source_unity_action_self_test')
def required_exports(native_binder=None):
    result=set(REQUIRED_EXPORTS)
    if native_binder is not None:
        source=native_binder.read_text()
        # Only full-AOT-module lookups are exports of this library. The binder
        # also names native gateway functions offered TO the managed module.
        result.update(re.findall(r'(?:fullExport|bindTable)\(\s*"(ehr_[A-Za-z0-9_]+)"',source))
        result.update(re.findall(r'required<[^;\n]+>\(\s*"(ehr_[A-Za-z0-9_]+)"',source))
    return sorted(result)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def resolved(value,base):
    p=Path(value)
    return (base/p).resolve() if not p.is_absolute() else p.resolve()
def capture(project,upstream):
    project=project.resolve();upstream=upstream.resolve()
    observed=subprocess.check_output(['git','-C',str(upstream),'rev-parse','HEAD'],text=True).strip()
    if observed!=COMMIT:raise ValueError('Upstream commit pin mismatch')
    root=ET.parse(project).getroot();sources=[];resources=[];seen=set();packages={}
    tracked=set(subprocess.check_output(['git','-C',str(upstream),'ls-files','-z','--','Resources'],text=True).split('\0'))
    if list(root.iter('Reference')) or list(root.iter('ProjectReference')):raise ValueError('Only exact public PackageReferences are allowed; no game reference DLLs')
    for item in root.iter('Compile'):
        value=item.get('Include','')
        if not value or any(char in value for char in '*?$'):raise ValueError('Compile paths must be explicit')
        path=resolved(value,project.parent)
        if path.suffix!='.cs' or not path.is_file() or path in seen:raise ValueError('Missing/duplicate/non-CSharp compile item')
        if path.name in ('UnsupportedCompileHost.cs','UnboundCoroutine.cs'):raise ValueError('Compiler-only unsupported host cannot enter production manifest')
        seen.add(path);sources.append({'path':str(path),'sha256':sha(path)})
    for item in root.iter('PackageReference'):
        name,version=item.get('Include'),item.get('Version')
        if name not in PACKAGES or version!=PACKAGES[name]:raise ValueError('Unreviewed dependency '+str(name))
        packages[name]=version
    for item in root.iter('EmbeddedResource'):
        value=item.get('Include','').replace('\\','/')
        if value.endswith('/**'):
            directory=resolved(value[:-3],project.parent)
            for path in sorted(directory.rglob('*')):
                if not path.is_file():continue
                if directory!=upstream/'Resources':raise ValueError('Only pinned upstream EHR resources may be globbed')
                if path.is_symlink() or path.relative_to(upstream).as_posix() not in tracked:raise ValueError('Untracked/symlink resource input')
                relative=path.relative_to(directory).as_posix()
                # Match the original EHR RootNamespace/default resource naming,
                # rather than preserve a staging %(RecursiveDir) slash mistake.
                resources.append({'path':str(path.resolve()),'sha256':sha(path),'logicalName':'EHR.Resources.'+relative.replace('/','.')})
        elif value:
            raw=Path(value);raw=raw if raw.is_absolute() else project.parent/raw
            path=raw.resolve();logical=item.get('LogicalName')
            try:relative=path.relative_to(upstream/'Resources')
            except ValueError:raise ValueError('Explicit resources must be inside pinned upstream Resources')
            resource_symlink=False
            for candidate in (raw,*raw.parents):
                resource_symlink=resource_symlink or candidate.is_symlink()
                if candidate.resolve()==upstream/'Resources':break
            if resource_symlink or 'Resources/'+relative.as_posix() not in tracked:raise ValueError('Untracked/symlink explicit resource input')
            if not logical or '%' in logical or '$' in logical:raise ValueError('Resource logical names must be exact')
            resources.append({'path':str(path),'sha256':sha(path),'logicalName':logical})
    if not sources or not resources:raise ValueError('Full source and resources are required')
    logicals=[r['logicalName'] for r in resources]
    if len(set(logicals))!=len(logicals):raise ValueError('Duplicate resource logical name')
    return {'schema':'ehr.full-source-inputs.v1','upstreamCommit':COMMIT,'upstreamRoot':str(upstream),'assemblyName':'EHR','defines':['IL2CPP','EHR_ALL_SOURCE_COMPONENTS'],'sources':sources,'resources':resources,'packages':packages,'baseGameDllReferences':False}
def verify(manifest):
    if manifest.get('schema')!='ehr.full-source-inputs.v1' or manifest.get('upstreamCommit')!=COMMIT or manifest.get('assemblyName')!='EHR' or manifest.get('baseGameDllReferences') is not False:raise ValueError('Invalid source manifest identity')
    if manifest.get('defines')!=['IL2CPP','EHR_ALL_SOURCE_COMPONENTS']:raise ValueError('Full component/source configuration required')
    if manifest.get('packages')!=PACKAGES:raise ValueError('Full exact public package pins required')
    if not manifest.get('sources') or not manifest.get('resources'):raise ValueError('Source/resources are required')
    seen=set()
    for item in manifest['sources']+manifest['resources']:
        path=Path(item['path'])
        if not path.is_absolute() or not path.is_file() or sha(path)!=item['sha256']:raise ValueError('Source/resource changed: '+str(path))
        key=(str(path),item.get('logicalName',''))
        if key in seen:raise ValueError('Duplicate manifest item')
        seen.add(key)
    if any(Path(s['path']).suffix!='.cs' for s in manifest['sources']):raise ValueError('Non-CSharp source item')
    if any(Path(s['path']).name in ('UnsupportedCompileHost.cs','UnboundCoroutine.cs') for s in manifest['sources']):raise ValueError('Compiler-only host item')
    names=[r.get('logicalName') for r in manifest['resources']]
    if any(not isinstance(n,str) or not n.startswith('EHR.Resources.') or any(c in n for c in '%$/\\') for n in names) or len(set(names))!=len(names):raise ValueError('Invalid/duplicate exact resource names')
def emit(manifest,output):
    verify(manifest);root=ET.Element('Project',Sdk='Microsoft.NET.Sdk');p=ET.SubElement(root,'PropertyGroup')
    properties={'TargetFramework':'net10.0','AssemblyName':'EHR','RootNamespace':'EHR','LangVersion':'preview','AllowUnsafeBlocks':'true','Nullable':'enable','EnableDefaultCompileItems':'false','EnableDefaultEmbeddedResourceItems':'false','DefineConstants':';'.join(manifest['defines']),'GenerateAssemblyFileVersionAttribute':'false','GenerateAssemblyInformationalVersionAttribute':'false','GenerateAssemblyVersionAttribute':'false','Configurations':'IL2CPP;Release','Version':'8.0.3','PackageVersion':'8.0.3','PublishAot':'true','PublishAotUsingRuntimePack':'true','IsAotCompatible':'true','InvariantGlobalization':'true','DisableRuntimeMarshalling':'true','NativeLib':'Shared','StripSymbols':'true'}
    for k,v in properties.items():ET.SubElement(p,k).text=v
    # GitInfo must inspect the pinned source checkout, never the staging folder.
    ET.SubElement(p,'GitRoot').text=manifest['upstreamRoot']
    g=ET.SubElement(root,'ItemGroup')
    for s in manifest['sources']:ET.SubElement(g,'Compile',Include=s['path'])
    for r in manifest['resources']:ET.SubElement(g,'EmbeddedResource',Include=r['path'],LogicalName=r['logicalName'])
    for k,v in sorted(manifest['packages'].items()):
        attributes={'Include':k,'Version':v}
        if k=='JetBrains.Annotations':attributes['Aliases']='global,JetBrainsAnnotationsNuget'
        ET.SubElement(g,'PackageReference',attributes)
    ET.SubElement(g,'TrimmerRootAssembly',Include='EHR')
    output.parent.mkdir(parents=True,exist_ok=True);ET.indent(root);ET.ElementTree(root).write(output,encoding='unicode')
def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='operation',required=True)
    c=sub.add_parser('capture');c.add_argument('--project',type=Path,required=True);c.add_argument('--upstream-root',type=Path,required=True);c.add_argument('--output',type=Path,required=True)
    b=sub.add_parser('build');b.add_argument('--manifest',type=Path,required=True);b.add_argument('--output',type=Path,required=True);b.add_argument('--dotnet',type=Path,required=True);b.add_argument('--runtime',choices=['ios-arm64','osx-arm64'],default='ios-arm64');b.add_argument('--emit-only',action='store_true');b.add_argument('--native-binder',type=Path,help='Also derive required full-image exports from this current native binder source');b.add_argument('--omit-debug-symbols',action='store_true',help='Omit optional compiler debug symbols to reduce new build storage; preserves existing artifacts')
    a=p.parse_args()
    try:
        if a.operation=='capture':
            manifest=capture(a.project.resolve(),a.upstream_root.resolve());a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(manifest,indent=2)+'\n')
        else:
            manifest=json.loads(a.manifest.read_text());project=a.output/'project/EHR.csproj'
            observed=subprocess.check_output(['git','-C',manifest['upstreamRoot'],'rev-parse','HEAD'],text=True).strip()
            if observed!=COMMIT:raise ValueError('GitInfo upstream root no longer matches the source pin')
            emit(manifest,project)
            if a.emit_only:return 0
            publish=a.output/'publish'
            if publish.exists() and any(publish.iterdir()):raise ValueError('Fresh publish output required; stale artifacts are not accepted')
            env=dict(os.environ,DOTNET_CLI_TELEMETRY_OPTOUT='1',DOTNET_GENERATE_ASPNET_CERTIFICATE='false')
            command=[str(a.dotnet),'publish',str(project),'-c','IL2CPP','-r',a.runtime,'-p:NativeLib=Shared','-o',str(a.output/'publish')]
            if a.omit_debug_symbols:command.append('-p:DebugType=none')
            with (a.output/'publish.log').open('w') as log:result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT)
            # A concurrent edit to a source checkout invalidates this build's
            # identity; do not report a successful pinned artifact in that case.
            verify(manifest)
            report={'success':result.returncode==0,'runtime':a.runtime,'manifestSha256':sha(a.manifest),'sourceCount':len(manifest['sources']),'resourceCount':len(manifest['resources']),'baseGameDllReferences':False,'MainLoadExecuted':False,'debugSymbolsOmitted':a.omit_debug_symbols}
            library=a.output/'publish/EHR.dylib'
            if result.returncode==0 and not library.is_file():raise ValueError('NativeAOT reported success without required EHR.dylib')
            if library.exists():
                symbols=set(subprocess.check_output(['xcrun','nm','-gjU',str(library)],text=True).splitlines())
                required=required_exports(a.native_binder)
                missing=[name for name in required if '_'+name not in symbols]
                if missing:raise ValueError('Required production native exports absent: '+','.join(missing))
                report.update(library=str(library),librarySha256=sha(library),requiredProductionExports=required)
                if a.native_binder:report['nativeBinderSourceSHA256']=sha(a.native_binder)
            (a.output/'build-proof.json').write_text(json.dumps(report,indent=2)+'\n');return result.returncode
    except (OSError,ValueError,KeyError,ET.ParseError,subprocess.CalledProcessError) as error:p.exit(2,str(error)+'\n')
    return 0
if __name__=='__main__':raise SystemExit(main())
