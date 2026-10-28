import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import feature_inventory as f
import patch_dispatch_inventory as p


class LexicalSafetyTests(unittest.TestCase):
    def test_comments_and_embedded_code_are_not_discovered(self):
        source = f.Source("Fixture.cs", '''
// [HarmonyPatch(typeof(Fake), nameof(Fake.Bad))] class Commented {}
/* class OtherComment {} */
class Real {
 string a = "class StringType {} new BooleanOptionItem(1, \\\"Fake\\\", true)";
 string b = @"class VerbatimType {} ""escaped""";
 string c = $"prefix {Get("class NestedStringType {}")}";
 string d = """class RawType {} [HarmonyPatch]""";
}
''')
        self.assertEqual([t["name"] for t in source.types], ["Real"])
        self.assertEqual(source.hooks(), [])
        self.assertEqual(source.options(), [])

    def test_conditional_branches_and_opaque_directives_preserve_lines(self):
        original = '''class Test {
string s = @"
#if NO_SUCH_SYMBOL
not a directive
";
#if IL2CPP
void Selected() {
#else
void NotSelected() {
#endif
}
}
'''
        source = f.Source("Conditional.cs", original)
        declaration = source.types[0]
        self.assertEqual([m["name"] for m in p.methods(source, declaration)], ["Selected"])
        self.assertEqual(source.text.count("\n"), original.count("\n"))
        mono = f.Source("Conditional.cs", original, set())
        self.assertEqual([m["name"] for m in p.methods(mono, mono.types[0])], ["NotSelected"])

    def test_literal_evaluation_does_not_execute_expressions(self):
        self.assertEqual(f.literal(f.tokenize("0x1FUL")), 31)
        self.assertEqual(f.literal(f.tokenize("10_000 + Base_Id"), {"Base_Id": 25}), 10025)
        self.assertEqual(f.literal(f.tokenize("1 << 5")), 32)
        self.assertEqual(f.literal(f.tokenize("0.05f")), 0.05)
        self.assertIsNone(f.literal(f.tokenize('__import__("os").system("false")')))

    def test_patch_composition_binding_and_nested_identity(self):
        source = f.Source("Fixture.cs", '''namespace Example;
[HarmonyPatch(typeof(Target))]
class Container {
 [HarmonyPatch(nameof(Target.Call)), HarmonyPrefix, HarmonyPriority(100)]
 static bool Before(Target __instance, [HarmonyArgument(1)] ref int amount, out bool __state) { __state = true; return false; }
 [HarmonyPatch(typeof(Other), "Run")]
 class Nested {
  static void Postfix(ref int __result, bool __state) {}
 }
}
class Conventional {
 [HarmonyPatch(typeof(Other), nameof(Other.Run))]
 static void Prefix() {}
}
''')
        manifest = p.manifest([source])
        by_name = {c["qualified_type"]: c for c in manifest["patch_classes"]}
        before = by_name["Example.Container"]["callbacks_and_helpers"][0]
        self.assertEqual(before["callback_kinds"], ["Prefix"])
        self.assertEqual(before["target_templates"][0]["type"], "Target")
        self.assertEqual(before["target_templates"][0]["member"], "Call")
        self.assertEqual(before["parameters"][1]["injection"], "original_argument_by_HarmonyArgument")
        self.assertIn("mutable_original_argument", before["semantic_requirements"])
        self.assertIn("per_original_invocation_patch_class_state", before["semantic_requirements"])
        self.assertIn("Example.Container+Nested", by_name)
        self.assertEqual(by_name["Example.Conventional"]["callbacks_and_helpers"][0]["callback_kinds"], ["Prefix"])


class PinnedUpstreamIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not f.UPSTREAM_DEFAULT.is_dir():
            raise unittest.SkipTest("Pinned upstream checkout is not available")
        cls.inventory = f.inventory(f.UPSTREAM_DEFAULT)
        cls.roles = {r["name"]: r for r in cls.inventory["roles"]}
        cls.patch_types = {c["qualified_type"]: c for c in cls.inventory["patch_dispatch"]["patch_classes"]}

    def test_exact_pinned_source_scope_and_counts(self):
        self.assertEqual(self.inventory["upstream"]["commit"], f.PIN)
        self.assertEqual(self.inventory["counts"]["compiled_scope_cs_files"], 727)
        self.assertEqual(self.inventory["counts"]["excluded_CTA_cs_files"], 11)
        self.assertEqual(self.inventory["counts"]["role_enum_members_including_vanilla_aliases_and_sentinels"], 585)
        self.assertFalse(any(s["file"].startswith("CTA/") for s in self.inventory["source_files"]))
        self.assertTrue(all(f.PIN in role["source"]["url"] for role in self.roles.values()))

    def test_modes_are_exact_enum_values_not_assumed_flags(self):
        modes = {m["name"]: m["value"] for m in self.inventory["game_modes"]["members"]}
        self.assertEqual(modes["FFA"], 3)
        self.assertEqual(modes["DoomTag"], 18)
        self.assertEqual(modes["All"], 2147483647)
        self.assertEqual(len(modes) - 1, 18)

    def test_bait_real_defaults_ranges_and_central_behavior_reference(self):
        options = {o["label"]: o for o in self.inventory["option_sites"]
                   if o["source"]["file"] == "Roles/Standard/Addons/Common/Bait.cs" and o["label"]}
        self.assertEqual(set(options), {"BaitDelayMin", "BaitDelayMax", "BaitDelayNotify", "BaitNotification", "ReportBaitAtAllCost"})
        for name in ["BaitDelayMin", "BaitDelayMax"]:
            self.assertEqual(options[name]["default"], 0)
            self.assertEqual({k: options[name]["range"][k] for k in ["min", "max", "step"]}, {"min": 0, "max": 90, "step": 1})
        self.assertIs(options["BaitDelayNotify"]["default"], True)
        self.assertIs(options["BaitNotification"]["default"], False)
        self.assertIs(options["ReportBaitAtAllCost"]["default"], False)
        self.assertIn("Patches/PlayerControlPatch.cs", self.roles["Bait"]["reference_files"])
        self.assertFalse(self.roles["Bait"]["complete_EHR_role_compatibility"])

    def test_auto_setup_options_retain_values_without_inventing_generated_ids(self):
        options = {o.get("field"): o for o in self.inventory["option_sites"]
                   if o["source"]["file"].endswith("/Gardener.cs") and o["factory"] == "AutoSetupOption"}
        self.assertEqual(options["PlantRange"]["default"], 2.5)
        self.assertEqual(options["AbilityUseLimit"]["range"]["step"], 0.05)
        self.assertIsNone(options["PlantRange"]["resolved_id"])

    def test_murder_patch_preserves_prefix_postfix_state_and_target_binding(self):
        patch = self.patch_types["EHR.MurderPlayerPatch"]
        callbacks = {m["name"]: m for m in patch["callbacks_and_helpers"]}
        self.assertEqual(callbacks["Prefix"]["return_type"], "bool")
        self.assertIn("per_original_invocation_patch_class_state", callbacks["Prefix"]["semantic_requirements"])
        state = next(p for p in callbacks["Prefix"]["parameters"] if p["name"] == "__state")
        self.assertEqual(state["modifiers"], ["ref"])
        self.assertEqual(callbacks["Prefix"]["target_templates"][0]["member"], "MurderPlayer")
        self.assertEqual(callbacks["Postfix"]["parameters"][-1]["name"], "__state")

    def test_dynamic_state_machine_resolvers_and_runtime_registration_are_explicit(self):
        manifest = self.inventory["patch_dispatch"]
        self.assertEqual(manifest["counts"]["dynamic_target_classes"], 4)
        show = self.patch_types["EHR.ShowRoleMoveNextPatch"]
        resolver = next(m for m in show["callbacks_and_helpers"] if "TargetMethod" in m["helper_kinds"])
        self.assertIn("GetStateMachineMoveNext", resolver["helper_body_expression"])
        self.assertIn("IntroCutscene . ShowRole", resolver["helper_body_expression"])
        registrations = manifest["runtime_registration_sites"]
        self.assertEqual(sum(r["operation"] == "PatchAll" for r in registrations), 3)
        self.assertEqual(sum(r["operation"] == "Patch" for r in registrations), 2)
        self.assertEqual(sum(r["operation"] == "UnpatchSelf" for r in registrations), 2)
        self.assertEqual(manifest["counts"]["callback_kind_sites"], {"Prefix": 202, "Postfix": 131, "Finalizer": 1})

    def test_patch_overload_type_arguments_do_not_replace_inherited_declaring_type(self):
        patch = self.patch_types["EHR.HashRandomPatch"]
        callback = next(m for m in patch["callbacks_and_helpers"] if m["name"] == "MinMaxNext")
        target = callback["target_templates"][0]
        self.assertEqual(target["type"], "HashRandom")
        self.assertEqual(target["member"], "Next")
        self.assertEqual(target["argument_types"], ["int", "int"])

    def test_dependency_conditions_and_native_coverage_do_not_overclaim(self):
        dependencies = {d["package"]: d for d in self.inventory["package_dependencies"]}
        self.assertEqual(dependencies["AmongUs.GameLibs.Steam"]["version"], "2026.9.29")
        self.assertIn("IL2CPP", dependencies["AmongUs.GameLibs.Steam"]["group_condition"])
        self.assertEqual(self.inventory["counts"]["complete_native_EHR_roles_verified"], 0)
        self.assertFalse(any(r["complete_EHR_role_compatibility"] for r in self.roles.values()))

    def test_runtime_proof_promotes_only_observed_boot_and_version_evidence(self):
        with tempfile.TemporaryDirectory() as temp:
            proof = Path(temp) / "proof.json"
            proof.write_text(json.dumps({"status": "live_sample", "gameAssemblyFound": True,
                "nativeHooksBeforeGetter": {"broadcastVersionCallbacks": 0},
                "nativeHooks": {"broadcastVersionCallbacks": 1, "murderCallbacks": 999},
                "versionGetter": {"success": True}, "multiplayerVerified": True}))
            audit = f.coverage(f.NATIVE_DEFAULT, proof)
        self.assertEqual(audit["runtime_evidence"]["actual_version_hook"], "verified_under_app_hosted_XCTest")
        self.assertEqual(audit["runtime_evidence"]["actual_murder_callback"], "not_verified")
        self.assertEqual(audit["runtime_evidence"]["multiplayer"], "not_verified")


if __name__ == "__main__":
    unittest.main()
