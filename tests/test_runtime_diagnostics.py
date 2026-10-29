from __future__ import annotations
import json
import pathlib
import os
import subprocess
import tempfile
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[1]
class RuntimeDiagnostics(unittest.TestCase):
 def run_fixture(self,name,objc=False,game_start=False,auth_handoff=False,network=False):
  with tempfile.TemporaryDirectory(prefix='ehr-diagnostics-fixture-') as temp:
   output=pathlib.Path(temp)/'fixture'
   args=['xcrun','clang++','-std=c++17','-Wall','-Wextra','-Werror','-pthread','-I',str(ROOT/'native'),'-I',str(ROOT/'native/include'),str(ROOT/'tests'/name)]
   if objc:args+=['-fobjc-arc',str(ROOT/'native/EHRRuntimeDiagnostics.mm'),'-framework','Foundation']
   if game_start:args+=['-DEHR_HAS_GAME_START_ITERATOR=1']
   if auth_handoff:args+=['-DEHR_HAS_AUTH_HANDOFF=1']
   if network:args+=['-DEHR_HAS_NETWORK_DIAGNOSTICS=1']
   compiled=subprocess.run(args+['-o',str(output)],capture_output=True,text=True)
   self.assertEqual(compiled.returncode,0,compiled.stderr)
   result=subprocess.run([str(output)],check=True,capture_output=True,text=True)
   self.assertTrue(json.loads(result.stdout)['pass'])
 def test_existing_production_iterator_lifecycle_and_unowned_fallthrough(self):
  canonical=pathlib.Path(os.environ.get('EHR_CANONICAL_PROJECT',str(ROOT)))
  with tempfile.TemporaryDirectory(prefix='ehr-iterator-diag-fixture-') as temp:
   output=pathlib.Path(temp)/'fixture'
   command=['xcrun','clang++','-std=c++17','-Wall','-Wextra','-Werror','-fobjc-arc','-fobjc-arc-exceptions','-I',str(ROOT/'native'),'-I',str(canonical/'native'),'-I',str(canonical/'native/include'),'-DEHR_PRODUCTION_SOURCE="'+str(ROOT/'native/EHRManagedIteratorProduction.mm')+'"',str(ROOT/'tests/production_iterator_fixture.mm'),'-framework','Foundation','-o',str(output)]
   result=subprocess.run(command,capture_output=True,text=True,timeout=60)
   self.assertEqual(result.returncode,0,result.stderr)
   result=subprocess.run([str(output)],capture_output=True,text=True,check=True,timeout=15)
   self.assertIn('production weak iterator lifecycle checks',result.stdout)
 def test_predispatch_receiver_and_reference_argument_phase(self):
  canonical=pathlib.Path(os.environ.get('EHR_CANONICAL_PROJECT',str(ROOT)))
  with tempfile.TemporaryDirectory(prefix='ehr-phase-fixture-') as temp:
   output=pathlib.Path(temp)/'fixture'
   command=['xcrun','clang++','-std=c++17','-Wall','-Wextra','-Werror','-fobjc-arc','-I',str(ROOT/'native'),'-I',str(canonical/'native'),'-I',str(canonical/'native/include'),str(ROOT/'tests/thunk_phase_diagnostics_fixture.mm'),'-framework','Foundation','-Wl,-undefined,dynamic_lookup','-Wl,-export_dynamic','-o',str(output)]
   result=subprocess.run(command,capture_output=True,text=True,timeout=60)
   self.assertEqual(result.returncode,0,result.stderr)
   proof=json.loads(subprocess.run([str(output)],capture_output=True,text=True,check=True,timeout=15).stdout)
   self.assertTrue(proof['pass']);self.assertFalse(proof['gameLoaded']);self.assertEqual(proof['sourceCalls'],0)
 def test_actual_gateway_guards_and_main_thread_snapshot(self):
  canonical=pathlib.Path(os.environ.get('EHR_CANONICAL_PROJECT',str(ROOT)))
  with tempfile.TemporaryDirectory(prefix='ehr-guard-fixture-') as temp:
   output=pathlib.Path(temp)/'fixture'
   command=['xcrun','clang++','-std=c++17','-Wall','-Wextra','-Werror','-fobjc-arc','-I',str(ROOT/'native'),'-I',str(canonical/'native'),'-I',str(canonical/'native/include'),str(ROOT/'tests/gateway_limit_diagnostics_fixture.mm'),'-framework','Foundation','-Wl,-undefined,dynamic_lookup','-o',str(output)]
   result=subprocess.run(command,capture_output=True,text=True,timeout=60)
   self.assertEqual(result.returncode,0,result.stderr)
   proof=json.loads(subprocess.run([str(output)],capture_output=True,text=True,check=True,timeout=15).stdout)
   self.assertTrue(proof['pass']);self.assertFalse(proof['gameLoaded']);self.assertEqual(proof['realGcCalls'],0)
 def test_native_exception_public_metadata_without_game(self):
  with tempfile.TemporaryDirectory(prefix='ehr-exception-diag-') as temp:
   output=pathlib.Path(temp)/'fixture'
   command=['xcrun','clang++','-std=c++17','-Wall','-Wextra','-Werror','-fobjc-arc','-fobjc-arc-exceptions','-I',str(ROOT/'native'),'-I',str(ROOT/'native/include'),str(ROOT/'tests/native_exception_diagnostics_fixture.mm'),'-framework','Foundation','-Wl,-undefined,dynamic_lookup','-o',str(output)]
   compiled=subprocess.run(command,capture_output=True,text=True,timeout=60)
   self.assertEqual(compiled.returncode,0,compiled.stderr)
   proof=json.loads(subprocess.run([str(output)],capture_output=True,text=True,check=True,timeout=15).stdout)
   self.assertTrue(proof['pass']);self.assertFalse(proof['gameLoaded']);self.assertEqual(proof['realGcCalls'],0)
 def test_bounded_ring_threads_and_call_balance(self):self.run_fixture('runtime_diagnostics_fixture.cpp')
 def test_actual_numeric_json_schema_without_filesystem(self):self.run_fixture('runtime_diagnostics_json_fixture.mm',True)
 def test_game_start_counter_snapshot_without_runtime_or_filesystem(self):self.run_fixture('runtime_diagnostics_json_fixture.mm',True,True)
 def test_auth_handoff_numeric_snapshot_with_game_start_without_runtime_or_filesystem(self):self.run_fixture('runtime_diagnostics_json_fixture.mm',True,True,True)
 def test_disconnect_scalar_snapshot_with_optional_modules_without_runtime_or_filesystem(self):self.run_fixture('runtime_diagnostics_json_fixture.mm',True,True,True,True)
if __name__=='__main__':unittest.main()
