from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == "darwin", "Requires Apple Foundation and clang")
class ItchAuthProviderTests(unittest.TestCase):
    def test_exact_provider_coordinates_owned_callbacks_without_game_or_auth(self):
        source = ROOT / "native/EHRItchAuthProvider.mm"
        before = hashlib.sha256(source.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory(prefix="ehr-itch-provider-own-") as directory:
            base = Path(directory)
            (base / "UIKit").mkdir()
            (base / "UIKit/UIKit.h").write_text('''#pragma once
#import <Foundation/Foundation.h>
@interface UIView:NSObject
@property(nonatomic,strong) id window;
@end
@interface UIViewController:NSObject
@property(nonatomic,strong) UIView *view;
@property(nonatomic,strong) UIViewController *presentedViewController;
@end
''')
            (base / "EHRItchAuthBinding.generated.h").write_text('''#pragma once
// Invented own-function addresses. No game/native map is used by this fixture.
#define EHRItchAuthImplTrampolineRVA (reinterpret_cast<uintptr_t>(&FixtureOriginalImpl))
#define EHRItchAuthFinalTrampolineRVA (reinterpret_cast<uintptr_t>(&FixtureOriginalFinal))
#define EHRItchAuthSilentTrampolineRVA (reinterpret_cast<uintptr_t>(&FixtureOriginalSilent))
#define EHRItchAuthGuestMigrationTrampolineRVA (reinterpret_cast<uintptr_t>(&FixtureOriginalMigration))
''')
            executable = base / "fixture"
            built = subprocess.run([
                "xcrun", "clang++", "-fobjc-arc", "-fblocks", "-std=c++20",
                "-Wall", "-Wextra", "-Werror", "-framework", "Foundation",
                "-I", str(base), "-I", str(ROOT / "native"),
                str(ROOT / "tests/ItchAuthProviderFixture.mm"), "-o", str(executable),
            ], capture_output=True, text=True, timeout=60)
            self.assertEqual(built.returncode, 0, built.stderr)
            run = subprocess.run([str(executable)], capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            proof = json.loads(run.stdout)
            self.assertTrue(proof["success"])
            self.assertGreaterEqual(proof["numericFilterChecks"], 7)
            self.assertGreaterEqual(proof["checks"], 250)
            for name in ("networkRequests", "keychainOperations", "gameCalls", "accountActions", "actualCredentialsRead"):
                self.assertEqual(proof[name], 0)
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), before, "Provider changed during fixture run")
