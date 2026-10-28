import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tools/source_port'))
import feature_inventory as f
import wire_aot_registry as wiring


class WiringSafetyTests(unittest.TestCase):
    def test_rewrites_tokens_only_and_preserves_surrounding_behavior(self):
        text = '// Activator.CreateInstance(x)\nvar s = "Activator.CreateInstance(x)";\nvar real = Activator . CreateInstance ( x );\n'
        result, edits = wiring.rewrite(text, [("Activator.CreateInstance(x)", "Factory(x)", 1)])
        self.assertIn('// Activator.CreateInstance(x)', result)
        self.assertIn('"Activator.CreateInstance(x)"', result)
        self.assertIn("var real = Factory(x);", result)
        self.assertEqual(edits[0]["line"], 3)

    def test_missing_duplicate_and_overlapping_edits_fail_closed(self):
        with self.assertRaises(ValueError):
            wiring.rewrite("A(); A();", [("A()", "B()", 1)])
        with self.assertRaises(ValueError):
            wiring.rewrite("A();", [("Missing()", "B()", 1)])
        with self.assertRaises(ValueError):
            wiring.rewrite("A(B());", [("A(B())", "Other()", 1), ("B()", "Inner()", 1)])

    @unittest.skipUnless(f.UPSTREAM_DEFAULT.exists(), "Pinned upstream checkout is not available")
    def test_actual_pinned_source_wiring_has_exact_counts_and_retains_guards(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            report = wiring.generate(f.UPSTREAM_DEFAULT, output)
            self.assertEqual((report["source_files"], report["edits"]), (8, 24))
            random = (output / "Modules/Random/IRandom.cs").read_text()
            self.assertIn("Instance == null || Instance.GetType() != type", random)
            self.assertIn("EHRAotRegistry.CreateIRandom(type) ?? Instance", random)
            main = (output / "Main.cs").read_text()
            self.assertIn("AllRoleClasses.Sort();", main)
            self.assertIn("Assembly.GetExecutingAssembly().GetTypes()", main)
            hns = (output / "Gamemodes/CustomHnS.cs").read_text()
            self.assertIn("CachedHnsTypes ??=", hns)
            with self.assertRaises(ValueError):
                wiring.generate(f.UPSTREAM_DEFAULT, output)


if __name__ == "__main__":
    unittest.main()
