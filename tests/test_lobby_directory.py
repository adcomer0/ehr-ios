"""Own opt-in directory/HTTP fixture; never opens a network or game runtime."""
import hashlib
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
SPEC = importlib.util.spec_from_file_location("directory_overlay", ROOT / "tools/source_port/prepare_lobby_directory.py")
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)


def fixture():
    values = {
        "compiled/81/LobbySharingAPI.cs": b'// Own header\n// The optional EHR directory is unavailable\npublic static class LobbySharingAPI {}\n[SuppressMessage("Own", "Tail")]\nclass OwnExitCallback {}\n',
        "compiled/102/OptionHolder.cs": b'new EHRProtectedLobbyDirectoryOption(19422,"Own",tab);\n.SetValueFormat(OptionFormat.Seconds)\n            .SetHidden(true);\nOwnOtherOption();\n',
        "compiled/106/OptionItem.cs": b'if (this is EHRProtectedLobbyDirectoryOption) return EHRProtectedLobbyDirectoryOption.Label;\nreturn OwnName;\n',
        "compiled/138/ChatCommandPatch.cs": b'OwnLevelCommandUnchanged();\n    private static void ConfirmAuthCommand(PlayerControl player, string text, string[] args)\n    { OwnUnavailable(); }\n    public static void RetributeCommand() { OwnRoleCallback(); }\n',
        "compiled/780/EHRProtectedLobbyDirectoryOption.cs": b'// Own protected fixture option.\n',
        "compiled/117/RPC.cs": b'// Own RPC canary.\n',
    }
    for name, sites in TOOL.LOG_SITES.items():
        values[name] += b"\n".join(sites) + b"\n"
    return values


class DirectoryTests(unittest.TestCase):
    def test_adapter_preserves_unrelated_callbacks_commands_and_options(self):
        original = fixture()
        result = TOOL.adapt(original)
        self.assertTrue(result["compiled/81/LobbySharingAPI.cs"].startswith(b"// Own header\n"))
        self.assertTrue(result["compiled/81/LobbySharingAPI.cs"].endswith(b'[SuppressMessage("Own", "Tail")]\nclass OwnExitCallback {}\n'))
        chat = result["compiled/138/ChatCommandPatch.cs"]
        self.assertIn(b"OwnLevelCommandUnchanged();", chat)
        self.assertIn(b"OwnRoleCallback();", chat)
        self.assertIn(b"LobbySharingAPI.ConfirmAuth(player, args);", chat)
        self.assertNotIn(b"OwnUnavailable", chat)
        self.assertIn(b"OwnOtherOption();", result["compiled/102/OptionHolder.cs"])
        self.assertNotIn(b".SetHidden(true)", result["compiled/102/OptionHolder.cs"])
        self.assertEqual(result["compiled/780/EHRProtectedLobbyDirectoryOption.cs"], (ROOT / "tools/source_port/lobby_directory/DirectorySupport.cs").read_bytes())
        self.assertEqual(result["compiled/117/RPC.cs"].replace(b"EHRDirectoryLog.ForLog(text)", b"text"), original["compiled/117/RPC.cs"])
        for name, count in (("compiled/117/RPC.cs", 2), ("compiled/138/ChatCommandPatch.cs", 3)):
            self.assertEqual(result[name].count(b"EHRDirectoryLog.ForLog(text)"), count)

    def test_changed_or_duplicated_anchors_rejected(self):
        for name in fixture():
            with self.subTest(name=name):
                values = fixture()
                values[name] *= 2
                if name.endswith("EHRProtectedLobbyDirectoryOption.cs"):
                    continue  # Whole-file source pin is checked by prepare.
                with self.assertRaises(ValueError):
                    TOOL.adapt(values)
        with self.assertRaises(ValueError):
            TOOL.adapt(TOOL.adapt(fixture()))

    def test_fresh_overlay_pins_manifest_and_resources(self):
        values = fixture()
        pins = {name: TOOL.sha(data) for name, data in values.items()}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            for name, data in values.items():
                target = source / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            manifest = {"sources": [{"path": name, "sha256": digest} for name, digest in pins.items()] + [{"path": f"own/{i}.cs", "sha256": "own"} for i in range(796-len(pins))], "resources": [{"upstreamPath": "Resources/OwnCanary", "sha256": "own-resource", "logicalName": "EHR.Resources.Own"}], "ownPolicy": "preserved"}
            (source / "manifest.json").write_text(json.dumps(manifest))
            with patch.object(TOOL, "FILES", pins):
                report = TOOL.prepare(source, root / "output")
                output = json.loads((root / "output/manifest.json").read_text())
                self.assertEqual(output["resources"], manifest["resources"])
                self.assertEqual(output["ownPolicy"], "preserved")
                self.assertEqual(len(output["sources"]), 796)
                self.assertFalse(report["directoryDefaultEnabled"])
                self.assertTrue(report["nativeGateDefaultDeny"])
                self.assertTrue(report["mainThreadRecoveryTickIncluded"])
                self.assertEqual(report["genericCommandLogSitesRedacted"], 5)
                for row in output["sources"][:len(pins)]:
                    self.assertEqual(row["sha256"], TOOL.sha((root / "output" / row["path"]).read_bytes()))
                with self.assertRaises(ValueError):
                    TOOL.prepare(source, root / "output")
                (source / next(iter(values))).write_bytes(b"own changed source")
                with self.assertRaisesRegex(ValueError, "source pin"):
                    TOOL.prepare(source, root / "changed")

    def test_selected_snapshot_preserves_protected_callback_and_resource_spans(self):
        directory = (ROOT / "source-app/compiled/81/LobbySharingAPI.cs").read_bytes()
        chat = (ROOT / "source-app/compiled/138/ChatCommandPatch.cs").read_bytes()
        rpc = (ROOT / "source-app/compiled/117/RPC.cs").read_bytes()
        body = (ROOT / "tools/source_port/lobby_directory/LobbySharingAPI.body.cs").read_bytes()
        self.assertIn(body, directory)
        self.assertEqual((ROOT / "source-app/compiled/780/EHRProtectedLobbyDirectoryOption.cs").read_bytes(), (ROOT / "tools/source_port/lobby_directory/DirectorySupport.cs").read_bytes())
        self.assertEqual(TOOL.sha(rpc.replace(b"EHRDirectoryLog.ForLog(text)", b"text")), TOOL.FILES["compiled/117/RPC.cs"])
        chat = chat.replace(b"EHRDirectoryLog.ForLog(text)", b"text")
        self.assertEqual(TOOL.sha(directory[directory.index(b"[SuppressMessage("):]), "7ff6258b3e293efc68b4aeb73337401f43d0fda9e0796b2784764188f6538115")
        self.assertEqual(TOOL.sha(chat[:chat.index(b"    private static void ConfirmAuthCommand(")]), "30da4a1c1440f1c8894bdd65d7c1e091a4ca66f618ebc6bcdb7c5f682c06df70")
        self.assertEqual(TOOL.sha(chat[chat.index(b"    public static void RetributeCommand("):]), "8854af97d0dc08df0742da5dcccf0a807f9cab26ca203f5ecfb93c161176b5e3")
        manifest = json.loads((ROOT / "source-app/manifest.json").read_text())
        self.assertEqual(hashlib.sha256(json.dumps(manifest["resources"], sort_keys=True).encode()).hexdigest(), "797bef7b8f3c31de1b31824f53f4574fef5c97206b00e13cf319117460531118")

    def test_actual_owned_source_and_bounded_fake_http(self):
        dotnet = os.environ.get("EHR_DOTNET") or shutil.which("dotnet")
        if not dotnet:
            self.skipTest("Set EHR_DOTNET to run the .NET-owned fixture")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            body = root / "Body.cs"
            body.write_text("using System; using System.Collections; using InnerNet;\nnamespace EHR.Modules;\n" + (ROOT / "tools/source_port/lobby_directory/LobbySharingAPI.body.cs").read_text())
            logs = root / "LogSites.cs"
            statements = []
            for name in TOOL.LOG_SITES:
                actual = (ROOT / "source-app" / name).read_text()
                sites = [line.strip() for line in actual.splitlines() if "Logger.Info(" in line and "EHRDirectoryLog.ForLog(text)" in line]
                self.assertEqual(len(sites), len(TOOL.LOG_SITES[name]))
                statements.extend(sites)
            logs.write_text("using EHR;\ninternal static partial class DirectoryLogSites { internal static List<(string Text,string Tag)> Capture(string text) { Logger.Entries.Clear(); var __instance=new OwnPlayer(); var command=new OwnCommand();\n" + "\n".join(statements) + "\nreturn Logger.Entries.ToList(); } }\n")
            chat = (ROOT / "source-app/compiled/138/ChatCommandPatch.cs").read_text()
            recognize = chat[chat.index("    public bool IsThisCommand(string text)"):chat.index("    public bool CanUseCommand(")]
            with logs.open("a") as stream:
                stream.write("internal sealed class OwnRecognizedCommand(string[] forms) { public string[] CommandForms=forms;\n" + recognize + "\n}\n")
            result = subprocess.run([dotnet, "run", "--project", str(ROOT / "tests/lobby_directory_fixture/DirectoryFixture.csproj"), "-c", "Release", "-p:DirectoryBodySource=" + str(body), "-p:DirectorySupportSource=" + str(ROOT / "tools/source_port/lobby_directory/DirectorySupport.cs"), "-p:DirectoryLogSitesSource=" + str(logs), "--artifacts-path", str(root / "artifacts")], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90, env=dict(os.environ, DOTNET_CLI_TELEMETRY_OPTOUT="1"))
            self.assertEqual(result.returncode, 0, result.stdout)
            proofs = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{"schema":"ehr.directory-owned-proof.v1"')]
            self.assertEqual(len(proofs), 1, result.stdout)
            self.assertTrue(proofs[0]["pass"])
            self.assertGreaterEqual(proofs[0]["checks"], 766)
            self.assertEqual(proofs[0]["actualNetworkRequests"], 0)


if __name__ == "__main__":
    unittest.main()
