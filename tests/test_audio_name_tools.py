from __future__ import annotations
import importlib.util,tempfile,unittest
from pathlib import Path
import xml.etree.ElementTree as E

ROOT=Path(__file__).resolve().parents[1]
def module(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'tools'/(name+'.py'));result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
fixture=module('prepare_audio_file_fixture');names=module('prepare_audio_names')
class FixtureTests(unittest.TestCase):
    def test_generated_fixture_has_only_explicit_own_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);repo=root/'repo';(repo/'managed').mkdir(parents=True);(repo/'tests').mkdir()
            for path in ['managed/PcmWaveData.cs','managed/OwnedSoundFiles.cs','managed/SourceAudioNames.cs','tests/OwnedSoundFixture.cs','tests/AudioNamesFixture.cs']:(repo/path).write_text('// own fixture')
            for kind,count in [('files',3),('names',4)]:
                out=root/kind;project=fixture.prepare(repo,out,kind);tree=E.parse(project)
                self.assertEqual(len(list(tree.iter('Compile'))),count);self.assertFalse(list(tree.iter('Reference')));self.assertFalse(list(tree.iter('PackageReference')))
                with self.assertRaisesRegex(ValueError,'Fresh'):fixture.prepare(repo,out,kind)
    def test_fixture_missing_input_rejected_before_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            with self.assertRaisesRegex(ValueError,'Adopted own'):fixture.prepare(root,root/'out','names')
            self.assertFalse((root/'out').exists())
    def test_names_refuses_incomplete_or_modified_base_before_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);project=root/'EHR.csproj';tree=E.Element('Project');group=E.SubElement(tree,'ItemGroup');helper=root/'SourceAudioPlayback.cs';helper.write_text('// modified own fixture');E.SubElement(group,'Compile',Include=str(helper));E.ElementTree(tree).write(project)
            with self.assertRaisesRegex(ValueError,'reviewed40'):names.prepare(project,root/'out')
            self.assertFalse((root/'out').exists())
if __name__=='__main__':unittest.main()
