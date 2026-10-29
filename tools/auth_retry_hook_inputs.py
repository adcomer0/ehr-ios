"""Separate pre-sign contract for a default-disabled native failure UX guard."""
from copy import deepcopy
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from eos_login_hook_inputs import SOURCE_SHA, METADATA_SHA, UUID

TARGET="EOSManager.LoginWithCorrectPlatform"
SYMBOL="_ehr_native_eos_platform_retry_guard"
FACTS=(("EOSManager","LoginWithCorrectPlatform","0x1b0fd70","0x60000d3"),
       ("AccountManager","PlatformSignInFail","0x1b06374","0x6000025"))

def selectors():
    return {"schema":"ehr.native-target-selectors.v1","selectors":[{
        "selectorId":"auth-retry-guard-"+str(i),"image":"Assembly-CSharp.dll","declaringType":owner,
        "methodName":name,"methodKind":"Normal","returnType":"System.Void","parameterTypes":[],"isStatic":False}
        for i,(owner,name,*_) in enumerate(FACTS)]}

def merge_auth_retry_inputs(base,report,contracts):
    for key,value in (("metadata_version",31),("framework_uuid",UUID),("preferred_image_base","0x0")):
        if base.get(key)!=value or report.get(key)!=value:raise ValueError("Auth retry guard image identity differs")
    for key,sha in (("framework",SOURCE_SHA),("metadata",METADATA_SHA)):
        pin=base.get("input_pins",{}).get(key)
        if not pin or pin.get("sha256")!=sha or report.get("input_pins",{}).get(key)!=pin:
            raise ValueError("Auth retry guard pin differs")
    if report.get("schema")!="ehr.harmony-native-target-map.v1" or len(report.get("selectors",[]))!=2:
        raise ValueError("Auth retry guard requires two exact metadata candidates")
    if contracts.get("schema")!="ehr.native-hook-contracts.v1" or not isinstance(contracts.get("methods"),dict):
        raise ValueError("Invalid existing native contracts")
    for owner,name,rva,token in FACTS:
        matches=[row for row in report["selectors"] if row.get("candidate",{}).get("declaring_type")==owner and row["candidate"].get("name")==name]
        if len(matches)!=1:raise ValueError("Absent/ambiguous auth failure/retry candidate")
        row=matches[0];candidate=row["candidate"]
        if (row.get("status")!="exact_metadata_native_candidate" or candidate.get("owning_image")!="Assembly-CSharp.dll" or
            candidate.get("return_type")!="System.Void" or candidate.get("parameter_types")!=[] or candidate.get("native_rva")!=rva or
            candidate.get("metadata_token")!=token or any(candidate.get(k) is not False for k in ("static","generic","abstract","shared_entry")) or
            candidate.get("registered_module_entry_count")!=1 or candidate.get("registered_generic_entry_count")!=0):
            raise ValueError("Auth failure/retry exact ABI evidence differs")
    result,extra=deepcopy(base),deepcopy(contracts)
    if TARGET in extra["methods"] or any((row.get("declaring_type")=="EOSManager" and row.get("name")=="LoginWithCorrectPlatform") or
            int(row.get("native_rva") or "0",0)==int(FACTS[0][2],0) for row in result["methods"]):
        raise ValueError("Auth retry guard entry duplicate/alias")
    result["methods"].append({"declaring_type":"EOSManager","name":"LoginWithCorrectPlatform","return_type":"System.Void",
        "parameters":[],"static":False,"native_rva":FACTS[0][2],"token":FACTS[0][3],"mapping":"codegen_module_token_rid"})
    extra["methods"][TARGET]={"declaring_type":"EOSManager","name":"LoginWithCorrectPlatform","return":"System.Void",
        "parameters":[],"static":False,"symbol":SYMBOL}
    return result,extra,[TARGET]

def binding_header(manifest):
    if manifest.get("framework_uuid")!=UUID or manifest.get("source_sha256")!=SOURCE_SHA:
        raise ValueError("Auth retry installed provenance differs")
    rows=[row for row in manifest.get("hooks",[]) if row.get("method")==TARGET]
    if len(rows)!=1:raise ValueError("Auth retry installed entry absent/ambiguous")
    row=rows[0]
    if (row.get("original_rva")!=FACTS[0][2] or row.get("metadata_token")!=FACTS[0][3] or row.get("symbol")!=SYMBOL or
        row.get("signature")!={"return":"System.Void","parameters":[],"static":False}):
        raise ValueError("Auth retry installed contract differs")
    rva=int(row["trampoline_rva"],0)
    if rva<=0 or rva%4:raise ValueError("Invalid auth retry trampoline")
    return "#pragma once\n#include <stdint.h>\nstatic const uintptr_t EHRAuthRetryTrampolineRVA="+hex(rva)+";\n"

if __name__=="__main__":
    import argparse
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--selectors-output",type=Path,required=True);args=parser.parse_args()
    with args.selectors_output.open("x") as stream:json.dump(selectors(),stream,indent=2);stream.write("\n")
