"""Own fake-SDK adapter checks; no game, account, credential or network inputs."""
from pathlib import Path
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "native/EHRItchAuthRuntime.mm"


@unittest.skipUnless(sys.platform == "darwin", "Requires Apple clang/Foundation")
class ItchAuthRuntimeTests(unittest.TestCase):
    def test_actual_adapter_with_owned_sdk_callbacks_and_failure_lifetimes(self):
        with tempfile.TemporaryDirectory(prefix="ehr-owned-itch-runtime-") as temp:
            binary = Path(temp) / "fixture"
            command = ["xcrun", "clang++", "-std=c++17", "-fobjc-arc",
                       "-fobjc-arc-exceptions", "-fblocks", "-Wall", "-Wextra", "-Werror",
                       "-DEHR_ITCH_RUNTIME_SOURCE=" + json.dumps(str(RUNTIME)),
                       "-I", str(ROOT / "native"), "-I", str(ROOT / "native/include"),
                       str(ROOT / "tests/ItchAuthRuntimeFixture.mm"),
                       "-framework", "Foundation", "-o", str(binary)]
            compiled = subprocess.run(command, capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stderr)
            proof = json.loads(run.stdout)
            self.assertEqual(proof["schema"], "ehr.itch-auth-owned-fixture.v1")
            self.assertGreaterEqual(proof["checks"], 520)
            self.assertEqual(proof["failures"], 0)
            self.assertEqual(proof["actualSDKRequests"], 0)
            self.assertEqual(proof["accountOperations"], 0)

    def test_active_binding_shape_strict_ios_arm64_compile(self):
        sdk = subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"],
                             capture_output=True, text=True, timeout=20)
        if sdk.returncode:
            self.skipTest("An iPhoneOS SDK is required for the strict target compile")
        # This is a compilation fixture, not an installed-method proof. The
        # production helper separately validates map/manifest/image provenance.
        sys.path.insert(0, str(ROOT / "tools"))
        try:
            spec = importlib.util.spec_from_file_location("ehr_itch_runtime_compile_inputs",
                                                         ROOT / "tools/itch_auth_hook_inputs.py")
            inputs = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(inputs)
        finally:
            sys.path.pop(0)
        with tempfile.TemporaryDirectory(prefix="ehr-itch-ios-compile-") as temp:
            folder = Path(temp)
            header = "#pragma once\n#include <stdint.h>\n" + "\n".join(
                "static const uintptr_t " + fact[7] + "=" + fact[5] + ";"
                for fact in inputs.METHODS) + "\n"
            (folder / "EHRItchAuthBinding.generated.h").write_text(header)
            command = ["xcrun", "--sdk", "iphoneos", "clang++", "-std=c++17",
                       "-fobjc-arc", "-fobjc-arc-exceptions", "-fblocks", "-Wall", "-Wextra",
                       "-Werror", "-fsyntax-only", "-target", "arm64-apple-ios17.0",
                       "-isysroot", sdk.stdout.strip(), "-I", str(folder),
                       "-I", str(ROOT / "native"), "-I", str(ROOT / "native/include"), str(RUNTIME)]
            compiled = subprocess.run(command, capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)


if __name__ == "__main__":
    unittest.main()
