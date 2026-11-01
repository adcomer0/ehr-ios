import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value
tool = load("settings_loading", ROOT / "tools/source_port/prepare_settings_loading.py")
checker = load("settings_loading_check", ROOT / "tools/check_settings_loading.py")


class SettingsLoadingTests(unittest.TestCase):
    def test_selected_source_reverses_exactly_to_reviewed64(self):
        data = (ROOT / "source-app/compiled/157/GameOptionsMenuPatch.cs").read_bytes()
        old = tool.reverse(data.decode()).encode()
        self.assertEqual(hashlib.sha256(old).hexdigest(), tool.EXPECTED_SOURCE_SHA256)
        self.assertEqual(tool.transform(old), data)
        with self.assertRaises(ValueError): tool.transform(data)
        with self.assertRaises(ValueError): tool.reverse(data.decode().replace("batch >= 8", "batch >= 9"))

    def test_extracted_actual_scheduling_lifecycle_and_reader(self):
        dotnet = os.environ.get("EHR_DOTNET") or shutil.which("dotnet")
        if not dotnet: self.skipTest("Set EHR_DOTNET for the owned settings control-flow fixture")
        with tempfile.TemporaryDirectory() as temporary:
            proof = checker.check(ROOT / "source-app/compiled/157/GameOptionsMenuPatch.cs", Path(temporary) / "proof", Path(dotnet))
            self.assertTrue(proof["pass"]); self.assertGreater(proof["checks"], 500)
            self.assertEqual(proof["maxSelectedRowsPerSlice"], 8)
            self.assertEqual(proof["actualGameCalls"], 0); self.assertEqual(proof["nativeCalls"], 0)
            destination = os.environ.get("EHR_SETTINGS_LOADING_PROOF")
            if destination:
                import json
                Path(destination).write_text(json.dumps(proof, indent=2) + "\n")

    def test_cache_and_close_changes_are_narrow_and_reversible(self):
        source = (ROOT / "source-app/compiled/157/GameOptionsMenuPatch.cs").read_text()
        old = tool.reverse(source)
        self.assertIn("GMButtons.Clear();", old); self.assertNotIn("GMButtons.Clear();", source)
        self.assertIn("cached = GMButtons.TryGetValue(gm, out cache) && cache;", source)
        self.assertIn("if (InputField) SetTempParent(InputField.gameObject);", source)
        self.assertIn("GameOptionsMenuPatch.CancelAllSettingsBuilds();", source)
        self.assertEqual(source.count("ehr_source_settings_loading_v1"), 1)
        self.assertNotIn("Thread.Sleep", source); self.assertNotIn("GC.Collect", source)


if __name__ == "__main__": unittest.main()
