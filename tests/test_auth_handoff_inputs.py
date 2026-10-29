from copy import deepcopy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import auth_handoff_hook_inputs as rules


class AuthHandoffInputsTests(unittest.TestCase):
    def setUp(self):
        self.base = {"metadata_version": 31, "framework_uuid": rules.UUID, "preferred_image_base": "0x0",
            "input_pins": {"framework": {"sha256": rules.SOURCE_SHA, "size": 100},
                           "metadata": {"sha256": rules.METADATA_SHA, "size": 10}},
            "methods": [{"declaring_type": "OwnExisting", "name": "Callback", "native_rva": "0x1000"}]}
        self.report = deepcopy(self.base)
        self.report.update(schema="ehr.harmony-native-target-map.v1", selectors=[])
        for owner, name, image, returns, params, rva, token in [r[:7] for r in rules.METHODS] + [rules.GETTER]:
            self.report["selectors"].append({"status": "exact_metadata_native_candidate", "candidate": {
                "declaring_type": owner, "name": name, "owning_image": image, "return_type": returns,
                "parameter_types": params, "native_rva": rva, "metadata_token": token, "static": False,
                "generic": False, "abstract": False, "shared_entry": False,
                "registered_module_entry_count": 1, "registered_generic_entry_count": 0}})
        self.contracts = {"schema": "ehr.native-hook-contracts.v1", "methods": {"own-existing": {"static": True}}}
        self.manifest = {"framework_uuid": rules.UUID, "source_sha256": rules.SOURCE_SHA, "hooks": []}
        for i, (owner, name, _, returns, params, rva, token, symbol, _) in enumerate(rules.METHODS):
            self.manifest["hooks"].append({"method": owner + "." + name, "original_rva": rva, "method_rva": rva,
                "metadata_token": token, "symbol": symbol,
                "signature": {"return": returns, "parameters": params, "static": False},
                "trampoline_rva": hex(0x2000 + i * 64)})

    def test_four_exact_selectors_include_nonhook_type_getter(self):
        rows = rules.selectors()["selectors"]
        self.assertEqual(len(rows), 4)
        self.assertEqual(rows[-1]["methodKind"], "Getter")
        self.assertEqual(rows[-1]["returnType"], rules.GETTER[3])
        self.assertEqual(rows[1]["parameterTypes"][0], rules.PREFIX + "LoginOptions&")

    def test_merge_preserves_catalog_and_does_not_hook_getter_or_mutate_inputs(self):
        before = deepcopy((self.base, self.report, self.contracts))
        merged, contracts, names = rules.merge_auth_handoff_inputs(self.base, self.report, self.contracts)
        self.assertEqual((self.base, self.report, self.contracts), before)
        self.assertEqual(merged["methods"][:-3], self.base["methods"])
        self.assertEqual(contracts["methods"]["own-existing"], {"static": True})
        self.assertEqual(len(names), 3)
        self.assertFalse(any(m["name"] == "get_Type" for m in merged["methods"]))

    def test_signature_generic_alias_and_getter_changes_rejected(self):
        changes = [(i, k, v) for i in range(4) for k, v in (
            ("generic", True), ("abstract", True), ("shared_entry", True), ("static", True),
            ("registered_module_entry_count", 2), ("registered_module_entry_count", True),
            ("registered_generic_entry_count", 1), ("native_rva", "0x1000"),
            ("metadata_token", "0x600ffff"), ("owning_image", "Foreign.dll"))]
        changes += [(1, "parameter_types", [rules.PREFIX + "LoginOptions", "System.Object", rules.PREFIX + "OnLoginCallback"]),
                    (2, "parameter_types", [rules.PREFIX + "Credentials"]), (3, "return_type", "System.Int32")]
        for i, key, value in changes:
            report = deepcopy(self.report); report["selectors"][i]["candidate"][key] = value
            with self.subTest(index=i, key=key), self.assertRaises(ValueError):
                rules.merge_auth_handoff_inputs(self.base, report, self.contracts)

    def test_identity_pins_and_candidate_cardinality_rejected(self):
        for key, value in (("framework_uuid", "foreign"), ("metadata_version", 30), ("preferred_image_base", "0x1000")):
            report = deepcopy(self.report); report[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): rules.validate_report(self.base, report)
        for key in ("framework", "metadata"):
            report = deepcopy(self.report); report["input_pins"][key]["size"] += 1
            with self.subTest(pin=key), self.assertRaises(ValueError): rules.validate_report(self.base, report)
        for rows in (self.report["selectors"][:-1], self.report["selectors"] + [self.report["selectors"][0]],
                     [self.report["selectors"][0]] * 4):
            report = deepcopy(self.report); report["selectors"] = rows
            with self.assertRaises(ValueError): rules.candidates(report)

    def test_existing_duplicate_and_numerically_equal_entry_alias_rejected(self):
        for fact in rules.METHODS:
            for row in ({"declaring_type": fact[0], "name": fact[1], "native_rva": "0x1004"},
                        {"declaring_type": "OwnAlias", "name": "Callback", "native_rva": str(int(fact[5], 0))}):
                base = deepcopy(self.base); base["methods"].append(row)
                with self.subTest(method=fact[1]), self.assertRaises(ValueError):
                    rules.merge_auth_handoff_inputs(base, self.report, self.contracts)
            contracts = deepcopy(self.contracts); contracts["methods"][fact[0] + "." + fact[1]] = {}
            with self.assertRaises(ValueError): rules.merge_auth_handoff_inputs(self.base, self.report, contracts)

    def test_header_requires_exact_manifest_and_bounded_distinct_trampolines(self):
        text = rules.binding_header(self.manifest)
        for fact in rules.METHODS: self.assertIn(fact[-1], text)
        self.assertIn("EHRAuthHandoffCredentialTypeGetterRVA = " + rules.GETTER[5], text)
        for key, bad in (("symbol", "_own_wrong"), ("metadata_token", "0x6000001"),
                         ("original_rva", "0x1000"), ("trampoline_rva", "0x2040"),
                         ("trampoline_rva", rules.GETTER[5]), ("trampoline_rva", "0x2001"),
                         ("trampoline_rva", "0x10000000000000000"), ("trampoline_rva", "0x0")):
            manifest = deepcopy(self.manifest); manifest["hooks"][0][key] = bad
            with self.subTest(key=key, bad=bad), self.assertRaises(ValueError): rules.binding_header(manifest)
        for key in ("source_sha256", "framework_uuid"):
            manifest = deepcopy(self.manifest); manifest[key] = "foreign"
            with self.assertRaises(ValueError): rules.binding_header(manifest)
        manifest = deepcopy(self.manifest); manifest["hooks"].append(deepcopy(manifest["hooks"][0]))
        with self.assertRaises(ValueError): rules.binding_header(manifest)

    def test_header_rejects_shadow_method_entry_or_missing_entry_for_every_hook(self):
        for index, fact in enumerate(rules.METHODS):
            for value in (None, "0x0", hex(int(fact[5], 0) + 4), True):
                manifest = deepcopy(self.manifest)
                if value is None:
                    del manifest["hooks"][index]["method_rva"]
                else:
                    manifest["hooks"][index]["method_rva"] = value
                with self.subTest(hook=index, value=value), self.assertRaises(ValueError):
                    rules.binding_header(manifest)


if __name__ == "__main__": unittest.main()
