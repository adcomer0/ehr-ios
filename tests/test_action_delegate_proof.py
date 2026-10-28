"""Own source-only tests for finite native delegate proof generation."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

path=Path(__file__).resolve().parents[1]/'tools/generate_action_delegate_proof.py'
spec=importlib.util.spec_from_file_location('action_proof_generator',path)
generator=importlib.util.module_from_spec(spec);spec.loader.exec_module(generator)


class ActionDelegateProofGenerationTests(unittest.TestCase):
    def own_base(self,path):
        path.write_text('namespace {\n}\n\n@interface NativeRuntimeTests : XCTestCase\n@end\nvoid test() {\n    NSDictionary *gateway = exerciseGateway();\n    NSDictionary *proof = @{\n        @"runtimeGateway": gateway,\n    };\n}\n')

    def test_private_overlay_is_reproducible_and_inputs_are_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);source=root/'source';source.mkdir();base=source/'OwnTests.mm';self.own_base(base)
            before=base.read_bytes();first=root/'first';second=root/'second'
            one=generator.generate(source,base,first);two=generator.generate(source,base,second)
            self.assertEqual(one['overlay_sha256'],two['overlay_sha256'])
            self.assertEqual(base.read_bytes(),before)
            overlay=(first/'NativeRuntimeActionDelegate.local.mm').read_text()
            self.assertIn('exerciseNativeActionDelegatePrototype()',overlay)
            self.assertIn('validate_native_method(version,30734292',overlay)
            self.assertIn('@"nativeActionDelegatePrototype": actionDelegate',overlay)
            self.assertFalse(one['runtime_execution_performed'])
            self.assertEqual(hashlib.sha256(overlay.encode()).hexdigest(),one['overlay_sha256'])
            with self.assertRaises(FileExistsError):generator.generate(source,base,first)

    def test_git_source_and_already_extended_base_fail_before_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);source=root/'source';source.mkdir();base=source/'OwnTests.mm';self.own_base(base)
            repo=root/'repository';repo.mkdir();(repo/'.git').write_text('gitdir: own-fixture')
            for output in [source/'output',repo/'output']:
                with self.assertRaises(ValueError):generator.generate(source,base,output)
                self.assertFalse(output.exists())
            base.write_text(base.read_text()+'\nexerciseNativeActionDelegatePrototype\n')
            with self.assertRaises(ValueError):generator.generate(source,base,root/'bad-source')
            self.assertFalse((root/'bad-source').exists())


if __name__=='__main__':unittest.main()
