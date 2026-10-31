from pathlib import Path
import subprocess
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]

@unittest.skipUnless(sys.platform=='darwin','Requires Apple UIKit SDK')
class OwnershipCoverTests(unittest.TestCase):
    def test_real_cover_and_input_boundary_fixture_compile_for_ios(self):
        sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
        run=subprocess.run(['xcrun','clang++','-target','arm64-apple-ios17.0','-isysroot',sdk,
            '-fobjc-arc','-fblocks','-std=c++20','-Wall','-Wextra','-Werror','-fsyntax-only',
            str(ROOT/'tests/OwnershipCoverUIKitFixture.mm'),str(ROOT/'native/EHROwnershipCover.mm')],
            capture_output=True,text=True,timeout=60)
        self.assertEqual(run.returncode,0,run.stderr)
