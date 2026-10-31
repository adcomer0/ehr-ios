"""Run actual production callbacks with owned host/facade fault sentinels."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class CoroutineFailureTests(unittest.TestCase):
    def test_actual_callback_faults_cleanup_and_stale_validation(self):
        dotnet=os.environ.get("EHR_DOTNET") or shutil.which("dotnet")
        if not dotnet:self.skipTest("Set EHR_DOTNET for the owned callback fixture")
        self.assertEqual((ROOT/"managed/ProductionCoroutines.cs").read_bytes(),(ROOT/"source-app/compiled/778/ProductionCoroutines.cs").read_bytes())
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            project=root/"Fixture.csproj"
            import xml.etree.ElementTree as ET
            p=ET.Element("Project",Sdk="Microsoft.NET.Sdk");g=ET.SubElement(p,"PropertyGroup")
            for k,v in {"OutputType":"Exe","TargetFramework":"net10.0","AllowUnsafeBlocks":"true","Nullable":"enable","EnableDefaultCompileItems":"false"}.items():ET.SubElement(g,k).text=v
            g=ET.SubElement(p,"ItemGroup")
            for source in [ROOT/"managed/ProductionCoroutines.cs",ROOT/"tests/CoroutineFailureFixture.cs"]:ET.SubElement(g,"Compile",Include=str(source))
            ET.ElementTree(p).write(project,encoding="unicode")
            ran=subprocess.run([dotnet,"run","--project",str(project),"-c","Release","--artifacts-path",str(root/"artifacts")],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
            self.assertEqual(ran.returncode,0,ran.stdout)
            proof=json.loads(next(line for line in ran.stdout.splitlines()if line.startswith('{"schema":"ehr.coroutine-failure-owned-proof.v1"')))
            self.assertTrue(proof["pass"]);self.assertGreater(proof["checks"],150);self.assertEqual(proof["tableBytes"],72);self.assertEqual(proof["callbackBytes"],32)
            self.assertEqual(proof["actualGameCalls"],0);self.assertEqual(proof["actualNetworkRequests"],0)
            mapped=subprocess.run([dotnet,"run","--project",str(ROOT/"tools/coroutine_type_map/CoroutineTypeMap.csproj"),"-c","Release","--artifacts-path",str(root/"mapper"),"--",str(root/"artifacts/bin/Fixture/release/Fixture.dll")],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
            self.assertEqual(mapped.returncode,0,mapped.stdout)
            data=json.loads(next(line for line in mapped.stdout.splitlines()if line.startswith('{"schema":"ehr.source-coroutine-type-map.v1"')))
            matches=[entry for entry in data["entries"]if entry["fullName"]==proof["faultSourceType"]]
            self.assertEqual(len(matches),1)
            expected=14695981039346656037
            for byte in proof["faultSourceType"].encode():expected=((expected^byte)*1099511628211)&((1<<64)-1)
            self.assertEqual(int(matches[0]["typeHash"]),expected);self.assertEqual(int(proof["faultSourceTypeHash"]),expected);self.assertFalse(data["assemblyExecuted"]);self.assertFalse(data["methodBodiesRead"])
            if os.environ.get("EHR_COROUTINE_FAILURE_PROOF"):
                output=Path(os.environ["EHR_COROUTINE_FAILURE_PROOF"])
                output.parent.mkdir(parents=True,exist_ok=True)
                output.write_text(json.dumps(proof,indent=2)+"\n")

if __name__=="__main__":unittest.main()
