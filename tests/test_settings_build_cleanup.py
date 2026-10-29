import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("prepare_settings_build_cleanup", ROOT / "tools/prepare_settings_build_cleanup.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class SettingsBuildCleanupTests(unittest.TestCase):
    def test_actual_selected_snapshot_recovers_pinned_baseline(self):
        selected = ROOT / "source-app/compiled/157/GameOptionsMenuPatch.cs"
        recovered = tool.reverse(selected.read_text())
        self.assertEqual(hashlib.sha256(recovered.encode()).hexdigest(), tool.EXPECTED_SOURCE_SHA256)

    def source(self):
        return "namespace Own;\n" + tool.START + "            OwnActions();\n" + tool.STALE_OLD + "\n" + tool.NORMAL_OLD + "        }\n" + tool.FOLLOWING + " => 1;\n"

    def project(self, path):
        source = path / "GameOptionsMenuPatch.cs"
        source.write_text(self.source())
        project = path / "Input.csproj"
        project.write_text('<Project><ItemGroup><Compile Include="GameOptionsMenuPatch.cs"/><Compile Include="Other.cs"/><EmbeddedResource Include="images/a.png" LogicalName="Own.Resource"/><Reference Include="A"><HintPath>libs/A.dll</HintPath></Reference></ItemGroup></Project>')
        return project, source

    def test_exact_reversal_preserves_actions_and_later_methods(self):
        old = self.source()
        new = tool.adapt(old)
        self.assertEqual(tool.reverse(new), old)
        self.assertIn("                OwnActions();", new)
        self.assertIn("completedGen == gen", new)
        self.assertEqual(new.count("BuildCoroutines.Remove(__instance)"), 1)

    def test_missing_duplicate_and_already_adapted_anchors_fail(self):
        old = self.source()
        for value in [old.replace(tool.STALE_OLD, "drift"), old + tool.START, tool.adapt(old), old.replace(tool.NORMAL_OLD, tool.NORMAL_NEW)]:
            with self.assertRaises(ValueError):
                tool.adapt(value)

    def test_reverse_rejects_changed_guard(self):
        value = tool.adapt(self.source()).replace("completedGen == gen", "true")
        with self.assertRaises(ValueError):
            tool.reverse(value)

    def test_pin_failure_before_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary).resolve()
            project, _ = self.project(path)
            with self.assertRaisesRegex(ValueError, "source pin changed"):
                tool.prepare(project, path / "Out")
            self.assertFalse((path / "Out").exists())

    def test_duplicate_selection_before_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary).resolve()
            project, _ = self.project(path)
            tree = ET.parse(project)
            ET.SubElement(next(tree.getroot().iter("ItemGroup")), "Compile", Include="elsewhere/GameOptionsMenuPatch.cs")
            tree.write(project)
            with self.assertRaisesRegex(ValueError, "one selected"):
                tool.prepare(project, path / "Out")
            self.assertFalse((path / "Out").exists())

    def test_relative_paths_resources_and_manifest_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary).resolve()
            project, source = self.project(path)
            expected = tool.EXPECTED_SOURCE_SHA256
            tool.EXPECTED_SOURCE_SHA256 = hashlib.sha256(source.read_bytes()).hexdigest()
            try:
                result = tool.prepare(project, path / "Out")
            finally:
                tool.EXPECTED_SOURCE_SHA256 = expected
            root = ET.parse(result).getroot()
            self.assertEqual([x.get("Include") for x in root.iter("Compile")], [str(path / "Out/GameOptionsMenuPatch.cs"), str(path / "Other.cs")])
            resource = next(root.iter("EmbeddedResource"))
            self.assertEqual(resource.get("Include"), str(path / "images/a.png"))
            self.assertEqual(resource.get("LogicalName"), "Own.Resource")
            self.assertEqual(next(root.iter("HintPath")).text, str(path / "libs/A.dll"))
            manifest = json.loads((path / "Out/settings-build-cleanup.json").read_text())
            self.assertFalse(manifest["cleanupOfReplacementGenerationAllowed"])
            self.assertFalse(manifest["physicalStatus8CauseProven"])
            self.assertTrue(manifest["normalUiActionsAndYieldSitesUnchanged"])


if __name__ == "__main__":
    unittest.main()
