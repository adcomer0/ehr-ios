"""Owned option/preflight fixtures; no actual game, SDK, signing or device call."""
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
import hashlib
import importlib.util
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
spec=importlib.util.spec_from_file_location('ehr_auth_handoff_builder',ROOT/'tools/build_game_probe.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)

class StopBeforeSourceRead(Exception):pass
class StopBeforeSDKCall(Exception):pass

class AuthHandoffBuilderTests(unittest.TestCase):
    def options(self,root,**overrides):
        values=dict(team_id='ABCDEFGHIJ',bundle_id='org.example.ehrfixture',team_name=None,
            game_app=root/'OwnSource.app',output=root/'Output',full_native_catalog=None,
            full_native_target_map=None,full_thunk_inputs=None,managed_dylib=None,
            iterator_hook_map=None,static_class_hooks=None,full_source_autoload=False,
            eos_login_map=None,platform_sign_in=False,auth_retry_guard_map=None,
            enable_auth_retry_guard=False,game_start_iterator_map=None,profile=root/'OwnProfile',
            destination_id_file=root/'own-destination.local.txt',identity='Own Fixture Identity',build=50)
        values.update(overrides);return SimpleNamespace(**values)
    def reject_before_any_input_or_output(self,overrides,reason):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);args=self.options(root,auth_handoff_map=root/'handoff.json',**overrides)
            with patch.object(builder,'inspect_path') as inspect,patch.object(builder.subprocess,'check_output') as external,patch.object(builder,'run') as run,self.assertRaisesRegex(ValueError,reason):builder.build(args)
            inspect.assert_not_called();external.assert_not_called();run.assert_not_called();self.assertFalse(args.output.exists())
    def test_missing_full_source_rejected_before_any_input_or_output(self):
        self.reject_before_any_input_or_output({},'require the full source profile')
    def test_missing_passive_eos_map_rejected_before_any_input_or_output(self):
        self.reject_before_any_input_or_output({'full_native_catalog':Path('own-catalog.json')},'require --eos-login-map')
    def test_missing_platform_capabilities_rejected_before_any_input_or_output(self):
        self.reject_before_any_input_or_output({'full_native_catalog':Path('own-catalog.json'),'eos_login_map':Path('own-eos.json')},'require --platform-sign-in')
    def test_full_source_contract_inputs_remain_required(self):
        self.reject_before_any_input_or_output({'full_native_catalog':Path('own-catalog.json'),'eos_login_map':Path('own-eos.json'),'platform_sign_in':True},'catalog, pinned target map and compiled thunk inputs together')
    def test_absent_option_keeps_default_profile_independent(self):
        with tempfile.TemporaryDirectory() as temp:
            args=self.options(Path(temp)) # deliberately omits the new attribute
            with patch.object(builder,'inspect_path',side_effect=StopBeforeSourceRead) as inspect,patch.object(builder,'run') as run,self.assertRaises(StopBeforeSourceRead):builder.build(args)
            inspect.assert_called_once_with(args.game_app.resolve());run.assert_not_called();self.assertFalse(args.output.exists())
    def test_signed_selection_flag_is_explicit_false_or_true(self):
        for selected in (False,True):
            with self.subTest(selected=selected),tempfile.TemporaryDirectory() as temp:
                root=Path(temp);source=root/'OwnSource.app';source.mkdir()
                # Entirely invented source bytes. Deliberately inherited true:
                # the builder must overwrite the copied selection flag.
                info={'CFBundleIdentifier':'com.innersloth.amongus','CFBundleExecutable':'OwnMain','CFBundleVersion':'3','CFBundleShortVersionString':'1.2.3','EHRAuthHandoffDiagnosticsCompiled':True}
                (source/'Info.plist').write_bytes(plistlib.dumps(info));(source/'OwnMain').write_bytes(b'own synthetic launcher')
                before=hashlib.sha256((source/'Info.plist').read_bytes()).hexdigest()
                destination=root/'own-destination.local.txt';destination.write_text('own-fixture-destination')
                profile=root/'OwnProfile';profile.write_bytes(b'own fixture profile')
                decoded={'TeamIdentifier':['ABCDEFGHIJ'],'ExpirationDate':datetime(2100,1,1),'ProvisionedDevices':['own-fixture-destination'],'DeveloperCertificates':[],
                    'Entitlements':{'application-identifier':'ABCDEFGHIJ.org.example.ehrfixture','get-task-allow':True,'com.apple.developer.applesignin':['Default'],'com.apple.developer.game-center':True}}
                overrides={}
                if selected:overrides=dict(auth_handoff_map=root/'handoff.json',full_native_catalog=root/'catalog.json',full_native_target_map=root/'targets.json',full_thunk_inputs=root/'thunks',managed_dylib=root/'own.dylib',iterator_hook_map=root/'iterator.json',static_class_hooks=root/'class.json',eos_login_map=root/'eos.json',platform_sign_in=True)
                args=self.options(root,**overrides)
                def output(arguments,**unused):
                    if arguments[:3]==['security','cms','-D']:return plistlib.dumps(decoded)
                    if arguments[:3]==['xcrun','--sdk','iphoneos']:raise StopBeforeSDKCall
                    self.fail('Unexpected external command in own synthetic fixture')
                with patch.object(builder,'inspect_path',return_value={'readiness':'ready','issues':[],'images':[],'bundle':'own fixture'}),patch.object(builder.subprocess,'check_output',side_effect=output),patch.object(builder,'run') as run,self.assertRaises(StopBeforeSDKCall):builder.build(args)
                run.assert_not_called();result=plistlib.loads((args.output/'EHRNativeGame.app/Info.plist').read_bytes())
                self.assertIs(result['EHRAuthHandoffDiagnosticsCompiled'],selected)
                self.assertEqual(result['CFBundleShortVersionString'],'1.2.3');self.assertNotIn('OwnMain',[p.name for p in (args.output/'EHRNativeGame.app').iterdir()])
                self.assertEqual(hashlib.sha256((source/'Info.plist').read_bytes()).hexdigest(),before)
    def test_cli_describes_optional_passive_dependencies(self):
        env=dict(os.environ);env['PYTHONPATH']=str(ROOT/'tools')
        result=subprocess.check_output([sys.executable,str(ROOT/'tools/build_game_probe.py'),'--help'],env=env,text=True,timeout=10)
        self.assertIn('--auth-handoff-map',result);self.assertIn('passive original-preserving',result)
        self.assertIn('--eos-login-map',result);self.assertIn('--platform-sign-in',result)

if __name__=='__main__':unittest.main()
