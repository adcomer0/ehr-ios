from __future__ import annotations
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class TerminalMarkerTests(unittest.TestCase):
    def test_actual_gateway_marker_metadata_barrier_and_worker_reads(self):
        with tempfile.TemporaryDirectory(prefix="ehr-terminal-marker-") as directory:
            binary = Path(directory) / "fixture"
            command = ["xcrun", "clang++", "-std=c++17", "-Wall", "-Wextra", "-Werror",
                       "-fobjc-arc", "-fobjc-arc-exceptions", "-I", str(ROOT / "native"),
                       "-I", str(ROOT / "native/include"),
                       str(ROOT / "tests/iterator_terminal_gateway_fixture.mm"),
                       "-framework", "Foundation", "-Wl,-undefined,dynamic_lookup",
                       "-Wl,-export_dynamic", "-o", str(binary)]
            compiled = subprocess.run(command, capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            proof = json.loads(result.stdout)
            self.assertTrue(proof["pass"])
            self.assertFalse(proof["gameLoaded"])
            self.assertEqual(proof["markerRoots"], 1)
            self.assertGreater(proof["checks"], 10000)

if __name__ == "__main__":
    unittest.main()
