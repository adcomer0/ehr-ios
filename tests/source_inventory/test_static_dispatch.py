import hashlib
import json
import os
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ExactIL2CPPStaticDispatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        location = os.environ.get('EHR_STATIC_SOURCE_BUILD')
        if not location:
            raise unittest.SkipTest('Set EHR_STATIC_SOURCE_BUILD to a fresh build_static_il2cpp output')
        cls.package = Path(location)
        cls.audit = json.loads((cls.package / 'Dispatcher/static_dispatch_audit.json').read_text())
        cls.selectors = json.loads((cls.package / 'Dispatcher/native_target_selectors.json').read_text())['selectors']

    def test_every_actual_callback_has_a_direct_compilable_bridge(self):
        self.assertEqual(self.audit['callbackCount'], 334)
        self.assertEqual(self.audit['callbacksByKind'], {'Prefix': 202, 'Postfix': 131, 'Finalizer': 1})
        self.assertEqual(self.audit['rejectedManagedBridgeForms'], [])
        assembly = self.package / 'Compile/bin/IL2CPP/net6.0/EHR.dll'
        evidence = json.loads((self.package / 'compiled_validation.json').read_text())
        self.assertEqual(evidence['assemblySha256'], hashlib.sha256(assembly.read_bytes()).hexdigest())
        self.assertTrue(evidence['noRoleOrGameAssemblyLoaded'])
        self.assertTrue(all(row['nativeBindingStatus'] == 'native_target_and_ABI_unbound' for row in self.audit['rows']))

    def test_exact_native_type_names_and_signatures_are_semantically_resolved(self):
        self.assertEqual(len(self.selectors), 298)
        resolved = [x for x in self.selectors if x['resolutionStatus'] == 'resolved_managed_reference_signature']
        self.assertEqual(len(resolved), 296)
        for selector in self.selectors:
            self.assertIn(selector['image'], ['Assembly-CSharp', 'Assembly-CSharp-firstpass', 'Unity.TextMeshPro'])
            self.assertIsInstance(selector['isStatic'], bool)
            self.assertTrue(selector['returnType'])
            self.assertEqual(len(selector['parameterTypes']), len(selector['parameterNames']))
            self.assertFalse(any('Il2CppInterop' in value or value.startswith('ystem.') for value in selector['parameterTypes']))
        murders = [x for x in resolved if x['declaringType'] == 'PlayerControl' and x['methodName'] == 'MurderPlayer']
        self.assertEqual(len(murders), 1)
        self.assertEqual(murders[0]['parameterTypes'], ['PlayerControl', 'MurderResultFlags'])
        self.assertEqual(murders[0]['returnType'], 'System.Void')
        self.assertFalse(murders[0]['isStatic'])
        self.assertTrue(any(x['methodKind'] == 'Getter' and x['methodName'].startswith('get_') for x in resolved))

    def test_coroutine_factories_are_never_claimed_as_resolved_move_next(self):
        coroutines = [x for x in self.selectors if x['methodKind'] == 'CoroutineMoveNext']
        self.assertEqual({(x['declaringType'], x['methodName']) for x in coroutines}, {
            ('AirshipExileController', 'WrapUpAndSpawn'), ('IntroCutscene', 'ShowRole')})
        self.assertTrue(all(x['resolutionStatus'] == 'factory_resolved_actual_MoveNext_unbound' for x in coroutines))

    def test_registration_preserves_explicit_classes_and_disables_owner(self):
        edits = self.audit['registrationEdits']
        self.assertEqual(len(edits), 5)
        self.assertEqual(sum('RequestAssembly' in x['replacement'] for x in edits), 1)
        self.assertEqual(sum('RequestClass' in x['replacement'] for x in edits), 2)
        self.assertEqual(sum('DisableOwner' in x['replacement'] for x in edits), 2)
        main = (self.package / 'Dispatcher/source/Main.cs').read_text()
        self.assertIn('if (!OperatingSystem.IsAndroid())', main)
        self.assertNotIn('Harmony.PatchAll(', main)

    def test_harmonyx_prefix_execution_is_explicit(self):
        runtime = (ROOT / 'managed/SourcePort/StaticPatchRuntime.cs').read_text()
        self.assertIn('foreach (EHRStaticPatchDescriptor prefix in Prefixes) if (enabled.Contains(prefix)) prefix.Invoke(frame);', runtime)
        self.assertNotIn('if (frame.RunOriginal || !prefix.AffectsOriginal)', runtime)
        self.assertTrue(any('all-prefix execution' in value for value in self.audit['semanticScope']))


if __name__ == '__main__':
    unittest.main()
