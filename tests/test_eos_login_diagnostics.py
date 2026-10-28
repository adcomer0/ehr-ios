from copy import deepcopy
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CANONICAL = Path(os.environ.get("EHR_CANONICAL_ROOT", str(ROOT)))
sys.path.insert(0, str(ROOT / "tools"))
from eos_login_hook_inputs import METHODS, GETTER, SOURCE_SHA, METADATA_SHA, UUID, PARAMETER, merge_eos_login_inputs, binding_header


class EOSInputTests(unittest.TestCase):
    def setUp(self):
        self.base={"metadata_version":31,"framework_uuid":UUID,"preferred_image_base":"0x0",
            "input_pins":{"framework":{"sha256":SOURCE_SHA,"size":100},"metadata":{"sha256":METADATA_SHA,"size":10}},
            "methods":[{"declaring_type":"OwnExisting","name":"Callback","native_rva":"0x1000"}]}
        self.report=deepcopy(self.base);self.report.update(schema="ehr.harmony-native-target-map.v1",selectors=[])
        expected=[("EOSManager",name,"Assembly-CSharp.dll","System.Void",[PARAMETER],rva,token) for name,rva,token,*_ in METHODS]+[GETTER]
        for owner,name,image,returns,params,rva,token in expected:
            self.report["selectors"].append({"status":"exact_metadata_native_candidate","candidate":{
                "declaring_type":owner,"name":name,"owning_image":image,"return_type":returns,"parameter_types":params,
                "native_rva":rva,"metadata_token":token,"static":False,"generic":False,"abstract":False,"shared_entry":False,
                "registered_module_entry_count":1,"registered_generic_entry_count":0}})
        self.contracts={"schema":"ehr.native-hook-contracts.v1","methods":{"own-existing":{"static":True}}}
        self.manifest={"framework_uuid":UUID,"source_sha256":SOURCE_SHA,"hooks":[]}
        for i,(name,rva,token,symbol,_) in enumerate(METHODS):
            self.manifest["hooks"].append({"method":"EOSManager."+name,"original_rva":rva,"metadata_token":token,"symbol":symbol,
                "signature":{"return":"System.Void","parameters":[PARAMETER],"static":False},"trampoline_rva":hex(0x2000+i*64)})

    def test_additions_preserve_existing_catalog_and_inputs(self):
        before=deepcopy((self.base,self.report,self.contracts))
        result,contracts,names=merge_eos_login_inputs(self.base,self.report,self.contracts)
        self.assertEqual((self.base,self.report,self.contracts),before)
        self.assertEqual(result["methods"][:-2],self.base["methods"])
        self.assertEqual(contracts["methods"]["own-existing"],self.contracts["methods"]["own-existing"])
        self.assertEqual(len(names),2);self.assertNotIn("targetId",json.dumps(result))

    def test_bad_signature_shared_alias_wrong_pin_and_getter_rejected(self):
        for index,key,bad in ((0,"static",True),(0,"shared_entry",True),(1,"native_rva","0x100"),
            (2,"return_type","System.Int64"),(2,"metadata_token","0x6001234"),(2,"registered_module_entry_count",2)):
            report=deepcopy(self.report);report["selectors"][index]["candidate"][key]=bad
            with self.subTest(index=index,key=key),self.assertRaises(ValueError):merge_eos_login_inputs(self.base,report,self.contracts)
        base=deepcopy(self.base);base["input_pins"]["metadata"]["sha256"]="foreign"
        with self.assertRaises(ValueError):merge_eos_login_inputs(base,self.report,self.contracts)
        base=deepcopy(self.base);base["methods"][0]["native_rva"]=METHODS[0][1]
        with self.assertRaises(ValueError):merge_eos_login_inputs(base,self.report,self.contracts)

    def test_installed_header_requires_exact_entries_and_distinct_trampolines(self):
        header=binding_header(self.manifest);self.assertIn("EHREOSPlatformSilentLoginTrampolineRVA",header)
        for key,bad in (("symbol","_own_wrong"),("metadata_token","0x6000001"),("trampoline_rva","0x2040")):
            manifest=deepcopy(self.manifest);manifest["hooks"][0][key]=bad
            with self.subTest(key=key),self.assertRaises(ValueError):binding_header(manifest)
        manifest=deepcopy(self.manifest);manifest["source_sha256"]="foreign"
        with self.assertRaises(ValueError):binding_header(manifest)

    @unittest.skipUnless(sys.platform=="darwin","Requires Apple clang/Foundation")
    def test_actual_own_forwarding_exceptions_and_unavailable_preflight(self):
        with tempfile.TemporaryDirectory(prefix="ehr-own-eos-observer-") as temp:
            folder=Path(temp);exe=folder/"Fixture"
            (folder/"EHREOSLoginBinding.generated.h").write_text("#pragma once\n#include <stdint.h>\nextern uintptr_t EHREOSPlatformLoginTrampolineRVA;\nextern uintptr_t EHREOSPlatformSilentLoginTrampolineRVA;\n")
            result=subprocess.run(["xcrun","clang++","-std=c++20","-fobjc-arc","-fobjc-arc-exceptions","-fblocks","-framework","Foundation",
                "-I",str(ROOT/"native"),"-I",str(folder),"-I",str(CANONICAL/"native"),str(ROOT/"tests/EOSLoginObserverFixture.mm"),"-o",str(exe)],capture_output=True,text=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stderr)
            proof=json.loads(subprocess.check_output([str(exe)],text=True,timeout=10))
            self.assertTrue(proof["pass"]);self.assertGreaterEqual(proof["checks"],35)
            self.assertEqual((proof["originalNormal"],proof["originalSilent"]),(5,2))
            self.assertEqual(proof["suppressed"],0);self.assertEqual(proof["networkRequests"],0)


if __name__=="__main__":unittest.main()
