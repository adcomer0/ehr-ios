"""Owned files and mocked process collaborators; no signing/device/game actions."""
from pathlib import Path
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import plistlib
import shutil
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("passive_runner", ROOT / "tests/runtime/run_native_runtime_test.py")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


def snapshot(root):
    return {str(path.relative_to(root)): path.read_bytes() for path in root.rglob("*") if path.is_file()}


def candidate_files(root, fmt=plistlib.FMT_XML):
    root.mkdir()
    info = {"CFBundleIdentifier": "org.example.ehrfixture", "CFBundleExecutable": "EHRNativeGame",
            "CFBundleName": "EHRNativeGame", "CFBundleVersion": "67", "CFBundleShortVersionString": "1.0",
            "EHRUnitySceneHostCompiled": True, "EHRItchAuthCompiled": True,
            "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False,
                "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [{"UISceneDelegateClassName": "EHRUnitySceneDelegate"}]}}}
    (root / "Info.plist").write_bytes(plistlib.dumps(info, fmt=fmt))
    for name in (*runner.RELATIVE_BINARIES, "embedded.mobileprovision", "Data/OwnedResource.txt"):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(("Owned synthetic input: " + name).encode())
    (root / "EHRNativeGame").chmod(0o755)
    return info


class PassiveRuntimeHostTests(unittest.TestCase):
    def test_generated_project_preserves_product_and_targets_passive_executable(self):
        template = runner.HERE / "EHRRuntimeProbe.xcodeproj/project.pbxproj"
        before = template.read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            source = base / "Source"
            source.mkdir()
            for name in runner.SOURCE_FILES:
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("// Owned source fixture\n")
            (source / "app/Assets.xcassets").mkdir()
            test = base / "OwnedTest.mm"
            test.write_text('// __EHR_TEST_APP_BUNDLE_ID__\n')
            output = base / "Output"
            output.mkdir()
            with patch.object(runner, "run", side_effect=AssertionError("No external process expected")):
                project = runner.prepare_project(source, test, output, "ABCDEFGHIJ", "org.example.ehrfixture")
            text = (project / "EHRRuntimeProbe.xcodeproj/project.pbxproj").read_text()
            self.assertEqual(text.count("PRODUCT_NAME = EHRNativeGame;"), 2)
            self.assertEqual(text.count("EXECUTABLE_NAME = EHRPassiveRuntimeHost;"), 2)
            self.assertEqual(text.count('TEST_HOST = "$(BUILT_PRODUCTS_DIR)/EHRNativeGame.app/EHRPassiveRuntimeHost";'), 2)
            self.assertNotIn('TEST_HOST = "$(BUILT_PRODUCTS_DIR)/EHRNativeGame.app/EHRNativeGame";', text)
            self.assertIn("DEVELOPMENT_TEAM = ABCDEFGHIJ", text)
            self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = org.example.ehrfixture;", text)
            self.assertIn("path = EHRNativeGame.app;", text)
        self.assertEqual(template.read_bytes(), before)

    def test_project_anchor_changes_are_rejected(self):
        original = (runner.HERE / "EHRRuntimeProbe.xcodeproj/project.pbxproj").read_text()
        for changed in (original.replace("PRODUCT_NAME = EHRNativeGame;", "PRODUCT_NAME = Changed;", 1),
                        original.replace("TEST_HOST =", "CHANGED_HOST =", 1),
                        original + "\nEXECUTABLE_NAME = Existing;\n"):
            with self.subTest(length=len(changed)), self.assertRaises(ValueError):
                runner.passive_project_settings(changed)
        with self.assertRaises(ValueError):
            runner.passive_project_settings(runner.passive_project_settings(original))

    def test_only_copied_executable_name_and_plist_key_change(self):
        for fmt in (plistlib.FMT_XML, plistlib.FMT_BINARY):
            with self.subTest(fmt=fmt), tempfile.TemporaryDirectory() as temporary:
                base = Path(temporary)
                candidate, host = base / "Candidate.app", base / "EHRNativeGame.app"
                original_info = candidate_files(candidate, fmt)
                shutil.copytree(candidate, host)
                original, copied = snapshot(candidate), snapshot(host)
                self.assertTrue(runner.prepare_passive_test_host(candidate, host))
                self.assertEqual(snapshot(candidate), original)
                expected = dict(copied)
                executable = expected.pop("EHRNativeGame")
                expected[runner.PASSIVE_EXECUTABLE] = executable
                actual = snapshot(host)
                self.assertEqual({k: v for k, v in actual.items() if k != "Info.plist"},
                                 {k: v for k, v in expected.items() if k != "Info.plist"})
                self.assertEqual(plistlib.loads(actual["Info.plist"]),
                                 dict(original_info, CFBundleExecutable=runner.PASSIVE_EXECUTABLE))
                self.assertEqual(actual["Info.plist"].startswith(b"bplist"), fmt == plistlib.FMT_BINARY)
                self.assertEqual((host / runner.PASSIVE_EXECUTABLE).stat().st_mode & 0o777, 0o755)

    def test_changed_shared_or_ambiguous_copy_is_rejected_before_mutation(self):
        for variant in ("same", "nested", "existing", "info", "binary", "linked_info", "linked_binary", "symlink_info"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                base = Path(temporary)
                candidate, host = base / "Candidate.app", base / "Host.app"
                candidate_files(candidate)
                if variant == "same":
                    host = candidate
                else:
                    if variant == "nested": host = candidate / "Nested.app"
                    shutil.copytree(candidate, host)
                    if variant == "existing": (host / runner.PASSIVE_EXECUTABLE).write_text("Owned collision")
                    elif variant == "info":
                        info = plistlib.loads((host / "Info.plist").read_bytes())
                        info["CFBundleIdentifier"] = "org.example.changed"
                        (host / "Info.plist").write_bytes(plistlib.dumps(info))
                    elif variant == "binary": (host / "EHRNativeGame").write_bytes(b"Owned changed binary")
                    elif variant in ("linked_info", "linked_binary", "symlink_info"):
                        name = "EHRNativeGame" if variant == "linked_binary" else "Info.plist"
                        (host / name).unlink()
                        if variant == "symlink_info": (host / name).symlink_to(candidate / name)
                        else: os.link(candidate / name, host / name)
                before = snapshot(base)
                with self.assertRaises(ValueError): runner.prepare_passive_test_host(candidate, host)
                self.assertEqual(snapshot(base), before)

    def synthetic_workflow(self, corrupt=None):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            candidate, output = base / "Candidate.app", base / "Output"
            candidate_files(candidate)
            original = snapshot(candidate)
            test = base / "OwnedTest.mm"
            test.write_text("// Owned XCTest fixture\n")
            host = output / "DerivedData/Build/Products/Debug-iphoneos/EHRNativeGame.app"
            calls = []
            def own_run(arguments, log=None, cwd=None, timeout=180):
                args = [str(x) for x in arguments]
                calls.append(args)
                if args[0] == "system_profiler": return json.dumps({"SPHardwareDataType": [{"provisioning_UDID": "OWNED-FIXTURE-NOT-A-DEVICE"}]})
                if args[0] == "xcodebuild":
                    (host / "PlugIns/NativeRuntimeTests.xctest").mkdir(parents=True)
                    return ""
                if args[:2] == ["cp", "-cR"]:
                    shutil.copytree(Path(args[2]), Path(args[3]))
                    return ""
                if args[0] == "codesign" and "--force" in args:
                    self.assertEqual(plistlib.loads((host / "Info.plist").read_bytes())["CFBundleExecutable"], runner.PASSIVE_EXECUTABLE)
                    self.assertFalse((host / "EHRNativeGame").exists())
                    self.assertEqual((host / runner.PASSIVE_EXECUTABLE).read_bytes(), original["EHRNativeGame"])
                    with (host / runner.PASSIVE_EXECUTABLE).open("ab") as stream: stream.write(b"Owned synthetic reseal")
                    if corrupt: (host / corrupt).write_bytes(b"Owned synthetic unexpected mutation")
                if args[:4] == ["xcrun", "xcresulttool", "export", "attachments"]:
                    (output / "RuntimeResults.xcresult").mkdir()
                    (output / "Attachments").mkdir()
                return ""
            arguments = ["runner", "--source-root", str(base / "Source"), "--candidate-app", str(candidate),
                         "--test-source", str(test), "--output-root", str(output), "--team-id", "ABCDEFGHIJ",
                         "--bundle-id", "org.example.ehrfixture", "--sign-identity", "Owned Fixture Identity"]
            with patch.object(sys, "argv", arguments), patch.object(runner.platform, "system", return_value="Darwin"), \
                 patch.object(runner.platform, "machine", return_value="arm64"), \
                 patch.object(runner, "prepare_project", return_value=base / "Project"), \
                 patch.object(runner, "run", side_effect=own_run), \
                 patch.object(runner.subprocess, "Popen", return_value=SimpleNamespace(poll=lambda: 0, returncode=0)) as launched, \
                 contextlib.redirect_stdout(io.StringIO()):
                if corrupt:
                    with self.assertRaisesRegex(ValueError, "profile changed|nested candidate binary changed"):
                        runner.main()
                    launched.assert_not_called()
                else:
                    runner.main()
                    summary = json.loads((output / "runtime-test-summary.json").read_text())
                    self.assertIs(summary["interactive_ui_disabled_by_test_host_identity"], True)
                    self.assertIs(summary["source_candidate_unchanged"], True)
                    self.assertEqual(summary["candidate_binary_sha256"], {name: hashlib.sha256(original[name]).hexdigest() for name in runner.RELATIVE_BINARIES})
                    self.assertEqual(summary["candidate_profile_sha256"], hashlib.sha256(original["embedded.mobileprovision"]).hexdigest())
                    self.assertEqual(launched.call_count, 1)
            self.assertEqual(snapshot(candidate), original)
            verifications = [args for args in calls if args[0] == "python3"]
            self.assertEqual(len(verifications), 2)
            for args in verifications:
                self.assertEqual(args[args.index("--team-id") + 1], "ABCDEFGHIJ")
                self.assertEqual(args[args.index("--bundle-id") + 1], "org.example.ehrfixture")

    def test_synthetic_workflow_reseals_only_renamed_copy_and_records_identity(self):
        self.synthetic_workflow()

    def test_synthetic_workflow_rejects_changed_nested_binary_or_profile(self):
        for corrupt in ("embedded.mobileprovision", runner.RELATIVE_BINARIES[1]):
            with self.subTest(corrupt=corrupt): self.synthetic_workflow(corrupt)


if __name__ == "__main__": unittest.main()
