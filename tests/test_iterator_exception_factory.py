"""Owned public-runtime fixture for the actual native iterator error path."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class IteratorExceptionFactoryTests(unittest.TestCase):
    def test_public_factory_type_pin_unwind_and_fail_closed_states(self):
        with tempfile.TemporaryDirectory(prefix="ehr-iterator-exception-") as directory:
            binary = Path(directory) / "fixture"
            command = ["xcrun", "clang++", "-std=c++17", "-Wall", "-Wextra", "-Werror",
                       "-fobjc-arc", "-fobjc-arc-exceptions", "-I", str(ROOT / "native"),
                       "-I", str(ROOT / "native/include"),
                       str(ROOT / "tests/iterator_exception_factory_fixture.mm"),
                       "-framework", "Foundation", "-Wl,-undefined,dynamic_lookup",
                       "-Wl,-export_dynamic", "-o", str(binary)]
            compiled = subprocess.run(command, capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            proof = json.loads(result.stdout)
            self.assertTrue(proof["pass"])
            self.assertFalse(proof["gameLoaded"])
            self.assertEqual(proof["activatorCalls"], 0)
            self.assertEqual(proof["liveNativeHandles"], 0)
            self.assertGreaterEqual(proof["checks"], 25)


if __name__ == "__main__":
    unittest.main()
