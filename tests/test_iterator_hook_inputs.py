"""Original declaration fixtures only; no game inputs or runtime execution."""
from copy import deepcopy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from iterator_hook_inputs import ITERATOR_METHODS, OWNER, merge_iterator_inputs


class IteratorHookInputTests(unittest.TestCase):
    def setUp(self):
        self.base = {"metadata_version": 31, "framework_uuid": "own-fixture",
                     "preferred_image_base": "0x0", "input_pins": {
                         "framework": {"sha256": "owned-framework", "size": 100},
                         "metadata": {"sha256": "owned-metadata", "size": 30}}, "methods": []}
        self.carrier = deepcopy(self.base)
        self.carrier.update(schema="ehr.harmony-native-target-map.v1", selectors=[])
        self.carrier["input_pins"]["selectors"] = {"sha256": "own-extra-provenance"}
        for name, returns, rva, _, _ in ITERATOR_METHODS:
            self.carrier["selectors"].append({"status": "exact_metadata_native_candidate",
                "candidate": {"declaring_type": OWNER, "name": name, "owning_image": "mscorlib.dll",
                    "return_type": returns, "parameter_types": [], "static": False,
                    "generic": False, "abstract": False, "shared_entry": False,
                    "native_rva": rva, "registered_module_entry_count": 1,
                    "registered_generic_entry_count": 0, "metadata_token": "0x6000001"}})
        self.contracts = {"schema": "ehr.native-hook-contracts.v1", "methods": {}}

    def test_exact_pin_merge_preserves_inputs_and_explicit_shapes(self):
        before = deepcopy((self.base, self.carrier, self.contracts))
        merged, contracts, names = merge_iterator_inputs(self.base, self.carrier, self.contracts)
        self.assertEqual((self.base, self.carrier, self.contracts), before)
        self.assertEqual(len(names), 3)
        self.assertEqual([m["return_type"] for m in merged["methods"]], ["System.Boolean", "System.Object", "System.Void"])
        self.assertTrue(all(not value["static"] for value in contracts["methods"].values()))

    def test_foreign_game_pins_rejected(self):
        for key in ("framework_uuid", "metadata_version", "preferred_image_base"):
            wrong = deepcopy(self.carrier); wrong[key] = "foreign"
            with self.assertRaises(ValueError): merge_iterator_inputs(self.base, wrong, self.contracts)
        wrong = deepcopy(self.carrier); wrong["input_pins"]["metadata"]["sha256"] = "foreign"
        with self.assertRaises(ValueError): merge_iterator_inputs(self.base, wrong, self.contracts)

    def test_shared_generic_wrong_abi_address_and_ambiguous_entries_rejected(self):
        for key, bad in (("shared_entry", True), ("generic", True), ("return_type", "System.Int32"),
                         ("static", True), ("owning_image", "foreign.dll"), ("native_rva", "0x1234"),
                         ("registered_module_entry_count", 2), ("registered_generic_entry_count", 1)):
            wrong = deepcopy(self.carrier); wrong["selectors"][0]["candidate"][key] = bad
            with self.subTest(key=key), self.assertRaises(ValueError):
                merge_iterator_inputs(self.base, wrong, self.contracts)
        wrong = deepcopy(self.carrier); wrong["selectors"].append(deepcopy(wrong["selectors"][0]))
        with self.assertRaises(ValueError): merge_iterator_inputs(self.base, wrong, self.contracts)

    def test_duplicate_existing_hook_rejected(self):
        self.base["methods"].append({"declaring_type": OWNER, "name": "MoveNext"})
        with self.assertRaises(ValueError): merge_iterator_inputs(self.base, self.carrier, self.contracts)


if __name__ == "__main__":
    unittest.main()
