"""Own synthetic preflight checks; no Xcode build, install or device action."""
from __future__ import annotations
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import sys
from types import SimpleNamespace
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("runtime_runner", Path(__file__).with_name("run_native_runtime_test.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
# Invented fixture identities; these do not identify any actual device.
UDID = "00000000-0000000000000001"
IDENTIFIER = "00000000-0000-0000-0000-000000000001"


def device(transport="wired", product="iPhone18,2"):
    return {"identifier": IDENTIFIER,
            "hardwareProperties": {"platform": "iOS", "productType": product, "udid": UDID},
            "connectionProperties": {"transportType": transport, "pairingState": "paired"}}


class PhysicalDestinationTests(unittest.TestCase):
    def test_mac_default_keeps_existing_destination(self):
        class StopBeforeBuild(Exception): pass
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp); candidate = base / "Own.app"; candidate.mkdir()
            (candidate / "embedded.mobileprovision").write_bytes(b"own synthetic profile fixture")
            (candidate / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "org.example.ehrfixture", "CFBundleExecutable": "EHRNativeGame"}))
            for relative in runner.RELATIVE_BINARIES:
                target = candidate / relative; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(b"own fixture")
            arguments = ["runner", "--source-root", str(base / "Source"), "--candidate-app", str(candidate), "--output-root", str(base / "Output"), "--team-id", "ABCDEFGHIJ", "--bundle-id", "org.example.ehrfixture", "--sign-identity", "Own Fixture Identity"]
            def own_run(args, *unused, **keywords):
                if args[0] == "system_profiler":
                    return json.dumps({"SPHardwareDataType": [{"provisioning_UDID": IDENTIFIER}]})
                if args[0] == "xcodebuild":
                    self.assertEqual(args[args.index("-destination") + 1], "platform=macOS,arch=arm64")
                    self.assertIn("GCC_PREPROCESSOR_DEFINITIONS=$(inherited) EHR_XCTEST_WRAPPER_HOLD_SECONDS=5", args)
                    self.assertNotIn("-allowProvisioningDeviceRegistration", args)
                    raise StopBeforeBuild()
                return ""
            with patch.object(sys, "argv", arguments), patch.object(runner.platform, "system", return_value="Darwin"), patch.object(runner.platform, "machine", return_value="arm64"), patch.object(runner, "prepare_project", return_value=base / "Project"), patch.object(runner, "run", side_effect=own_run):
                with self.assertRaises(StopBeforeBuild):
                    runner.main()

    def test_generated_project_uses_only_explicit_own_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp); source = base / "Source"; source.mkdir()
            for relative in runner.SOURCE_FILES:
                target = source / relative; target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("Own fixture source\n")
            (source / "app/Assets.xcassets").mkdir()
            test = base / "OwnTest.mm"
            test.write_text('@"__EHR_TEST_APP_BUNDLE_ID__"; // own assertion\n')
            output = base / "Output"; output.mkdir()
            project = runner.prepare_project(source, test, output, "ABCDEFGHIJ", "org.example.ehrfixture")
            pbx = (project / "EHRRuntimeProbe.xcodeproj/project.pbxproj").read_text()
            self.assertNotIn("__TEAM_ID__", pbx)
            self.assertNotIn("__APP_BUNDLE_ID__", pbx)
            self.assertIn("DEVELOPMENT_TEAM = ABCDEFGHIJ", pbx)
            self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = org.example.ehrfixture.nativeruntimetests", pbx)
            self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = org.example.ehrfixture;", pbx)
            self.assertEqual((project / "NativeRuntimeTests.mm").read_text(),
                             '@"org.example.ehrfixture"; // own assertion\n')

    def test_auth_metadata_proof_include_is_copied_without_game_inputs(self):
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp);source=base/"Source";source.mkdir()
            for relative in runner.SOURCE_FILES:
                target=source/relative;target.parent.mkdir(parents=True,exist_ok=True)
                target.write_text("Own fixture source\n")
            (source/"app/Assets.xcassets").mkdir()
            (source/"tests").mkdir()
            (source/"tests/AuthRetryMetadataProof.inc").write_text("// own metadata proof fixture\n")
            test=base/"OwnTest.mm";test.write_text('#include "AuthRetryMetadataProof.inc"\n')
            output=base/"Output";output.mkdir()
            project=runner.prepare_project(source,test,output,"ABCDEFGHIJ","org.example.ehrfixture")
            self.assertEqual((project/"AuthRetryMetadataProof.inc").read_text(),"// own metadata proof fixture\n")

    def test_iterator_retirement_include_and_public_headers_are_copied(self):
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp);source=base/"Source";source.mkdir()
            for relative in runner.SOURCE_FILES:
                target=source/relative;target.parent.mkdir(parents=True,exist_ok=True)
                target.write_text("Own fixture source\n")
            (source/"app/Assets.xcassets").mkdir()
            inputs={"tests/runtime/IteratorRetirementProof.inc":"// own retirement proof fixture\n",
                    "native/include/EHRManagedIteratorProductionV1.h":"// own production table fixture\n",
                    "native/include/EHRManagedIteratorV1.h":"// own callback table fixture\n"}
            for relative,value in inputs.items():
                target=source/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(value)
            test=base/"OwnTest.mm";test.write_text('#include "IteratorRetirementProof.inc"\n')
            output=base/"Output";output.mkdir()
            project=runner.prepare_project(source,test,output,"ABCDEFGHIJ","org.example.ehrfixture")
            self.assertEqual((project/"IteratorRetirementProof.inc").read_text(),inputs["tests/runtime/IteratorRetirementProof.inc"])
            for relative in tuple(inputs)[1:]:self.assertEqual((project/relative).read_text(),inputs[relative])
            self.assertEqual((project/"EHRRuntimeProbe.xcodeproj/project.pbxproj").read_text().count('HEADER_SEARCH_PATHS = "$(SRCROOT)/native";'),2)

    def test_generated_xctest_paid_team(self):
        with tempfile.TemporaryDirectory() as temp:
            bundle = Path(temp); (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "org.example.ehrfixture.nativeruntimetests"}))
            with patch.object(runner.subprocess, "run", return_value=SimpleNamespace(stderr="TeamIdentifier=ABCDEFGHIJ\n")):
                runner.verify_test_bundle_team(bundle, "ABCDEFGHIJ", "org.example.ehrfixture")
            with patch.object(runner.subprocess, "run", return_value=SimpleNamespace(stderr="TeamIdentifier=WRONGTEAM0\n")):
                with self.assertRaisesRegex(ValueError, "required paid team"):
                    runner.verify_test_bundle_team(bundle, "ABCDEFGHIJ", "org.example.ehrfixture")

    def test_private_file_json_and_text(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp) / "own-device.local.json"
            p.write_text(json.dumps({"udid": UDID, "deviceIdentifier": IDENTIFIER}))
            self.assertEqual(runner.load_physical_device_file(p), {"udid": UDID, "identifier": IDENTIFIER})
            p.write_text(UDID + "\n")
            self.assertEqual(runner.load_physical_device_file(p)["udid"], UDID)
            p.write_text(IDENTIFIER)
            with self.assertRaisesRegex(ValueError, "physical iPhone UDID"):
                runner.load_physical_device_file(p)

    def test_private_device_file_inside_git_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp); (base / ".git").write_text("gitdir: own-fixture\n")
            p = base / "device.local.json"; p.write_text(UDID)
            with self.assertRaisesRegex(ValueError, "outside Git"):
                runner.load_physical_device_file(p)

    def test_exact_physical_identity_and_transport(self):
        requested = {"udid": UDID, "identifier": IDENTIFIER}
        self.assertEqual(runner.select_physical_device({"result": {"devices": [device()]}}, requested)["identifier"], IDENTIFIER)
        for invalid in [device("sameMachine"), device(product="iPad13,11")]:
            with self.assertRaises(ValueError):
                runner.select_physical_device({"result": {"devices": [invalid]}}, requested)
        with self.assertRaisesRegex(ValueError, "uniquely"):
            runner.select_physical_device({"result": {"devices": [device(), device()]}}, requested)
        with self.assertRaisesRegex(ValueError, "identity differs"):
            runner.select_physical_device({"result": {"devices": [device()]}}, {"udid": UDID, "identifier": "different"})

    def test_explicit_model_keeps_exact_physical_identity_and_rejects_coredevice_alias(self):
        requested={"udid":UDID,"identifier":IDENTIFIER}
        own=device("localNetwork",product="iPhone17,1")
        self.assertEqual(runner.select_physical_device({"result":{"devices":[own]}},requested,expected_product_type="iPhone17,1"),own)
        with self.assertRaisesRegex(ValueError,"model"):
            runner.select_physical_device({"result":{"devices":[own]}},requested)
        for model in ("*","iPad13,11","iPhone18,*","iPhone018,2",None):
            with self.subTest(model=model),self.assertRaisesRegex(ValueError,"exact physical iPhone model"):
                runner.select_physical_device({"result":{"devices":[own]}},requested,expected_product_type=model)
        alias=device();alias['hardwareProperties']['udid']='00000000-0000000000000002'
        with self.assertRaisesRegex(ValueError,"CoreDevice identity is not uniquely"):
            runner.select_physical_device({"result":{"devices":[device(),alias]}},requested)
        wrong=device();wrong['hardwareProperties']['platform']='macOS'
        with self.assertRaisesRegex(ValueError,"physical iPhone"):
            runner.select_physical_device({"result":{"devices":[wrong]}},requested)

    def test_explicit_nonphysical_reality_rejected_with_missing_field_compatibility(self):
        requested={"udid":UDID,"identifier":IDENTIFIER}
        physical=device("localNetwork");physical['hardwareProperties']['reality']='physical'
        self.assertEqual(runner.select_physical_device({"result":{"devices":[physical]}},requested),physical)
        self.assertEqual(runner.select_physical_device({"result":{"devices":[device()]}},requested)['identifier'],IDENTIFIER)
        for reality in ('simulated','virtual',None,''):
            invalid=device();invalid['hardwareProperties']['reality']=reality
            with self.subTest(reality=reality),self.assertRaisesRegex(ValueError,"explicitly identifies a nonphysical"):
                runner.select_physical_device({"result":{"devices":[invalid]}},requested)

    def test_candidate_pins_exact_all_four_and_tamper(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp); app = base / "Own.app"; pins = {}
            for relative in runner.RELATIVE_BINARIES:
                target = app / relative; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(b"original own fixture " + relative.encode()); pins[relative] = runner.hash_file(target)
            p = base / "pins.json"; p.write_text(json.dumps({"candidate_binary_sha256": pins}))
            self.assertEqual(runner.validate_candidate_pins(app, p), pins)
            (app / runner.RELATIVE_BINARIES[-1]).write_bytes(b"own changed fixture")
            with self.assertRaisesRegex(ValueError, "hash differs"):
                runner.validate_candidate_pins(app, p)
            p.write_text(json.dumps({"../other": "0" * 64}))
            with self.assertRaisesRegex(ValueError, "exactly the four"):
                runner.validate_candidate_pins(app, p)

    def test_physical_preflight_summary_has_no_identifiers(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp); output = base / "Output"; output.mkdir(); app = base / "Own.app"
            pins = {}
            for relative in runner.RELATIVE_BINARIES:
                target = app / relative; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(relative.encode()); pins[relative] = runner.hash_file(target)
            pinfile = base / "pins.json"; pinfile.write_text(json.dumps(pins))
            private = base / "device.local.json"; private.write_text(json.dumps({"udid": UDID, "deviceIdentifier": IDENTIFIER}))
            def own_run(arguments, log=None, cwd=None, timeout=180):
                args = [str(v) for v in arguments]
                if args[:4] == ["xcrun", "devicectl", "list", "devices"]:
                    Path(args[-1]).write_text(json.dumps({"result": {"devices": [device()]}}))
                elif args[:5] == ["xcrun", "devicectl", "device", "info", "details"]:
                    Path(args[-1]).write_text(json.dumps({"result": {"deviceProperties": {"bootState": "booted", "developerModeStatus": "enabled", "ddiServicesAvailable": True, "osVersionNumber": "26.7.1"}}}))
                elif args[:3] == ["xcrun", "xcdevice", "list"]:
                    return json.dumps([{"identifier": UDID, "simulator": False, "available": True, "modelCode": "iPhone18,2", "platform": "com.apple.platform.iphoneos"}])
                elif args[0] == "codesign":
                    return plistlib.dumps({"get-task-allow": True}).decode()
                else:
                    self.fail("Unexpected external operation in synthetic preflight")
                return ""
            with patch.object(runner, "run", side_effect=own_run):
                destination_file, destination, actual_pins, summary = runner.physical_preflight(app, private, pinfile, output)
            self.assertEqual(destination, "platform=iOS,id=" + UDID)
            self.assertEqual(destination_file.read_text().strip(), UDID)
            self.assertEqual(actual_pins, pins)
            self.assertNotIn(UDID, json.dumps(summary)); self.assertNotIn(IDENTIFIER, json.dumps(summary))
            self.assertFalse(summary["security_or_pairing_changes_performed"])
            self.assertEqual(destination_file.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
