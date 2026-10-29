from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


class AuthHandoffRuntime(unittest.TestCase):
    @unittest.skipUnless(sys.platform=='darwin','Requires Apple clang/Foundation')
    def test_forwarding_preflight_unknowns_nested_scope_and_exception_cleanup(self):
        with tempfile.TemporaryDirectory(prefix='ehr-own-auth-handoff-') as temp:
            folder=Path(temp);exe=folder/'Fixture'
            header='#pragma once\n#include <stdint.h>\n'
            for name in ('Credentials','Login','Set'):
                header+='extern uintptr_t EHRAuthHandoff'+name+'TrampolineRVA;\n'
            header+='static const uintptr_t EHRAuthHandoffCredentialTypeGetterRVA=0x1aad5f8;\n'
            (folder/'EHRAuthHandoffBinding.generated.h').write_text(header)
            result=subprocess.run(['xcrun','clang++','-std=c++20','-fobjc-arc','-fobjc-arc-exceptions','-fblocks',
                '-Wall','-Wextra','-Werror','-framework','Foundation','-I',str(ROOT/'native'),'-I',str(folder),
                str(ROOT/'tests/auth_handoff_fixture.mm'),'-o',str(exe)],capture_output=True,text=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stderr)
            proof=json.loads(subprocess.check_output([str(exe)],text=True,timeout=10))
            self.assertTrue(proof['pass']);self.assertGreaterEqual(proof['checks'],90)
            self.assertEqual((proof['gameAuthCalls'],proof['networkRequests'],proof['tokenReads']),(0,0,0))


if __name__=='__main__':unittest.main()
