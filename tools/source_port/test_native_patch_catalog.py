import copy
import unittest
from generate_native_patch_catalog import PIN, emit, join


def fixture():
    identifier = "a" * 20
    candidate = dict(declaring_type="Own.Sample", owning_image="Own.dll", name="TryRead",
        parameter_types=["System.Int32&"], return_type="System.Boolean", static=False,
        shared_entry=False, generic=False, abstract=False, native_rva="0x1000")
    target = dict(selector_id=identifier, status="exact_metadata_native_candidate", native_rva="0x1000",
        selector=dict(selectorId=identifier, methodKind="Normal", parameterNames=["value"]), candidate=candidate)
    types = dict(selectorId=identifier, resolutionStatus="resolved_managed_reference_signature",
        instanceType="global::Own.Sample", returnType="bool", parameterTypes=["int"], parameterRefKinds=["Out"])
    return (dict(schema="ehr.harmony-native-target-map.v1", upstream_commit=PIN, selectors=[target]),
        dict(schema="ehr.source-patch-clr-types.v1", upstreamCommit=PIN, compileProfile="IL2CPP", selectors=[types]))


class NativePatchCatalogTests(unittest.TestCase):
    def test_exact_out_parameter_and_source_clr_type_are_preserved(self):
        rows = join(*fixture()); text = emit(rows)
        self.assertEqual(rows[0]["nativeNamespace"], "Own")
        self.assertIn('typeof(global::Own.Sample),[typeof(int)],["value"],[true],[true],typeof(bool)', text)
        self.assertIn('"System.Int32&"', text)
        self.assertNotIn("Configure(", text)

    def test_static_has_no_clr_receiver_and_reserved_route_is_exact(self):
        target, types = fixture(); native = target["selectors"][0]["candidate"]
        native.update(declaring_type="Constants", name="GetBroadcastVersion", static=True,
            parameter_types=[], return_type="System.Int32")
        target["selectors"][0]["selector"]["parameterNames"] = []
        types["selectors"][0].update(parameterTypes=[], parameterRefKinds=[], returnType="int")
        row = join(target, types)[0]
        self.assertEqual(row["targetId"], 1)
        self.assertIsNone(row["instanceType"])

    def test_coroutine_uses_real_move_next_bool_and_native_object_proxy(self):
        target, types = fixture(); row = target["selectors"][0]
        row["selector"].update(methodKind="CoroutineMoveNext", parameterNames=[])
        body = copy.deepcopy(row.pop("candidate")); body.update(declaring_type="Own.Sample+<Factory>d__1",
            name="MoveNext", parameter_types=[], return_type="System.Boolean",
            association="pinned_factory_class_slot_allocation_return_dataflow_and_metadata_definition")
        row["factory_body_association"] = dict(body=body)
        types["selectors"][0].update(returnType="global::Il2CppSystem.Collections.IEnumerator", parameterTypes=[], parameterRefKinds=[])
        result = join(target, types)[0]
        self.assertEqual(result["returnType"], "bool")
        self.assertEqual(result["instanceType"], "global::Il2CppSystem.Object")
        self.assertEqual(result["nativeType"], "Sample+<Factory>d__1")
        body["association"] = "name_match_only"
        with self.assertRaisesRegex(ValueError, "dataflow"): join(target, types)

    def test_mismatched_byref_and_unresolved_source_fail(self):
        target, types = fixture(); types["selectors"][0]["parameterRefKinds"] = ["None"]
        with self.assertRaisesRegex(ValueError, "byref"): join(target, types)
        target, types = fixture(); types["selectors"][0]["resolutionStatus"] = "unresolved"
        with self.assertRaisesRegex(ValueError, "unresolved"): join(target, types)

    def test_duplicate_selector_shared_code_and_source_injection_fail(self):
        target, types = fixture(); target["selectors"].append(copy.deepcopy(target["selectors"][0]))
        with self.assertRaisesRegex(ValueError, "Duplicate"): join(target, types)
        target, types = fixture(); target["selectors"][0]["candidate"]["shared_entry"] = True
        with self.assertRaisesRegex(ValueError, "Shared"): join(target, types)
        target, types = fixture(); types["selectors"][0]["instanceType"] = "object);DoSomething("
        with self.assertRaisesRegex(ValueError, "syntax"): join(target, types)

    def test_route_identity_does_not_depend_on_input_order(self):
        target, types = fixture(); other = copy.deepcopy(target["selectors"][0]); other["selector_id"] = "b" * 20
        other["selector"]["selectorId"] = "b" * 20; other["candidate"]["native_rva"] = other["native_rva"] = "0x2000"
        other_types = copy.deepcopy(types["selectors"][0]); other_types["selectorId"] = "b" * 20
        target["selectors"].append(other); types["selectors"].append(other_types)
        first = join(target, types); target["selectors"].reverse(); types["selectors"].reverse()
        self.assertEqual(first, join(target, types))


if __name__ == "__main__": unittest.main()
