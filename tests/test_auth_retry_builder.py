from pathlib import Path
from types import SimpleNamespace
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
spec=importlib.util.spec_from_file_location('ehr_guard_builder',ROOT/'tools/build_game_probe.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)

class GuardBuilderTests(unittest.TestCase):
    def test_guard_without_passive_eos_profile_rejects_before_input_inspection(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)
            args=SimpleNamespace(team_id='ABCDEFGHIJ',bundle_id='org.example.ehrfixture',team_name=None,
                game_app=path,output=path/'new',full_native_catalog=None,
                eos_login_map=None,auth_retry_guard_map=path/'map.json')
            with patch.object(builder,'inspect_path') as inspect, self.assertRaisesRegex(ValueError,'requires --eos-login-map'):
                builder.build(args)
            inspect.assert_not_called();self.assertFalse((path/'new').exists())

    def test_explicit_activation_requires_exact_guard_map_before_input_inspection(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)
            args=SimpleNamespace(team_id='ABCDEFGHIJ',bundle_id='org.example.ehrfixture',team_name=None,
                game_app=path,output=path/'new',full_native_catalog=None,
                eos_login_map=path/'eos.json',auth_retry_guard_map=None,enable_auth_retry_guard=True)
            with patch.object(builder,'inspect_path') as inspect, self.assertRaisesRegex(ValueError,'requires --auth-retry-guard-map'):
                builder.build(args)
            inspect.assert_not_called();self.assertFalse((path/'new').exists())

    def test_guard_cannot_enter_non_full_profile(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)
            args=SimpleNamespace(team_id='ABCDEFGHIJ',bundle_id='org.example.ehrfixture',team_name=None,
                game_app=path,output=path/'new',full_native_catalog=None,
                full_native_target_map=None,full_thunk_inputs=None,full_source_autoload=False,
                eos_login_map=path/'eos.json',auth_retry_guard_map=path/'guard.json')
            with patch.object(builder,'inspect_path') as inspect, self.assertRaisesRegex(ValueError,'EOS diagnostics require the full source profile'):
                builder.build(args)
            inspect.assert_not_called();self.assertFalse((path/'new').exists())

    def test_cli_exposes_explicit_development_opt_in_and_default_disabled_map_option(self):
        env=dict(os.environ);env['PYTHONPATH']=str(ROOT/'tools')
        text=subprocess.check_output([sys.executable,str(ROOT/'tools/build_game_probe.py'),'--help'],env=env,text=True,timeout=10)
        self.assertIn('--auth-retry-guard-map',text);self.assertIn('default-disabled',text)
        self.assertIn('--enable-auth-retry-guard',text);self.assertIn('Opt-in development build',text)

if __name__=='__main__':unittest.main()
