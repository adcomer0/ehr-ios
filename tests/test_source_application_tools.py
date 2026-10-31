from __future__ import annotations
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import sys
import subprocess
import json
import io
from contextlib import redirect_stderr
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
def module(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'tools'/(name+'.py'))
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
build=module('build_source_application');startup=module('adapt_source_startup');join=module('prepare_source_application')
def digest(data):return hashlib.sha256(data).hexdigest()

class SourceManifestTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.upstream=self.root/'source';self.resources=self.upstream/'Resources'
        (self.resources/'Images').mkdir(parents=True)
        (self.resources/'Images/Icon.png').write_bytes(b'own fixture image')
        (self.resources/'en.json').write_text('{}')
        self.cs=self.root/'Bootstrap.cs';self.cs.write_text('class OwnBootstrap {}')
        self.project=self.root/'Full.csproj'
        p=ET.Element('Project');g=ET.SubElement(p,'ItemGroup')
        ET.SubElement(g,'Compile',Include=str(self.cs))
        ET.SubElement(g,'EmbeddedResource',Include=str(self.resources/'**'))
        for k,v in build.PACKAGES.items():ET.SubElement(g,'PackageReference',Include=k,Version=v)
        ET.ElementTree(p).write(self.project)
        self.mock=patch.object(build.subprocess,'check_output',side_effect=[build.COMMIT,'Resources/Images/Icon.png\0Resources/en.json\0'])
        self.mock.start()
    def tearDown(self):self.mock.stop();self.tmp.cleanup()
    def capture(self):return build.capture(self.project,self.upstream)
    def test_exact_resources_and_aliases(self):
        manifest=self.capture();build.emit(manifest,self.root/'out/EHR.csproj')
        root=ET.parse(self.root/'out/EHR.csproj').getroot()
        self.assertEqual({r['logicalName'] for r in manifest['resources']},{'EHR.Resources.Images.Icon.png','EHR.Resources.en.json'})
        self.assertEqual(root.findtext('PropertyGroup/GitRoot'),str(self.upstream.resolve()))
        self.assertEqual(root.findtext('PropertyGroup/GitBranch'),'main')
        self.assertEqual(root.find('ItemGroup/PackageReference[@Include="JetBrains.Annotations"]').get('Aliases'),'global,JetBrainsAnnotationsNuget')
        self.assertEqual(root.findtext('PropertyGroup/PublishAotUsingRuntimePack'),'true')
        self.assertFalse(list(root.iter('Reference')))
    def test_changed_source_fails_closed(self):
        manifest=self.capture();self.cs.write_text('class Modified {}')
        with self.assertRaisesRegex(ValueError,'changed'):build.verify(manifest)
    def test_duplicate_logical_name_rejected(self):
        manifest=self.capture();manifest['resources'][1]['logicalName']=manifest['resources'][0]['logicalName']
        with self.assertRaisesRegex(ValueError,'resource names'):build.verify(manifest)
    def test_game_reference_rejected(self):
        root=ET.parse(self.project);ET.SubElement(root.getroot(),'Reference',Include='Assembly-CSharp');root.write(self.project)
        with self.assertRaisesRegex(ValueError,'no game reference'):self.capture()
    def test_untracked_resource_rejected(self):
        (self.resources/'secret.txt').write_text('own fixture')
        with self.assertRaisesRegex(ValueError,'Untracked'):self.capture()
    def test_compile_only_host_rejected(self):
        invalid=self.root/'UnsupportedCompileHost.cs';invalid.write_text('class Own {}')
        root=ET.parse(self.project);root.find('.//Compile').set('Include',str(invalid));root.write(self.project)
        with self.assertRaisesRegex(ValueError,'unsupported host'):self.capture()
    def test_wrong_package_rejected(self):
        root=ET.parse(self.project);root.find('.//PackageReference').set('Version','0.0.1');root.write(self.project)
        with self.assertRaisesRegex(ValueError,'Unreviewed'):self.capture()
    def test_missing_package_rejected(self):
        manifest=self.capture();manifest['packages'].pop('GitInfo')
        with self.assertRaisesRegex(ValueError,'Full exact'):build.verify(manifest)
    def test_dynamic_binder_export_names_cannot_be_omitted(self):
        binder=self.root/'Binder.mm';binder.write_text('bindTable("ehr_new_required_family",x); required<Fn>("ehr_action_bind_families"); if(!strcmp(name,"ehr_runtime_find_class")) return native;')
        required=build.required_exports(binder)
        self.assertIn('ehr_new_required_family',required)
        self.assertIn('ehr_source_coroutines_self_test',required)
        self.assertEqual(required.count('ehr_action_bind_families'),1)
        self.assertNotIn('ehr_runtime_find_class',required)
    def test_explicit_outside_resource_is_rejected(self):
        outside=self.root/'Outside.dat';outside.write_bytes(b'own outside fixture')
        tree=ET.parse(self.project);item=tree.find('.//EmbeddedResource');item.set('Include',str(outside));item.set('LogicalName','EHR.Resources.Outside.dat');tree.write(self.project)
        with self.assertRaisesRegex(ValueError,'inside pinned'):self.capture()
    def test_explicit_tracked_resource_is_accepted(self):
        tree=ET.parse(self.project);item=tree.find('.//EmbeddedResource');item.set('Include',str(self.resources/'Images/Icon.png'));item.set('LogicalName','EHR.Resources.Images.Icon.png');tree.write(self.project)
        manifest=self.capture();build.verify(manifest);self.assertEqual(len(manifest['resources']),1)
    def test_explicit_symlink_resource_is_rejected(self):
        link=self.resources/'Alias.png';link.symlink_to(self.resources/'Images/Icon.png')
        tree=ET.parse(self.project);item=tree.find('.//EmbeddedResource');item.set('Include',str(link));item.set('LogicalName','EHR.Resources.Alias.png');tree.write(self.project)
        with self.assertRaisesRegex(ValueError,'symlink explicit'):self.capture()
    def test_success_without_native_artifact_fails_closed(self):
        manifest=self.capture();path=self.root/'manifest.json';path.write_text(json.dumps(manifest));output=self.root/'build';errors=io.StringIO()
        argv=['build_source_application.py','build','--manifest',str(path),'--output',str(output),'--dotnet',str(self.root/'own-fake-dotnet')]
        with patch.object(sys,'argv',argv),patch.object(build,'verify_upstream_release',return_value=build.release_identity_policy()),patch.object(build.subprocess,'run',return_value=SimpleNamespace(returncode=0)),redirect_stderr(errors):
            with self.assertRaises(SystemExit) as exit:build.main()
        self.assertEqual(exit.exception.code,2);self.assertIn('without required EHR.dylib',errors.getvalue());self.assertFalse((output/'build-proof.json').exists())
    def test_existing_publish_artifact_is_never_reused(self):
        manifest=self.capture();path=self.root/'manifest.json';path.write_text(json.dumps(manifest));output=self.root/'build';(output/'publish').mkdir(parents=True);(output/'publish/EHR.dylib').write_bytes(b'own stale artifact');errors=io.StringIO()
        argv=['build_source_application.py','build','--manifest',str(path),'--output',str(output),'--dotnet',str(self.root/'own-fake-dotnet')]
        with patch.object(sys,'argv',argv),patch.object(build,'verify_upstream_release',return_value=build.release_identity_policy()),patch.object(build.subprocess,'run') as run,redirect_stderr(errors):
            with self.assertRaises(SystemExit) as exit:build.main()
        self.assertEqual(exit.exception.code,2);run.assert_not_called();self.assertIn('stale artifacts',errors.getvalue())

class AlignmentTests(unittest.TestCase):
    def test_all_retained_relative_inputs_rebase_and_generated_variant_stays(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();source=root/'input';source.mkdir();canonical=root/'canonical';helpers=canonical/'managed/SourceReuse/Facades';helpers.mkdir(parents=True);app=root/'app';(app/'managed').mkdir(parents=True)
            tree=ET.Element('Project');group=ET.SubElement(tree,'ItemGroup')
            for name in ('ActionRuntime.cs','TypedActionRuntime.cs','NativeEngineColors.cs','Untouched.cs','GeneratedFacades.g.cs'):
                (source/name).write_text('// selected '+name);ET.SubElement(group,'Compile',Include=name)
                if name!='Untouched.cs':(helpers/name).write_text('// canonical '+name)
            (helpers/'HtmlColorCompatibility.cs').write_text('// helper')
            (app/'managed/SourceUnityAction.cs').write_text('// source helper')
            (source/'Resources').mkdir();(source/'Resources/test.png').write_bytes(b'own')
            ET.SubElement(group,'EmbeddedResource',Include='Resources/test.png',LogicalName='EHR.Resources.test.png')
            project=source/'Full.csproj';ET.ElementTree(tree).write(project)
            result=subprocess.run([sys.executable,str(ROOT/'tools/align_shared_runtime.py'),'--project',str(project),'--canonical-root',str(canonical),'--application-root',str(app),'--output',str(root/'out')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            emitted=ET.parse(root/'out/EHR.csproj');includes=[n.get('Include') for n in emitted.findall('.//Compile')]
            self.assertIn(str(source/'Untouched.cs'),includes)
            self.assertIn(str(source/'GeneratedFacades.g.cs'),includes)
            self.assertNotIn(str(helpers/'GeneratedFacades.g.cs'),includes)
            self.assertEqual(emitted.find('.//EmbeddedResource').get('Include'),str(source/'Resources/test.png'))

class StartupOverlayTests(unittest.TestCase):
    def test_options_milestones_and_no_steam(self):
        source=b'void Own() {\n        AddSteamID.AddSteamAppIdFile();\n        IsLoaded = true;\n        PostLoadTasks();\n}\n'
        output,report=startup.transform(source,digest(source),'options')
        self.assertNotIn(b'AddSteamAppIdFile()',output)
        self.assertIn(b'IsLoaded = true;\n        global::EHR.EHRSourceApplication.ObserveOptionsLoaded',output)
        self.assertIn(b'PostLoadTasks();\n        global::EHR.EHRSourceApplication.ObserveOptionsPostLoad();',output)
        self.assertEqual(report['kind'],'options')
    def test_original_crlf_preserved(self):
        source=b'        AddSteamID.AddSteamAppIdFile();\r\n        IsLoaded = true;\r\n        PostLoadTasks();\r\n'
        output,_=startup.transform(source,digest(source),'options')
        self.assertNotIn(b'\n',output.replace(b'\r\n',b''))
    def test_hash_and_anchor_fail_closed(self):
        with self.assertRaisesRegex(ValueError,'hash mismatch'):startup.transform(b'x','0'*64,'options')
        with self.assertRaisesRegex(ValueError,'anchor mismatch'):startup.transform(b'x',digest(b'x'),'options')
    def test_closed_enum_apis(self):
        source=b'public static T[] GetValues<T>() => (T[])Enum.GetValues(typeof(T));\npublic static string[] GetNames<T>() => Enum.GetNames(typeof(T));'
        output,_=startup.transform(source,digest(source),'enum-helper')
        self.assertIn(b'where T : struct, Enum => Enum.GetValues<T>()',output)
        self.assertIn(b'where T : struct, Enum => Enum.GetNames<T>()',output)
        source=b'int Own() => Enum.GetValues(typeof(Mode)).Length;'
        output,_=startup.transform(source,digest(source),'role-enum')
        self.assertIn(b'Enum.GetValues<Mode>().Length',output)

class ProductionJoinTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name).resolve()
        self.canonical=self.root/'native';self.application=self.root/'application'
        self.paths={}
        p=ET.Element('Project');g=ET.SubElement(p,'ItemGroup')
        for name in ('ProductionCoroutines.cs','EHRPortableJsonContext.cs','SourcePatchOwner.cs','EHRSourceApplication.cs','NativePatchTargets.cs','SourceComponentRuntime.cs','OptionHolder.cs','EnumHelper.cs','Commander.cs','Telekinetic.cs','AmciRegistration.cs'):
            path=self.root/'input'/name;path.parent.mkdir(exist_ok=True);path.write_text('class Own {}')
            self.paths[name]=path;ET.SubElement(g,'Compile',Include=str(path))
        self.paths['OptionHolder.cs'].write_text('        AddSteamID.AddSteamAppIdFile();\n        IsLoaded = true;\n        PostLoadTasks();\n')
        self.paths['EnumHelper.cs'].write_text('public static T[] GetValues<T>() => (T[])Enum.GetValues(typeof(T));\npublic static string[] GetNames<T>() => Enum.GetNames(typeof(T));')
        for name in ('Commander.cs','Telekinetic.cs'):self.paths[name].write_text('Enum.GetValues(typeof(Mode)).Length')
        self.paths['AmciRegistration.cs'].write_text('ALL_CLIENT')
        for name in ('SourcePatchOwner.cs','EHRSourceApplication.cs'):
            path=self.application/'managed'/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('class OwnProduction {}')
        self.component=self.canonical/'managed/SourceReuse/Facades/SourceComponentRuntime.cs';self.component.parent.mkdir(parents=True);self.component.write_text('// production profile export fixture')
        self.signature=self.canonical/'managed/SourcePort/NativePatchSignature.cs';self.signature.parent.mkdir(parents=True);self.signature.write_text('// signature export fixture')
        self.adapter=self.root/'registration.py';self.adapter.write_text('def transform(data,expected):\n return data.replace(b"ALL_CLIENT",b"HOST_ONLY"),{"profile":"host-only"}\n')
        self.project=self.root/'Full.csproj';ET.ElementTree(p).write(self.project)
    def tearDown(self):self.tmp.cleanup()
    def run_join(self,output):return join.prepare(self.project,output,self.application,self.canonical,self.adapter,digest(self.adapter.read_bytes()))
    def test_production_exports_and_host_only_overlay_are_included(self):
        before={p:p.read_bytes() for p in self.paths.values()}
        self.run_join(self.root/'out');root=ET.parse(self.root/'out/EHR.csproj')
        includes=[Path(n.get('Include')) for n in root.findall('.//Compile')]
        self.assertIn(self.signature,includes);self.assertIn(self.component,includes)
        self.assertNotIn(self.paths['SourceComponentRuntime.cs'],includes)
        self.assertEqual((self.root/'out/source/AmciRegistration.cs').read_text(),'HOST_ONLY')
        self.assertIn('ObserveOptionsLoaded',(self.root/'out/source/OptionHolder.cs').read_text())
        self.assertEqual(before,{p:p.read_bytes() for p in self.paths.values()})
    def test_missing_production_export_source_rejected(self):
        self.signature.unlink()
        with self.assertRaisesRegex(ValueError,'signature export missing'):self.run_join(self.root/'out')
    def test_pinned_adapter_required(self):
        with self.assertRaisesRegex(ValueError,'tool hash mismatch'):join.prepare(self.project,self.root/'out',self.application,self.canonical,self.adapter,'0'*64)

if __name__=='__main__':unittest.main()
