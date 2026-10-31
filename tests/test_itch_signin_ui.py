from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == "darwin", "Requires Apple Foundation/Security and SDKs")
class ItchSignInUITests(unittest.TestCase):
    def test_actual_policy_rejects_malformed_keys_callbacks_and_storage_scope(self):
        with tempfile.TemporaryDirectory(prefix="ehr-itch-ui-policy-") as directory:
            executable = Path(directory) / "fixture"
            built = subprocess.run([
                "xcrun", "clang++", "-fobjc-arc", "-fblocks", "-std=c++20",
                "-Wall", "-Wextra", "-Werror", "-framework", "Foundation",
                "-framework", "Security", str(ROOT / "tests/ItchSignInPolicyFixture.mm"),
                "-o", str(executable),
            ], capture_output=True, text=True, timeout=60)
            self.assertEqual(built.returncode, 0, built.stderr)
            run = subprocess.run([str(executable)], capture_output=True, text=True, timeout=15)
            self.assertEqual(run.returncode, 0, run.stderr + run.stdout)
            proof = json.loads(run.stdout)
            self.assertTrue(proof["success"])
            self.assertGreaterEqual(proof["checks"], 400)
            for field in ("actualCredentialsRead", "networkRequests", "accountActions", "actualKeychainWrites"):
                self.assertEqual(proof[field], 0)

    def test_full_controller_compiles_for_ios_arm64(self):
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
        built = subprocess.run([
            "xcrun", "clang++", "-target", "arm64-apple-ios17.0", "-isysroot", sdk,
            "-fobjc-arc", "-fblocks", "-std=c++20", "-Wall", "-Wextra", "-Werror",
            "-fsyntax-only", str(ROOT / "native/EHRItchSignInUI.mm"),
        ], capture_output=True, text=True, timeout=60)
        self.assertEqual(built.returncode, 0, built.stderr)

    def test_owned_uikit_security_fixture_compiles_for_simulator(self):
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
        built = subprocess.run([
            "xcrun", "clang++", "-target", "arm64-apple-ios17.0-simulator", "-isysroot", sdk,
            "-fobjc-arc", "-fblocks", "-std=c++20", "-Wall", "-Wextra", "-Werror",
            "-fsyntax-only", str(ROOT / "tests/ItchSignInUIKitFixture.mm"),
        ], capture_output=True, text=True, timeout=60)
        self.assertEqual(built.returncode, 0, built.stderr)
