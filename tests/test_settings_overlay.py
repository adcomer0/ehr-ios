from pathlib import Path
import subprocess
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]

@unittest.skipUnless(sys.platform=='darwin','Requires Apple UIKit SDK')
class SettingsOverlayTests(unittest.TestCase):
    def test_exact_overlay_with_owned_inputs_strict_ios_compile(self):
        sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
        run=subprocess.run(['xcrun','clang++','-target','arm64-apple-ios17.0','-isysroot',sdk,
            '-fobjc-arc','-fblocks','-std=c++20','-Wall','-Wextra','-Werror','-fsyntax-only',
            str(ROOT/'tests/SettingsOverlayUIKitFixture.mm'),str(ROOT/'native/EHROwnershipCover.mm')],
            capture_output=True,text=True,timeout=60)
        self.assertEqual(run.returncode,0,run.stderr)

if __name__=='__main__':unittest.main()
