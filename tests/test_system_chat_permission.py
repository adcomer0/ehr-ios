from pathlib import Path
import importlib.util
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("ehr_chat_mode_check",ROOT/"tools/check_system_chat_permission.py")
M=importlib.util.module_from_spec(spec);spec.loader.exec_module(M)
SOURCE=ROOT/"source-app/compiled/131/Utils.cs"


class SystemChatPermission(unittest.TestCase):
    def test_exact_selected_current_mode_and_early_local_before_all_network(self):
        parts=M.selected(SOURCE.read_text())
        self.assertEqual(len(parts),4)
        self.assertNotIn("EOSManager",parts[0]);self.assertNotIn("IsFreechatAllowed",parts[0])
        self.assertIsNone(re.search(r"ChatMode\s*=(?!=)",parts[0]))
        self.assertIn("catch { return false; }",parts[0])

    def test_fail_open_helper_late_guard_and_denied_writer_mutation_rejected(self):
        original=SOURCE.read_text()
        for mutated in (
            original.replace("catch { return false; }","catch { return true; }",1),
            original.replace("ChatMode == QuickChatModes.FreeChatOrQuickChat","ChatMode != QuickChatModes.QuickChatOnly",1),
            original.replace("if (sendTo == byte.MaxValue) SendLocally(sender);\n                return writer;",
                             "writer.SendMessage();\n                return writer;",1),
        ):
            with self.assertRaises(ValueError):M.selected(mutated)
        helper,local,gate,_=M.selected(original)
        late=original.replace(gate+"\n\n","",1).replace("            int targetClientId =",gate+"\n\n            int targetClientId =",1)
        with self.assertRaises(ValueError):M.selected(late)
        baseline=original.replace(helper+"\n\n","",1).replace(gate+"\n\n","",1)
        M.selected(original,baseline)
        with self.assertRaises(ValueError):M.selected(original,baseline+"\n")

    def test_compiled_actual_guard_with_owned_null_unknown_throwing_and_writer_cases(self):
        sdk=os.environ.get("EHR_DOTNET") or shutil.which("dotnet")
        if not sdk:self.skipTest("Set EHR_DOTNET or install .NET10 on PATH")
        with tempfile.TemporaryDirectory(prefix="ehr-own-chat-mode-") as temporary:
            output=Path(temporary)/"Own"
            result=subprocess.run([sys_executable(),str(ROOT/"tools/check_system_chat_permission.py"),
                "--source",str(SOURCE),"--output",str(output),"--dotnet",sdk],text=True,capture_output=True,timeout=100)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            proof=json.loads((output/"proof.json").read_text())
            self.assertTrue(proof["pass"]);self.assertGreaterEqual(proof["cases"],4000)
            self.assertGreaterEqual(proof["checks"],28000)
            self.assertEqual((proof["gameCalls"],proof["networkOperations"],proof["accountOperations"]),(0,0,0))


def sys_executable():
    import sys
    return sys.executable


if __name__=="__main__":unittest.main()
