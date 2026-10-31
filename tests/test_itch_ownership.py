from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == "darwin", "Requires Apple Foundation and clang")
class ItchOwnershipTests(unittest.TestCase):
    def test_exact_helper_with_owned_transport_no_accounts_or_network(self):
        source = ROOT / "native/EHRItchOwnership.mm"
        before = hashlib.sha256(source.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory(prefix="ehr-owned-ownership-") as directory:
            executable = Path(directory) / "fixture"
            built = subprocess.run([
                "xcrun", "clang++", "-fobjc-arc", "-fblocks", "-std=c++20",
                "-Wall", "-Wextra", "-Werror", "-framework", "Foundation",
                "-framework", "Security", "-I", str(ROOT / "native"),
                str(ROOT / "tests/ItchOwnershipFixture.mm"), "-o", str(executable),
            ], capture_output=True, text=True, timeout=60)
            self.assertEqual(built.returncode, 0, built.stderr)
            run = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            proof = json.loads(run.stdout)
            self.assertTrue(proof["success"])
            self.assertGreaterEqual(proof["checks"], 300)
            for name in ("networkRequests", "keychainOperations", "gameCalls", "accountActions", "actualCredentialsRead"):
                self.assertEqual(proof[name], 0)
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), before)
