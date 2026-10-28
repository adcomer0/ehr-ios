from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CANONICAL = Path(os.environ.get('EHR_CANONICAL_ROOT', str(ROOT)))


@unittest.skipUnless(sys.platform == 'darwin', 'Requires Apple clang and Foundation')
class AppleObserverTests(unittest.TestCase):
    def test_own_objective_c_forwarding_redaction_and_failed_preflight(self):
        with tempfile.TemporaryDirectory(prefix='ehr-own-apple-observer-') as temp:
            base = Path(temp)
            (base/'EHRRuntimeDiagnostics.h').write_text('#pragma once\n#include <stdint.h>\nvoid EHRRuntimeDiagnosticsRecordAuth(uint32_t,int32_t,uint64_t);\nvoid EHRRuntimeDiagnosticsRecordAuthCounters(uint64_t,uint64_t,uint64_t,uint64_t);\n')
            exe = base/'Fixture'
            compile_result = subprocess.run(['xcrun','clang++','-std=c++20','-fobjc-arc','-fblocks','-framework','Foundation',
                '-I',str(ROOT/'native'),'-I',str(base),'-I',str(CANONICAL/'native'),str(ROOT/'tests/AppleAuthObserverFixture.mm'),'-o',str(exe)],capture_output=True,text=True,timeout=60)
            self.assertEqual(compile_result.returncode,0,compile_result.stderr)
            result = subprocess.run([str(exe)],check=True,capture_output=True,text=True,timeout=10)
            proof = json.loads(result.stdout)
            self.assertTrue(proof['pass'])
            self.assertEqual(proof['checks'],24)
            self.assertEqual(proof['originalRequests'],2)
            self.assertEqual(proof['originalErrors'],5)
            self.assertEqual(proof['originalSuccesses'],1)
            self.assertEqual(proof['gameAuthCalls'],0)
            self.assertEqual(proof['networkRequests'],0)
            self.assertEqual(proof['suppressed'],0)
