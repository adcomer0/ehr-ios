"""Exercise the exact production writer in an explicit isolated temp cache."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

@unittest.skipUnless(sys.platform=="darwin" and shutil.which("xcrun"),"Requires Apple Foundation/Objective-C++")
class IteratorFailurePersistenceTests(unittest.TestCase):
    def test_failure_only_atomic_persistence_and_path_guards(self):
        with tempfile.TemporaryDirectory(prefix="ehr-owned-failure-writer-") as temporary:
            root=Path(temporary)
            folder=root/"isolated-files";folder.mkdir()
            binary=root/"fixture"
            command=["xcrun","clang++","-std=c++17","-Wall","-Wextra","-Werror","-fobjc-arc","-fobjc-arc-exceptions","-fblocks","-I",str(ROOT/"native"),'-DEHR_DIAGNOSTICS_SOURCE="'+str(ROOT/"native/EHRRuntimeDiagnostics.mm")+'"',str(ROOT/"tests/IteratorFailurePersistenceFixture.mm"),"-framework","Foundation","-o",str(binary)]
            built=subprocess.run(command,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
            self.assertEqual(built.returncode,0,built.stdout)
            ran=subprocess.run([str(binary),str(folder)],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=20)
            self.assertEqual(ran.returncode,0,ran.stdout)
            proof=json.loads(ran.stdout)
            self.assertTrue(proof["pass"]);self.assertGreater(proof["checks"],100)
            self.assertTrue(proof["temporaryCacheOnly"]);self.assertTrue(proof["selectorRestored"])
            self.assertEqual(proof["actualGameCalls"],0);self.assertEqual(proof["actualNetworkRequests"],0)
            if os.environ.get("EHR_ITERATOR_PERSISTENCE_PROOF"):
                output=Path(os.environ["EHR_ITERATOR_PERSISTENCE_PROOF"])
                output.parent.mkdir(parents=True,exist_ok=True)
                output.write_text(json.dumps(proof,indent=2)+"\n")

if __name__=="__main__":unittest.main()
