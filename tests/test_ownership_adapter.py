import hashlib,importlib.util,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('a',Path(__file__).resolve().parents[1]/'tools/adapt_coroutine_ownership.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
SURFACE='''class MonoBehaviour {
    public Coroutine? @StartCoroutine(IEnumerator? @routine)
    {
        using var result = FacadeRuntime.Invoke(Start, Token, args, 1);
        return result.Token == 0 ? null : new Coroutine(result.Detach());
    }
    public void @StopAllCoroutines()
    {
        using var result = FacadeRuntime.Invoke(StopAll, Token, null, 0);
    }
    public void @StopCoroutine(IEnumerator? @routine)
    {
        using var result = FacadeRuntime.Invoke(StopEnumerator, Token, args, 1);
    }
    public void @StopCoroutine(Coroutine? @routine)
    {
        using var result = FacadeRuntime.Invoke(StopHandle, Token, args, 1);
    }
}
'''.encode()
class OwnershipTests(unittest.TestCase):
    def test_real_invocations_retained_and_cleanup_after_native_success(self):
        output,report=m.surface(SURFACE,m.sha(SURFACE));text=output.decode()
        self.assertEqual(text.count('FacadeRuntime.Invoke('),4)
        self.assertEqual(text.count('ProductionCoroutines.'),4)
        self.assertLess(text.index('FacadeRuntime.Invoke(StopHandle'),text.index('ProductionCoroutines.StoppedHandle'))
        self.assertLess(text.index('FacadeRuntime.Invoke(Start'),text.index('ProductionCoroutines.Started'))
        self.assertLess(text.index('ProductionCoroutines.Started'),text.index('return result.Token'))
        self.assertTrue(report['onlyAfterNativeSuccess'])
    def test_does_not_duplicate_or_accept_changed_hash(self):
        with self.assertRaises(ValueError):m.surface(SURFACE,'0'*64)
        output,_=m.surface(SURFACE,m.sha(SURFACE))
        with self.assertRaises(ValueError):m.surface(output,m.sha(output))
    def test_missing_native_call_or_overload_rejects(self):
        for data in [SURFACE.replace(b'FacadeRuntime.Invoke(StopHandle',b'Fake.Invoke(StopHandle'),SURFACE.replace(b'@StopAllCoroutines()',b'@UnknownStop()')]:
            with self.assertRaises(ValueError):m.surface(data,m.sha(data))
    def test_exact_main_source_identity_without_changing_start(self):
        source=b'coroutines.StartCoroutine(coroutine.WrapToIl2Cpp());\n        coroutines.StopCoroutine(coroutine.WrapToIl2Cpp());\ncoroutines.StopCoroutine(handle);'
        output,proof=m.main_source(source,m.sha(source))
        self.assertIn(b'StartCoroutine(coroutine.WrapToIl2Cpp())',output)
        self.assertIn(b'ProductionCoroutines.StopSource(coroutines, coroutine)',output)
        self.assertIn(b'coroutines.StopCoroutine(handle)',output)
        self.assertTrue(proof['nativeStopBeforeClose'])
if __name__=='__main__':unittest.main()
