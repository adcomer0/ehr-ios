from pathlib import Path
import hashlib,json,tempfile,unittest
from unittest.mock import patch
from generate_source_adapters import COMMIT,generate
class AdapterTests(unittest.TestCase):
    def setup_files(self,base):
        root=base/'upstream';root.mkdir();project=base/'EHR.csproj'
        files={'Modules/Il2CppHelpers/CastHelper.cs':'original expression compiler',
               'Modules/Il2CppHelpers/ButtonClickCrashFix.cs':'__instance.Pointer != IntPtr.Zero\n__instance.Pointer != IntPtr.Zero',
               'Modules/ExtendedPlayerControl.cs':'using System;\ncatch (Il2CppException e) { }'}
        pins={};items=[]
        for name,text in files.items():
            path=root/name;path.parent.mkdir(exist_ok=True,parents=True);path.write_text(text)
            pins[name]=hashlib.sha256(path.read_bytes()).hexdigest();items.append('<Compile Include="'+str(path)+'"/>')
        project.write_text('<Project><ItemGroup>'+''.join(items)+'</ItemGroup></Project>')
        return root,project,pins
    @patch('generate_source_adapters.subprocess.check_output',return_value=COMMIT)
    def test_three_adapters_preserve_inputs_and_manifest(self,_):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory);root,project,pins=self.setup_files(base);before={p:p.read_bytes() for p in root.rglob('*.cs')}
            result=generate(project,root,base/'out',pins)
            self.assertEqual(len(result['adapters']),3)
            cast=(base/'out/source/CastHelper.cs').read_text();self.assertIn('obj.Cast<T>()',cast);self.assertNotIn('Expression',cast);self.assertNotIn('Pointer',cast)
            self.assertIn('TokenIsValid',(base/'out/source/ButtonClickCrashFix.cs').read_text())
            self.assertIn('NativeGameException',(base/'out/source/ExtendedPlayerControl.cs').read_text())
            self.assertEqual(before,{p:p.read_bytes() for p in before})
    @patch('generate_source_adapters.subprocess.check_output',return_value=COMMIT)
    def test_input_sha_mismatch_fails_closed(self,_):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory);root,project,pins=self.setup_files(base);pins['Modules/Il2CppHelpers/CastHelper.cs']='0'*64
            with self.assertRaisesRegex(ValueError,'SHA pin mismatch'):generate(project,root,base/'out',pins)
    @patch('generate_source_adapters.subprocess.check_output',return_value='wrong')
    def test_commit_mismatch_is_rejected_before_output(self,_):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory);root,project,pins=self.setup_files(base)
            with self.assertRaisesRegex(ValueError,'commit pin mismatch'):generate(project,root,base/'out',pins)
            self.assertFalse((base/'out').exists())
    @patch('generate_source_adapters.subprocess.check_output',return_value=COMMIT)
    def test_changed_pointer_pattern_requires_review(self,_):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory);root,project,pins=self.setup_files(base);path=root/'Modules/Il2CppHelpers/ButtonClickCrashFix.cs';path.write_text('new source pattern')
            pins['Modules/Il2CppHelpers/ButtonClickCrashFix.cs']=hashlib.sha256(path.read_bytes()).hexdigest()
            with self.assertRaisesRegex(ValueError,'pointer pattern changed'):generate(project,root,base/'out',pins)
if __name__=='__main__':unittest.main()
