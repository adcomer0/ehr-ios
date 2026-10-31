"""Own fixtures for exact entry ownership, callback ABI and source provenance.

No game, account, credential, signing, device or native callback is executed.
"""
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import itch_auth_hook_inputs as rules
import prepare_itch_auth_map as mapper


def fixtures():
    base = {"metadata_version": 31, "framework_uuid": rules.UUID, "preferred_image_base": "0x0",
        "input_pins": {"framework": {"sha256": rules.SOURCE_SHA, "size": 7},
                       "metadata": {"sha256": rules.METADATA_SHA, "size": 5}},
        "methods": [{"declaring_type": "OwnExisting", "name": "Callback", "native_rva": "0x1000"},
                    {"declaring_type": "EOSManager", "name": "LoginWithCorrectPlatform", "native_rva": "0x1b0fd70"}]}
    report = deepcopy(base)
    report.update(schema="ehr.harmony-native-target-map.v1", selectors=[],
                  runtime_execution_performed=False, native_hooks_installed=False)
    for selector, fact in zip(rules.selectors()["selectors"], rules.METHODS):
        owner, name, image, returns, params, rva, token, _constant = fact
        report["selectors"].append({"selector_id": selector["selectorId"], "selector": selector,
            "status": "exact_metadata_native_candidate", "candidate": {
                "declaring_type": owner, "name": name, "owning_image": image, "return_type": returns,
                "parameter_types": list(params), "native_rva": rva, "metadata_token": token,
                "static": False, "generic": False, "abstract": False, "shared_entry": False,
                "registered_module_entry_count": 1, "registered_generic_entry_count": 0,
                "association": "offline_codegen_module_token_rid_candidate", "runtime_association_verified": False,
                "first_instruction_relocation": {"status": "supported_at_report_probe_slot"}}})
    contracts = {"schema": "ehr.native-hook-contracts.v1", "methods": {
        "OwnExisting.Callback": {"static": True},
        "EOSManager.LoginWithCorrectPlatform": {"symbol": "_own_existing_retry_guard"}}}
    manifest = {"framework_uuid": rules.UUID, "source_sha256": rules.SOURCE_SHA, "hooks": [
        {"method": rules.TARGET, "original_rva": rules.IMPL[5], "method_rva": rules.IMPL[5],
         "metadata_token": rules.IMPL[6], "symbol": rules.SYMBOL,
         "signature": {"return": "System.Void", "parameters": list(rules.IMPL[4]), "static": False},
         "trampoline_rva": "0x2000"},
        {"method": "EOSManager.LoginWithCorrectPlatform", "original_rva": "0x1b0fd70",
         "method_rva": "0x1b0fd70", "symbol": "_own_existing_retry_guard", "trampoline_rva": "0x3000"}]}
    manifest["hooks"].append({"method": rules.FINAL[0] + "." + rules.FINAL[1],
        "original_rva": rules.FINAL[5], "method_rva": rules.FINAL[5],
        "metadata_token": rules.FINAL[6], "symbol": rules.FINAL_SYMBOL,
        "signature": {"return": rules.FINAL[3], "parameters": [], "static": False},
        "trampoline_rva": "0x4000"})
    for index, (fact, symbol, _constant) in enumerate(rules.HOOKS[2:]):
        manifest["hooks"].append({"method": fact[0] + "." + fact[1],
            "original_rva": fact[5], "method_rva": fact[5], "metadata_token": fact[6], "symbol": symbol,
            "signature": {"return": fact[3], "parameters": list(fact[4]), "static": False},
            "trampoline_rva": hex(0x5000 + index * 0x1000)})
    return base, report, contracts, manifest


class ItchAuthInputsTests(unittest.TestCase):
    def setUp(self):
        self.base, self.report, self.contracts, self.manifest = fixtures()

    def test_four_explicit_hooks_preserve_callbacks_and_leave_connect_read_only(self):
        before = deepcopy((self.base, self.report, self.contracts))
        merged, contracts, names = rules.merge_itch_auth_inputs(self.base, self.report, self.contracts)
        self.assertEqual(before, (self.base, self.report, self.contracts))
        self.assertEqual(names, [fact[0] + "." + fact[1] for fact, _symbol, _constant in rules.HOOKS])
        count = len(rules.HOOKS)
        self.assertEqual(merged["methods"][:-count], self.base["methods"])
        self.assertEqual(merged["methods"][-count]["parameters"], [
            {"type": "Epic.OnlineServices.Connect.OnLoginCallback"}, {"type": "System.Action"}])
        self.assertTrue(all(row["parameters"] == [] for row in merged["methods"][-count + 1:]))
        self.assertTrue(all(row["static"] is False for row in merged["methods"][-count:]))
        self.assertEqual(contracts["methods"][names[1]]["symbol"], rules.FINAL_SYMBOL)
        self.assertEqual(contracts["methods"]["EOSManager.LoginWithCorrectPlatform"],
                         self.contracts["methods"]["EOSManager.LoginWithCorrectPlatform"])
        self.assertEqual(contracts["methods"][rules.TARGET]["symbol"], rules.SYMBOL)
        self.assertNotIn("RetryAuthAndLoginImpl", names)
        self.assertEqual(len(rules.selectors()["selectors"]), len(rules.METHODS))
        self.assertIn("const void *methodInfo", rules.IMPL_NATIVE_ABI)
        self.assertIn("void *loginOptionsByRef", rules.CONNECT_NATIVE_ABI)
        self.assertNotIn("AccountManager.SignInFail", names)
        self.assertNotIn(rules.CONNECT_LOGIN[0] + ".Login", names)

    def test_every_helper_signature_and_unique_registration_is_required(self):
        mutations = [("static", True), ("generic", True), ("abstract", True), ("shared_entry", True),
            ("registered_module_entry_count", 2), ("registered_module_entry_count", True),
            ("registered_generic_entry_count", 1), ("registered_generic_entry_count", False),
            ("native_rva", "0x1000"), ("metadata_token", "0x600ffff"),
            ("owning_image", "OwnForeign.dll"), ("declaring_type", "OwnForeign"),
            ("return_type", "System.Object"), ("association", "guessed"),
            ("runtime_association_verified", True)]
        for index in range(len(rules.METHODS)):
            for key, value in mutations:
                report = deepcopy(self.report); report["selectors"][index]["candidate"][key] = value
                with self.subTest(method=index, key=key), self.assertRaises(ValueError):
                    rules.validate_report(self.base, report)
        for index in (0, 2, 11, 12, 13, 14, 16, 17):
            report = deepcopy(self.report)
            report["selectors"][index]["candidate"]["parameter_types"] = ["System.Object"]
            with self.subTest(callback_or_byref=index), self.assertRaises(ValueError):
                rules.validate_report(self.base, report)

    def test_cardinality_selector_spoof_and_runtime_claims_rejected(self):
        for rows in (self.report["selectors"][:-1], self.report["selectors"] + [self.report["selectors"][0]],
                     [self.report["selectors"][0]] * len(rules.METHODS), [None] * len(rules.METHODS)):
            report = deepcopy(self.report); report["selectors"] = rows
            with self.assertRaises(ValueError): rules.validate_report(self.base, report)
        for key, value in (("runtime_execution_performed", True), ("native_hooks_installed", True),
                           ("schema", "own-unrelated-schema")):
            report = deepcopy(self.report); report[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): rules.validate_report(self.base, report)
        report = deepcopy(self.report); report["selectors"][0]["selector"]["parameterTypes"] = []
        with self.assertRaises(ValueError): rules.validate_report(self.base, report)
        report = deepcopy(self.report); report["selectors"][0]["candidate"]["first_instruction_relocation"] = None
        with self.assertRaises(ValueError): rules.validate_report(self.base, report)

    def test_pins_require_exact_source_and_positive_integer_sizes(self):
        for key, value in (("metadata_version", 30), ("framework_uuid", "foreign"), ("preferred_image_base", "0x1000")):
            report = deepcopy(self.report); report[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): rules.validate_report(self.base, report)
        for name in ("framework", "metadata"):
            for key, value in (("sha256", "0" * 64), ("size", 0), ("size", True), ("size", -1)):
                base, report = deepcopy(self.base), deepcopy(self.report)
                base["input_pins"][name][key] = value; report["input_pins"][name][key] = value
                with self.subTest(name=name, key=key, value=value), self.assertRaises(ValueError):
                    rules.validate_report(base, report)
            report = deepcopy(self.report); report["input_pins"][name]["size"] += 1
            with self.assertRaises(ValueError): rules.validate_report(self.base, report)

    def test_duplicate_hook_and_numeric_alias_rejected_without_mutation(self):
        for existing in ({"declaring_type": rules.IMPL[0], "name": rules.IMPL[1], "native_rva": "0x1004"},
                         {"declaring_type": "OwnAlias", "name": "Alias", "native_rva": str(int(rules.IMPL[5], 0))}):
            base = deepcopy(self.base); base["methods"].append(existing); before = deepcopy(base)
            with self.assertRaises(ValueError): rules.merge_itch_auth_inputs(base, self.report, self.contracts)
            self.assertEqual(base, before)
        contracts = deepcopy(self.contracts); contracts["methods"][rules.TARGET] = {}
        with self.assertRaises(ValueError): rules.merge_itch_auth_inputs(self.base, self.report, contracts)
        for bad in (True, "0x0", "0x1001", "0x10000000000000000"):
            base = deepcopy(self.base); base["methods"][0]["native_rva"] = bad
            with self.subTest(rva=bad), self.assertRaises(ValueError): rules.merge_itch_auth_inputs(base, self.report, self.contracts)

    def test_header_revalidates_helpers_and_final_installed_contract(self):
        header = rules.binding_header(self.manifest, self.report)
        self.assertIn(rules.TRAMPOLINE + " = 0x2000;", header)
        for fact in rules.METHODS: self.assertIn(fact[7] + " = " + fact[5] + ";", header)
        self.assertIn(rules.SOURCE_SHA, header); self.assertIn(rules.METADATA_SHA, header)
        self.assertIn("EHRItchAuthFrameworkUUID[16]", header)
        for key, value in (("symbol", "_own_other"), ("metadata_token", "0x600ffff"),
                           ("method_rva", "0x1000"), ("original_rva", "0x1000"),
                           ("trampoline_rva", "0x2001"), ("trampoline_rva", "0x0"),
                           ("trampoline_rva", "0x10000000000000000"),
                           ("trampoline_rva", "0x3000"), ("trampoline_rva", rules.METHODS[-1][5])):
            manifest = deepcopy(self.manifest); manifest["hooks"][0][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError): rules.binding_header(manifest, self.report)
        for key in ("framework_uuid", "source_sha256"):
            manifest = deepcopy(self.manifest); manifest[key] = "foreign"
            with self.assertRaises(ValueError): rules.binding_header(manifest, self.report)
        report = deepcopy(self.report); report["selectors"][14]["candidate"]["parameter_types"] = []
        with self.assertRaises(ValueError): rules.binding_header(self.manifest, report)

    def test_header_rejects_duplicate_ownership_even_with_different_names(self):
        for key, value in (("original_rva", rules.IMPL[5]), ("method_rva", rules.IMPL[5]),
                           ("symbol", rules.SYMBOL), ("stub_rva", "0x2000"), ("got_rva", "0x2000")):
            manifest = deepcopy(self.manifest); manifest["hooks"][1][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): rules.binding_header(manifest, self.report)
        manifest = deepcopy(self.manifest); manifest["hooks"].append(deepcopy(manifest["hooks"][0]))
        with self.assertRaises(ValueError): rules.binding_header(manifest, self.report)

    def test_passive_completion_is_exact_void_instance_and_has_its_own_original_trampoline(self):
        for key, value in (("metadata_token", "0x600ffff"), ("method_rva", rules.IMPL[5]),
                           ("symbol", rules.SYMBOL), ("trampoline_rva", "0x2000"),
                           ("signature", {"return": "System.Boolean", "parameters": [], "static": False})):
            manifest = deepcopy(self.manifest); manifest["hooks"][2][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): rules.binding_header(manifest, self.report)
        manifest = deepcopy(self.manifest); manifest["hooks"].pop(2)
        with self.assertRaises(ValueError): rules.binding_header(manifest, self.report)
        report = deepcopy(self.report); report["selectors"][rules.METHODS.index(rules.FINAL)]["candidate"]["first_instruction_relocation"] = {"status": "unsupported"}
        with self.assertRaises(ValueError): rules.validate_report(self.base, report)

    def test_all_hook_owners_and_entry_aliases_are_rejected(self):
        for fact, symbol, _constant in rules.HOOKS:
            target = fact[0] + "." + fact[1]
            base = deepcopy(self.base)
            base["methods"].append({"declaring_type": "OwnOtherOwner", "name": "Alias", "native_rva": str(int(fact[5], 0))})
            with self.subTest(target=target), self.assertRaises(ValueError):
                rules.merge_itch_auth_inputs(base, self.report, self.contracts)
            contracts = deepcopy(self.contracts); contracts["methods"][target] = {"symbol": "_own_legacy_handoff"}
            with self.subTest(contract=target), self.assertRaises(ValueError):
                rules.merge_itch_auth_inputs(self.base, self.report, contracts)
            manifest = deepcopy(self.manifest)
            selected = next(row for row in manifest["hooks"] if row["method"] == target)
            selected["trampoline_rva"] = "0x3000"
            with self.subTest(trampoline=target), self.assertRaises(ValueError):
                rules.binding_header(manifest, self.report)
            self.assertNotEqual(symbol, "_own_legacy_handoff")

    def test_existing_connect_observer_is_preserved_without_new_hook_ownership(self):
        base, contracts = deepcopy(self.base), deepcopy(self.contracts)
        target = rules.CONNECT_LOGIN[0] + ".Login"
        existing = {"declaring_type": rules.CONNECT_LOGIN[0], "name": "Login", "native_rva": rules.CONNECT_LOGIN[5]}
        base["methods"].append(existing)
        contracts["methods"][target] = {"symbol": "_own_existing_passive_observer"}
        merged, extra, names = rules.merge_itch_auth_inputs(base, self.report, contracts)
        self.assertEqual(merged["methods"][:-len(rules.HOOKS)], base["methods"])
        self.assertEqual(extra["methods"][target], contracts["methods"][target])
        self.assertNotIn(target, names)

    def test_silent_hook_requires_relocation_and_readonly_connect_requires_exact_byref(self):
        for fact in (rules.SILENT,):
            index = rules.METHODS.index(fact)
            report = deepcopy(self.report); report["selectors"][index]["candidate"]["first_instruction_relocation"] = {"status": "unsupported"}
            with self.subTest(method=fact[1]), self.assertRaises(ValueError): rules.validate_report(self.base, report)
        report = deepcopy(self.report)
        report["selectors"][rules.METHODS.index(rules.CONNECT_LOGIN)]["candidate"]["parameter_types"][0] = rules.CONNECT + "LoginOptions"
        with self.assertRaises(ValueError): rules.validate_report(self.base, report)
        report = deepcopy(self.report)
        report["selectors"][rules.METHODS.index(rules.CONNECT_LOGIN)]["candidate"]["first_instruction_relocation"] = {"status": "unsupported"}
        self.assertEqual(len(rules.validate_report(self.base, report)), len(rules.METHODS))
        header = rules.binding_header(self.manifest, self.report)
        self.assertIn("EHRItchAuthSilentTrampolineRVA = 0x5000;", header)
        self.assertNotIn("EHRItchAuthConnectLoginTrampolineRVA", header)
        self.assertIn("EHRItchAuthConnectLoginRVA = 0x1aab220;", header)
        self.assertIn("EHRItchAuthFailureUIRVA = 0x1b05eac;", header)

    def test_standalone_guest_boundary_requires_exact_void_hook_and_readonly_string_getter(self):
        selector_rows = rules.selectors()["selectors"]
        getter_index = rules.METHODS.index(rules.GUEST_PRODUCT_USER)
        boundary_index = rules.METHODS.index(rules.GUEST_MIGRATION)
        self.assertEqual(selector_rows[getter_index]["methodKind"], "Getter")
        self.assertEqual(selector_rows[getter_index]["returnType"], "System.String")
        self.assertEqual(selector_rows[boundary_index]["returnType"], "System.Void")
        self.assertEqual(selector_rows[boundary_index]["parameterTypes"], [])
        _merged, contracts, names = rules.merge_itch_auth_inputs(self.base, self.report, self.contracts)
        self.assertNotIn("EOSManager.get_DeviceIDProductUserId", names)
        self.assertIn("EOSManager.CheckGuestAccountMigrationStuff", names)
        self.assertEqual(contracts["methods"]["EOSManager.CheckGuestAccountMigrationStuff"]["symbol"],
                         "_ehr_native_eos_itch_guest_migration")
        for index, key, value in ((getter_index, "return_type", "System.Object"),
                                  (getter_index, "metadata_token", "0x60000be"),
                                  (boundary_index, "parameter_types", ["System.Boolean"]),
                                  (boundary_index, "static", True),
                                  (boundary_index, "first_instruction_relocation", {"status": "unsupported"})):
            report = deepcopy(self.report); report["selectors"][index]["candidate"][key] = value
            with self.subTest(index=index, key=key), self.assertRaises(ValueError): rules.validate_report(self.base, report)
        header = rules.binding_header(self.manifest, self.report)
        self.assertIn("EHRItchAuthDeviceIDProductUserIdRVA = 0x1b0da60;", header)
        self.assertIn("EHRItchAuthGuestMigrationRVA = 0x1b126fc;", header)
        self.assertIn("EHRItchAuthGuestMigrationTrampolineRVA = 0x6000;", header)
        manifest = deepcopy(self.manifest)
        manifest["hooks"] = [row for row in manifest["hooks"] if row["method"] != "EOSManager.CheckGuestAccountMigrationStuff"]
        with self.assertRaises(ValueError): rules.binding_header(manifest, self.report)

    def test_prepare_hash_and_uuid_fail_before_mapping(self):
        with tempfile.TemporaryDirectory() as temp:
            framework, metadata = Path(temp) / "own-native", Path(temp) / "own-metadata"
            framework.write_bytes(b"OWNNATV"); metadata.write_bytes(b"OWNMD")
            for changes in ({}, {"framework": "0" * 64}, {"metadata": "0" * 64}):
                hashes = {framework: rules.SOURCE_SHA, metadata: rules.METADATA_SHA}
                for key, value in changes.items(): hashes[framework if key == "framework" else metadata] = value
                with patch.object(mapper, "digest", side_effect=lambda path: hashes[path]), \
                     patch.object(mapper, "MachO", return_value=SimpleNamespace(uuid="foreign")), \
                     patch.object(mapper, "build_report") as build, self.assertRaises(ValueError):
                    mapper.prepare(framework, metadata, self.base)
                build.assert_not_called()

    def test_prepare_detects_equal_size_timestamp_restored_change(self):
        with tempfile.TemporaryDirectory() as temp:
            framework, metadata = Path(temp) / "own-native", Path(temp) / "own-metadata"
            framework.write_bytes(b"OWNNATV"); metadata.write_bytes(b"OWNMD")
            hashes = [rules.SOURCE_SHA, rules.METADATA_SHA, "0" * 64]
            with patch.object(mapper, "digest", side_effect=hashes), \
                 patch.object(mapper, "MachO", return_value=SimpleNamespace(uuid=rules.UUID)), \
                 patch.object(mapper, "NestedMetadata", return_value=object()), \
                 patch.object(mapper, "build_report", return_value=deepcopy(self.report)), \
                 self.assertRaisesRegex(ValueError, "contents changed"):
                mapper.prepare(framework, metadata, self.base)

    def test_cli_outputs_private_declarations_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); output = root / "selectors.json"
            command = [sys.executable, str(ROOT / "tools/itch_auth_hook_inputs.py"), "selectors", "--output", str(output)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(output.read_text()), rules.selectors())
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
            before = output.read_bytes()
            self.assertNotEqual(subprocess.run(command, capture_output=True, timeout=10).returncode, 0)
            self.assertEqual(output.read_bytes(), before)
            (root / ".git").write_text("gitdir: own-fixture")
            with self.assertRaisesRegex(ValueError, "outside Git"): rules.private_output(root / "next.json")
            self.assertFalse((root / "next.json").exists())

    def test_cli_merge_and_header_require_report_and_preserve_existing_catalog(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name, value in (("base", self.base), ("report", self.report),
                                ("contracts", self.contracts), ("manifest", self.manifest)):
                (root / (name + ".json")).write_text(json.dumps(value))
            merge = [sys.executable, str(ROOT / "tools/itch_auth_hook_inputs.py"), "merge"]
            for name in ("base", "report", "contracts"): merge += ["--" + name, str(root / (name + ".json"))]
            merge += ["--output", str(root / "merged")]
            result = subprocess.run(merge, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            merged = json.loads((root / "merged/itch-auth-hook-map.local.json").read_text())
            self.assertEqual(merged["methods"][:-len(rules.HOOKS)], self.base["methods"])
            self.assertEqual(stat.S_IMODE((root / "merged").stat().st_mode), 0o700)
            header = [sys.executable, str(ROOT / "tools/itch_auth_hook_inputs.py"), "header",
                      "--manifest", str(root / "manifest.json"), "--output", str(root / "binding.h")]
            self.assertNotEqual(subprocess.run(header, capture_output=True, timeout=10).returncode, 0)
            self.assertFalse((root / "binding.h").exists())
            result = subprocess.run(header + ["--report", str(root / "report.json")], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(rules.TRAMPOLINE, (root / "binding.h").read_text())


if __name__ == "__main__": unittest.main()
