"""Own detached GitInfo fixture and metadata-only release identity gates."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("identity_builder", ROOT / "tools/build_source_application.py")
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)


class ReleaseIdentityTests(unittest.TestCase):
    def identity(self):
        policy = BUILD.release_identity_policy()
        values = {key: policy[key] for key in ("pluginVersion", "forkId", "gitBranch", "gitCommit")}
        values["gitSha"] = policy["upstreamCommit"]
        return {"schema": "ehr.assembly-identity.v1", "assemblyName": "EHR", "assemblyVersion": "8.0.3.0", "assemblySha256": "1" * 64, "assemblyExecuted": False, "constants": values}

    def test_reviewed_policy_and_compiled_constants_match(self):
        policy = BUILD.release_identity_policy()
        self.assertEqual(policy["upstreamCommit"], BUILD.COMMIT)
        self.assertEqual(policy["gitBranch"], "main")
        self.assertEqual(policy["releaseAssetSha256"], "612cf1b4a17a985da49dbb72c0e14c5e98f16c3e5361bbdd850add20737dc103")
        result = BUILD.verify_compiled_identity(self.identity(), policy)
        self.assertTrue(result["passed"])
        self.assertFalse(result["compiled"]["assemblyExecuted"])

    def test_policy_tampering_cannot_add_a_compatibility_tag(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "policy.json"
            policy = BUILD.release_identity_policy()
            policy["gitBranch"] = "OWN-UNVERIFIED"
            path.write_text(json.dumps(policy))
            with patch.object(BUILD, "RELEASE_POLICY", path), self.assertRaisesRegex(ValueError, "policy pin"):
                BUILD.release_identity_policy()

    def test_every_compiled_wire_identity_component_is_required(self):
        for field in ("pluginVersion", "forkId", "gitBranch", "gitCommit", "gitSha"):
            for mode in ("wrong", "missing"):
                with self.subTest(field=field, mode=mode):
                    identity = self.identity()
                    if mode == "wrong":
                        identity["constants"][field] = "OWN-DIFFERENT"
                    else:
                        identity["constants"].pop(field)
                    with self.assertRaisesRegex(ValueError, field):
                        BUILD.verify_compiled_identity(identity, BUILD.release_identity_policy())

    def test_executed_or_unhashed_metadata_proof_is_rejected(self):
        for key, value in (("assemblyExecuted", True), ("assemblySha256", ""), ("schema", "own-unexpected")):
            identity = self.identity()
            identity[key] = value
            with self.assertRaisesRegex(ValueError, "Invalid compiled"):
                BUILD.verify_compiled_identity(identity, BUILD.release_identity_policy())

    def test_unknown_or_dirty_upstream_is_rejected_before_publication(self):
        manifest = {"upstreamCommit": BUILD.COMMIT, "upstreamRoot": "OWN-NOT-ACCESSED"}
        with patch.object(BUILD.subprocess, "check_output", side_effect=["0" * 40, ""]), self.assertRaisesRegex(ValueError, "source pin"):
            BUILD.verify_upstream_release(manifest)
        with patch.object(BUILD.subprocess, "check_output", side_effect=[BUILD.COMMIT, " M Own.cs\n"]), self.assertRaisesRegex(ValueError, "clean upstream"):
            BUILD.verify_upstream_release(manifest)
        with patch.object(BUILD.subprocess, "check_output") as query, self.assertRaisesRegex(ValueError, "exact reviewed"):
            BUILD.verify_upstream_release(dict(manifest, upstreamCommit="0" * 40))
        query.assert_not_called()
        with patch.object(BUILD.subprocess, "check_output", side_effect=[BUILD.COMMIT, ""]):
            self.assertEqual(BUILD.verify_upstream_release(manifest)["gitBranch"], "main")

    def test_real_gitinfo_override_from_own_detached_checkout(self):
        dotnet = os.environ.get("EHR_DOTNET") or shutil.which("dotnet")
        if not dotnet:
            self.skipTest("Set EHR_DOTNET to test real GitInfo code generation")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            code = source / "Own.cs"
            code.write_text('namespace EHR { public static class Main { public const string PluginVersion="8.0.3"; public const string ForkId="EHR"; } }\ninternal static class OwnGeneratedReference { internal const string Value=ThisAssembly.Git.Branch; }\n')
            project = source / "Fixture.csproj"
            project.write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework><AssemblyName>EHR</AssemblyName></PropertyGroup><ItemGroup><PackageReference Include="GitInfo" Version="3.3.4" /></ItemGroup></Project>\n')
            def git(*args):
                return subprocess.check_output(["git", "-C", str(source), *args], text=True, stderr=subprocess.DEVNULL).strip()
            git("init", "--initial-branch=main")
            git("-c", "user.name=Own Fixture", "-c", "user.email=fixture@example.invalid", "add", ".")
            git("-c", "user.name=Own Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "Own detached fixture")
            head = git("rev-parse", "HEAD")
            git("checkout", "--detach", head)
            artifacts = root / "artifacts"
            command = [dotnet, "build", str(project), "-c", "Release", "--artifacts-path", str(artifacts)]
            env = dict(os.environ, DOTNET_CLI_TELEMETRY_OPTOUT="1")
            first = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, timeout=120)
            self.assertEqual(first.returncode, 0, first.stdout)
            assembly = artifacts / "bin/Fixture/release/EHR.dll"
            before = BUILD.read_compiled_identity(Path(dotnet), assembly, root / "reader")
            self.assertEqual(before["constants"]["gitBranch"], "HEAD")
            # Reuse the exact same detached repository and GitInfo cache. Only
            # the supported global MSBuild property changes the generated tag.
            second = subprocess.run(command + ["-p:GitBranch=main"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, timeout=120)
            self.assertEqual(second.returncode, 0, second.stdout)
            after = BUILD.read_compiled_identity(Path(dotnet), assembly, root / "reader")
            self.assertEqual(after["constants"]["gitBranch"], "main")
            self.assertEqual(after["constants"]["gitCommit"], head[:7])
            self.assertEqual(after["constants"]["gitSha"], head)
            self.assertEqual(after["constants"]["pluginVersion"], "8.0.3")
            self.assertEqual(after["constants"]["forkId"], "EHR")
            self.assertNotEqual(before["assemblySha256"], after["assemblySha256"])
            self.assertEqual(git("rev-parse", "--abbrev-ref", "HEAD"), "HEAD")
            self.assertEqual(git("status", "--porcelain"), "")


if __name__ == "__main__":
    unittest.main()
