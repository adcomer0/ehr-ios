"""Exact optional CoStartGame iterator interception; no game bytes are emitted."""
from copy import deepcopy
import hashlib
import uuid
from eos_login_hook_inputs import SOURCE_SHA,METADATA_SHA,UUID
from map_native_methods import MachO
from patch_native_entries import branch,indirect_stub,relocate_first_instruction
OWNER="AmongUsClient+<CoStartGame>d__32"
HOST="AmongUsClient+<CoStartGameHost>d__28"
TARGET=OWNER+".MoveNext"
SYMBOL="_ehr_native_game_start_move_next_hook"
FACTS=((OWNER,"MoveNext","System.Boolean","0x1bd31e0","0x6001ce5"),
       ("AmongUsClient","CoStartGameHost","System.Collections.IEnumerator","0x1bcd480","0x6001c6b"))
INLINE_PROOF={"parentType":OWNER,"hostType":HOST,"allocationTypeCell":"0x5834610","registeredHostTypeIndex":40081,"hostMetadataTypeIndex":1187,
    "parentYieldStates":[5,7],"hostInitialState":0,"parentCurrentStores":["0x1bd394c","0x1bd39d0"],
    "reviewedDataflowSourceHash":SOURCE_SHA,"runtimeExecutionPerformed":False}

def selectors():
    return {"schema":"ehr.native-target-selectors.v1","selectors":[{
        "selectorId":"game-start-iterator-"+str(i),"image":"Assembly-CSharp.dll","declaringType":owner,
        "methodName":name,"methodKind":"Normal","returnType":returns,"parameterTypes":[],"isStatic":False}
        for i,(owner,name,returns,*_) in enumerate(FACTS)]}

def validate_report(base,report):
    for key,value in (("metadata_version",31),("framework_uuid",UUID),("preferred_image_base","0x0")):
        if base.get(key)!=value or report.get(key)!=value:raise ValueError("Game-start iterator image identity differs")
    for key,sha in (("framework",SOURCE_SHA),("metadata",METADATA_SHA)):
        pin=base.get("input_pins",{}).get(key)
        if not pin or pin.get("sha256")!=sha or report.get("input_pins",{}).get(key)!=pin:
            raise ValueError("Game-start iterator input pin differs")
    if report.get("schema")!="ehr.harmony-native-target-map.v1" or len(report.get("selectors",[]))!=2:
        raise ValueError("Game-start iterator requires two exact candidates")
    if report.get("inline_factory_proof")!=INLINE_PROOF:raise ValueError("Reviewed host inlining evidence differs")
    for owner,name,returns,rva,token in FACTS:
        rows=[r for r in report["selectors"] if r.get("candidate",{}).get("declaring_type")==owner and r["candidate"].get("name")==name]
        if len(rows)!=1:raise ValueError("Absent/ambiguous game-start candidate")
        row,c=rows[0],rows[0]["candidate"]
        if (row.get("status")!="exact_metadata_native_candidate" or c.get("owning_image")!="Assembly-CSharp.dll" or
            c.get("return_type")!=returns or c.get("parameter_types")!=[] or c.get("native_rva")!=rva or c.get("metadata_token")!=token or
            any(c.get(k) is not False for k in ("static","generic","abstract","shared_entry")) or
            c.get("registered_module_entry_count")!=1 or c.get("registered_generic_entry_count")!=0):
            raise ValueError("Game-start iterator exact ABI/entry evidence differs")

def merge_game_start_inputs(base,report,contracts):
    validate_report(base,report)
    if contracts.get("schema")!="ehr.native-hook-contracts.v1" or not isinstance(contracts.get("methods"),dict):raise ValueError("Invalid existing hook contracts")
    merged,extra=deepcopy(base),deepcopy(contracts)
    if TARGET in extra["methods"] or any((r.get("declaring_type")==OWNER and r.get("name")=="MoveNext") or
        int(r.get("native_rva") or "0",0)==int(FACTS[0][3],0) for r in merged["methods"]):raise ValueError("Game-start iterator duplicate/alias")
    merged["methods"].append({"declaring_type":OWNER,"name":"MoveNext","return_type":"System.Boolean","parameters":[],"static":False,
        "native_rva":FACTS[0][3],"token":FACTS[0][4],"mapping":"codegen_module_token_rid"})
    extra["methods"][TARGET]={"declaring_type":OWNER,"name":"MoveNext","return":"System.Boolean","parameters":[],"static":False,"symbol":SYMBOL}
    return merged,extra,[TARGET]

def binding_header(manifest,data):
    if manifest.get("framework_uuid")!=UUID or manifest.get("source_sha256")!=SOURCE_SHA or hashlib.sha256(data).hexdigest()!=manifest.get("output_sha256"):
        raise ValueError("Game-start installed provenance differs")
    rows=[r for r in manifest.get("hooks",[]) if r.get("method")==TARGET]
    if len(rows)!=1:raise ValueError("Game-start installed entry absent/ambiguous")
    r=rows[0]
    if (r.get("original_rva")!=FACTS[0][3] or r.get("metadata_token")!=FACTS[0][4] or r.get("symbol")!=SYMBOL or
        r.get("signature")!={"return":"System.Boolean","parameters":[],"static":False}):raise ValueError("Game-start installed contract differs")
    image=MachO(data);method,stub,tramp,got=(int(r[k],0)for k in ("method_rva","stub_rva","trampoline_rva","got_preferred_va"));count=r["relocation"]["trampoline_bytes"];word=int(r["entry_branch"],0)
    if method!=int(FACTS[0][3],0) or image.uuid!=UUID or image.preferred_base or count<8 or count>48 or count%4 or tramp!=stub+16 or word!=branch(method,stub):raise ValueError("Game-start installed geometry differs")
    if image.words(method,1)[0]&0xffffffff!=word:raise ValueError("Game-start installed branch differs")
    stub_data=data[image.va_to_offset(stub,16):image.va_to_offset(stub,16)+16]
    tramp_data=data[image.va_to_offset(tramp,count):image.va_to_offset(tramp,count)+count]
    relocated,details=relocate_first_instruction(int(r["first_instruction"],0),method,tramp)
    if stub_data!=indirect_stub(stub,got) or relocated!=tramp_data or details["trampoline_bytes"]!=count:raise ValueError("Game-start installed code differs")
    def array(value):return "{"+",".join(str(n) for n in value)+"}"
    return ('#pragma once\n#include "EHRNativePatchThunks.h"\n'+
        'static const uint8_t EHRGameStartUUID[16]='+array(uuid.UUID(UUID).bytes)+';\n'+
        'static const EHRNativePatchInstallV1 EHRGameStartInstall={'+','.join(str(v)for v in (method,stub,tramp,got,word,count))+','+array(hashlib.sha256(stub_data).digest())+','+array(hashlib.sha256(tramp_data).digest())+'};\n'+
        'static const EHRNativePatchSiteV1 EHRGameStartSite={0,'+str(method)+','+str(int(FACTS[0][4],0))+',0,EHRGameStartUUID,reinterpret_cast<const void *>(&ehr_native_game_start_move_next_hook),&EHRGameStartInstall,nullptr,nullptr,nullptr,0,false};\n'+
        'static const uint64_t EHRGameStartParentRVA='+FACTS[0][3]+';\nstatic const uint64_t EHRGameStartFactoryRVA='+FACTS[1][3]+';\n')
