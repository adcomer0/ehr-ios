from pathlib import Path
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source-app/compiled/167/JoinGameButtonPatch.cs"
SPEC = importlib.util.spec_from_file_location("join_privacy", ROOT / "tools/source_port/prepare_join_privacy.py")
ADAPTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ADAPTER)


class JoinPrivacyTests(unittest.TestCase):
    def test_selected_source_diff_removes_exact_log_line_only(self):
        selected = SOURCE.read_bytes()
        ending = b"\r\n" if ADAPTER.SET_TEXT + b"\r\n" in selected else b"\n"
        original = selected.replace(ADAPTER.SET_TEXT, ADAPTER.LOG_LINE + ending + ADAPTER.SET_TEXT, 1)
        self.assertEqual(hashlib.sha256(original).hexdigest(), ADAPTER.REVIEWED_INPUT_SHA256)
        output, proof = ADAPTER.transform(original)
        self.assertEqual(output, selected)
        self.assertTrue(proof["clipboardLogRemoved"])
        self.assertTrue(proof["joinValidationUnchanged"])
        self.assertTrue(proof["originalJoinCallbackUnchanged"])
        self.assertFalse(proof["actualClipboardRead"])

    def test_hash_or_changed_ambiguous_log_rejected_without_input_mutation(self):
        selected = SOURCE.read_bytes()
        original = selected.replace(ADAPTER.SET_TEXT, ADAPTER.LOG_LINE + b"\r\n" + ADAPTER.SET_TEXT, 1)
        before = hashlib.sha256(original).hexdigest()
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            ADAPTER.transform(original, "0" * 64)
        for invalid in (selected, original + ADAPTER.LOG_LINE, original + ADAPTER.PREFIX,
                        original.replace(ADAPTER.LOG_LINE, ADAPTER.LOG_LINE.replace(b"Info", b"Warn"))):
            with self.subTest(length=len(invalid)), self.assertRaisesRegex(ValueError, "changed or ambiguous"):
                ADAPTER.transform(invalid, hashlib.sha256(invalid).hexdigest())
        self.assertEqual(hashlib.sha256(original).hexdigest(), before)

    def test_exact_production_prefix_uses_only_valid_trimmed_input_and_never_logs(self):
        dotnet = os.environ.get("EHR_DOTNET") or shutil.which("dotnet")
        if not dotnet:
            self.skipTest("Set EHR_DOTNET to a local .NET 10 SDK")
        before = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory(prefix="ehr-own-join-privacy-") as temporary:
            root = Path(temporary)
            (root / "Selected.cs").write_bytes(SOURCE.read_bytes())
            (root / "Owned.csproj").write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings></PropertyGroup></Project>')
            (root / "NuGet.Config").write_text('<configuration><packageSources><clear/></packageSources></configuration>')
            (root / "Program.cs").write_text(r'''using System.Text.Json;
using EHR;
namespace HarmonyLib { [AttributeUsage(AttributeTargets.Class)] class HarmonyPatch:Attribute { public HarmonyPatch(Type t,string name){} } }
namespace UnityEngine { static class GUIUtility { internal static string OwnedInput=""; internal static int Reads; public static string systemCopyBuffer { get { Reads++;return OwnedInput; } } } }
class TextBox { internal string text=""; internal int Writes; internal void SetText(string value){text=value;Writes++;} }
class JoinGameButton { internal TextBox GameIdText; }
namespace EHR {
 static class Logger { internal static int Calls; internal static void Info(string value,string tag){Calls++;} }
 class EHRStaticPatchFrame { internal JoinGameButton Button; internal T GetInstance<T>() => (T)(object)Button; }
}
static class Program {
 static int Checks;static bool Pass=true;
 static void Check(bool value){Checks++;Pass&=value;}
 static void Run(string input,string previous,bool hasField,bool valid,bool generatedCallback){
  UnityEngine.GUIUtility.OwnedInput=input;UnityEngine.GUIUtility.Reads=0;Logger.Calls=0;
  var field=hasField?new TextBox{text=previous}:null;var button=new JoinGameButton{GameIdText=field};
  if(generatedCallback)JoinGameButtonPatch.__EHRStaticCallback_171(new EHRStaticPatchFrame{Button=button});else JoinGameButtonPatch.Prefix(button);
  bool fill=hasField&&previous.Length==0&&valid;
  Check(field==null||field.Writes==(fill?1:0));Check(field==null||field.text==(fill?input.Trim('\r','\n'):previous));
  Check(Logger.Calls==0);Check(UnityEngine.GUIUtility.OwnedInput==input);
  Check(UnityEngine.GUIUtility.Reads==(!hasField||previous.Length!=0?0:fill?2:1));
 }
 static void Main(){
  foreach(bool generated in new[]{false,true})foreach(bool hasField in new[]{false,true})foreach(string previous in new[]{"","OWNED-EXISTING"}){
   foreach(string valid in new[]{"ABCDEF","ZXCVBN","\r\nABCDEF\r\n","\nABCDEF\r"})Run(valid,previous,hasField,true,generated);
   foreach(string invalid in new[]{"","ABC","ABCDE","ABCDEFG","abcdef","AbCDEF"," ABCDEF","ABCDEF ","AB CDE","ABC1EF","ABCDEF\nX","ABC\nDEF","ＡBCDEF","{owned}","OWNED-SECRET-NOT-A-CODE"})Run(invalid,previous,hasField,false,generated);
  }
  Console.WriteLine(JsonSerializer.Serialize(new{schema="ehr.join-privacy-owned-proof.v1",pass=Pass,checks=Checks,actualClipboardReads=0,actualGameCalls=0,actualAccountActions=0,actualNetworkRequests=0,loggedInputs=Logger.Calls}));
  if(!Pass)Environment.Exit(1);
 }
}''')
            env = dict(os.environ, DOTNET_CLI_TELEMETRY_OPTOUT="1", DOTNET_NOLOGO="1", DOTNET_GENERATE_ASPNET_CERTIFICATE="false")
            result = subprocess.run([dotnet, "run", "--project", str(root / "Owned.csproj"), "-c", "Release"], capture_output=True, text=True, timeout=60, env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            proof = json.loads(next(line for line in result.stdout.splitlines() if line.startswith("{")))
            self.assertTrue(proof["pass"])
            self.assertGreaterEqual(proof["checks"], 700)
            self.assertEqual(proof["loggedInputs"], 0)
            self.assertEqual(proof["actualClipboardReads"], 0)
            self.assertEqual(proof["actualGameCalls"], 0)
        self.assertEqual(hashlib.sha256(SOURCE.read_bytes()).hexdigest(), before)
