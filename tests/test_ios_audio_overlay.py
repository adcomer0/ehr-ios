from __future__ import annotations
import hashlib,importlib.util,json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import xml.etree.ElementTree as E

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('audio',ROOT/'tools/prepare_ios_audio_behavior.py');audio=importlib.util.module_from_spec(spec);spec.loader.exec_module(audio)

class AudioOverlayTests(unittest.TestCase):
    def fixture(self,eol):
        return eol.join([
            b'namespace Own;',
            b'    private static readonly string SoundsPath = $"{Environment.CurrentDirectory.Replace(@"\\", "/")}/BepInEx/resources/";',
            b'    void RPC(){ /* own source command body */ }',
            b'    void Play(){',
            b'            if (!Constants.ShouldPlaySfx() || !Main.EnableCustomSoundEffect.Value || !OperatingSystem.IsWindows()) return;',
            b'            WindowsOriginal();',b'    }',b'    void OriginalLoader(){ /* own witness */ }',b''])
    def test_preserves_rpc_and_windows_tail(self):
        for eol in (b'\n',b'\r\n'):
            source=self.fixture(eol);result=audio.transform(source,hashlib.sha256(source).hexdigest())
            self.assertIn(b'if (!Constants.ShouldPlaySfx() || !Main.EnableCustomSoundEffect.Value) return;',result)
            self.assertIn(b'if (!OperatingSystem.IsWindows()) return;',result)
            self.assertEqual(source[source.index(b'            WindowsOriginal();'):],result[result.index(b'            WindowsOriginal();'):])
            self.assertIn(b'void RPC(){ /* own source command body */ }',result)
            self.assertEqual(result.count(b'SourceAudioPlayback.Play(sound, volume, pitch);'),1)
            if eol==b'\r\n':self.assertNotIn(b'\n',result.replace(b'\r\n',b''))
    def test_input_pin_and_exact_anchor_fail_closed(self):
        source=self.fixture(b'\n')
        with self.assertRaisesRegex(ValueError,'hash mismatch'):audio.transform(source,'0'*64)
        changed=source.replace(b'Constants.ShouldPlaySfx()',b'Changed()')
        with self.assertRaisesRegex(ValueError,'anchors'):audio.transform(changed,hashlib.sha256(changed).hexdigest())
    def test_bom_preserved(self):
        source=b'\xef\xbb\xbf'+self.fixture(b'\n')
        self.assertTrue(audio.transform(source,hashlib.sha256(source).hexdigest()).startswith(b'\xef\xbb\xbf'))
    def proof(self):
        return {'schema':'ehr.full-source-audio-proof.v1','accountActionsPerformed':False,'playbackVolume':0,
            'ehr_source_audio_data_probe_v1':{'status':0,'words':list(audio.DATA_WORDS)},
            'ehr_source_muted_sound_probe_v1':{'status':0,'words':list(audio.MUTED_WORDS)}}
    def test_both_complete_actual_proof_vectors_required(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'proof.json';proof=self.proof();path.write_text(json.dumps(proof));audio.proof_gate(path)
            for name in ('ehr_source_audio_data_probe_v1','ehr_source_muted_sound_probe_v1'):
                for index in range(16):
                    bad=self.proof();bad[name]['words'][index]+=1;path.write_text(json.dumps(bad))
                    with self.assertRaisesRegex(ValueError,'both pass exactly'):audio.proof_gate(path)
            for field,value in [('accountActionsPerformed',True),('playbackVolume',0.5),('schema','other')]:
                bad=self.proof();bad[field]=value;path.write_text(json.dumps(bad))
                with self.assertRaises(ValueError):audio.proof_gate(path)

class CurrentHelperSelectionTests(unittest.TestCase):
    def setup_inputs(self,root):
        helpers=root/'managed';helpers.mkdir();source=root/'CustomSounds.cs';source.write_bytes(AudioOverlayTests().fixture(b'\n'))
        for name in ['PcmWaveData.cs','OwnedSoundFiles.cs','SourceAudioPlayback.cs','SourceAudioNames.cs']:(helpers/name).write_text('// own current '+name)
        tree=E.Element('Project');group=E.SubElement(tree,'ItemGroup');E.SubElement(group,'Compile',Include=str(source));project=root/'Input.csproj';E.ElementTree(tree).write(project)
        return helpers,source,project
    def run_prepare(self,root,helpers,source,project):
        with patch.object(audio,'SOUND_SHA',hashlib.sha256(source.read_bytes()).hexdigest()):return audio.prepare(project,root/'out',helpers/'PcmWaveData.cs',helpers=helpers)
    def test_current_helpers_selected_once_without_legacy_upgrade(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();helpers,source,project=self.setup_inputs(root);before=source.read_bytes();emitted=self.run_prepare(root,helpers,source,project)
            paths=[Path(n.get('Include')) for n in E.parse(emitted).iter('Compile')]
            for name in ['PcmWaveData.cs','OwnedSoundFiles.cs','SourceAudioPlayback.cs','SourceAudioNames.cs']:self.assertEqual(paths.count(helpers/name),1)
            report=json.loads((root/'out/audio-overlay.json').read_text());self.assertTrue(report['namesSelected']);self.assertEqual(len(report['selectedHelpers']),4);self.assertFalse(report['iosProductionRouteEnabled']);self.assertEqual(source.read_bytes(),before)
    def test_old_helper_path_replaced_with_current_and_reported(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();helpers,source,project=self.setup_inputs(root);old=root/'old/OwnedSoundFiles.cs';old.parent.mkdir();old.write_text('// previous own helper');tree=E.parse(project);E.SubElement(tree.find('ItemGroup'),'Compile',Include=str(old));tree.write(project)
            emitted=self.run_prepare(root,helpers,source,project);paths=[Path(n.get('Include')) for n in E.parse(emitted).iter('Compile')];self.assertNotIn(old,paths);self.assertEqual(paths.count(helpers/'OwnedSoundFiles.cs'),1)
            report=json.loads((root/'out/audio-overlay.json').read_text());self.assertEqual(report['replacedInputHelpers']['OwnedSoundFiles.cs']['path'],str(old));self.assertEqual(old.read_text(),'// previous own helper')
    def test_conflicting_existing_name_adapter_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();helpers,source,project=self.setup_inputs(root);old=root/'old/SourceAudioNames.cs';old.parent.mkdir();old.write_text('// conflicting own fixture');tree=E.parse(project);E.SubElement(tree.find('ItemGroup'),'Compile',Include=str(old));tree.write(project)
            with self.assertRaisesRegex(ValueError,'Conflicting SourceAudioNames'):self.run_prepare(root,helpers,source,project)
            self.assertFalse((root/'out').exists())
    def test_duplicate_equivalent_names_rejected_before_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();helpers,source,project=self.setup_inputs(root);tree=E.parse(project)
            for folder in ['first','second']:
                path=root/folder/'SourceAudioNames.cs';path.parent.mkdir();path.write_bytes((helpers/path.name).read_bytes());E.SubElement(tree.find('ItemGroup'),'Compile',Include=str(path))
            tree.write(project)
            with self.assertRaisesRegex(ValueError,'Duplicate audio helper'):self.run_prepare(root,helpers,source,project)
            self.assertFalse((root/'out').exists())
    def test_equivalent_existing_names_rebased_once(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();helpers,source,project=self.setup_inputs(root);old=root/'old/SourceAudioNames.cs';old.parent.mkdir();old.write_bytes((helpers/old.name).read_bytes());tree=E.parse(project);E.SubElement(tree.find('ItemGroup'),'Compile',Include=str(old));tree.write(project)
            emitted=self.run_prepare(root,helpers,source,project);paths=[Path(n.get('Include')) for n in E.parse(emitted).iter('Compile')];self.assertNotIn(old,paths);self.assertEqual(paths.count(helpers/'SourceAudioNames.cs'),1)
    def test_missing_current_name_helper_rejected_before_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();helpers,source,project=self.setup_inputs(root);(helpers/'SourceAudioNames.cs').unlink()
            with self.assertRaisesRegex(ValueError,'All four'):self.run_prepare(root,helpers,source,project)
            self.assertFalse((root/'out').exists())

if __name__=='__main__':unittest.main()
