"""Pinned search-only MCI contracts. No host registration or network API is added."""
from copy import deepcopy
import json
from pathlib import Path
from eos_login_hook_inputs import SOURCE_SHA, METADATA_SHA, UUID

GAME="Assembly-CSharp.dll"
FILTER="AmongUs.Matchmaking.GameFilterSet"
HELPER=("CurrentModRegistration","UpdateFilterSetWithModRegistrationSettings",GAME,"System.Void",(FILTER,),True,"0x1bad1d4","0x6001a54","EHRLobbySearchHelper")
METHODS=(HELPER,
 ("AmongUs.Matchmaking.GameFilterSet",".ctor",GAME,"System.Void",(),False,"0x1e2fd88","0x6004431","EHRLobbySearchSetCtor"),
 ("AmongUs.Matchmaking.ModFilter",".ctor",GAME,"System.Void",(),False,"0x1e30708","0x600444a","EHRLobbySearchModCtor"),
 ("AmongUs.Matchmaking.GameFilter",".ctor",GAME,"System.Void",("System.String","AmongUs.Matchmaking.ISubFilter"),False,"0x1e2fec8","0x6004434","EHRLobbySearchFilterCtor"),
 ("System.Guid","Parse","mscorlib.dll","System.Guid",("System.String",),True,"0x36a394c","0x60007b1","EHRLobbySearchGuidParse"),
 ("HttpMatchmakerManager+<CoRequestGameListFiltered>d__20","MoveNext",GAME,"System.Boolean",(),False,"0x1bfd784","0x6001ee0","EHRLobbySearchRequestMove"))
SYMBOL="_ehr_native_ehr_lobby_search_filters"
TARGET=HELPER[0]+"."+HELPER[1]
CALLSITE=0x1bfdcd4
RETURN=CALLSITE+4
MAX_JSON_BYTES=16*1024*1024


def address(value):
 if not isinstance(value,str):raise ValueError("Lobby search address must be hexadecimal text")
 try:result=int(value,16)
 except ValueError:raise ValueError("Lobby search address must be hexadecimal text") from None
 if result<0 or result>0xffffffffffffffff:raise ValueError("Lobby search address exceeds pointer bound")
 return result


def selectors():
 return {"schema":"ehr.native-target-selectors.v1","selectors":[{"selectorId":"lobby-search-"+str(i+1),"image":f[2],"declaringType":f[0],"methodName":f[1],"methodKind":"Normal","returnType":f[3],"parameterTypes":list(f[4]),"isStatic":f[5]} for i,f in enumerate(METHODS)]}


def candidates(report):
 rows=report.get("selectors")
 if not isinstance(rows,list) or len(rows)!=len(METHODS):raise ValueError("Lobby search selector count differs")
 result=[]
 for expected,fact in zip(selectors()["selectors"],METHODS):
  matches=[r for r in rows if isinstance(r,dict) and r.get("selector_id")==expected["selectorId"]]
  if len(matches)!=1:raise ValueError("Lobby search selector absent or ambiguous")
  row=matches[0];c=row.get("candidate")
  selector=row.get("selector")
  if not isinstance(selector,dict) or type(selector.get("isStatic")) is not bool or selector!=expected or row.get("status")!="exact_metadata_native_candidate" or not isinstance(c,dict):raise ValueError("Lobby search exact candidate missing")
  checks={"declaring_type":fact[0],"name":fact[1],"owning_image":fact[2],"return_type":fact[3],"parameter_types":list(fact[4]),"static":fact[5],"native_rva":fact[6],"metadata_token":fact[7],"association":"offline_codegen_module_token_rid_candidate","runtime_association_verified":False,"generic":False,"abstract":False,"shared_entry":False,"registered_module_entry_count":1,"registered_generic_entry_count":0}
  if any(c.get(k)!=v or type(v) in (bool,int) and type(c.get(k)) is not type(v) for k,v in checks.items()):raise ValueError("Lobby search method identity or unique ABI differs")
  relocation=c.get("first_instruction_relocation")
  if fact==HELPER and (not isinstance(relocation,dict) or relocation.get("status")!="supported_at_report_probe_slot"):raise ValueError("Lobby search helper entry is not relocatable")
  result.append(c)
 return result


def validate_report(base,report):
 if not isinstance(base,dict) or not isinstance(report,dict):raise ValueError("Lobby search report must be an object")
 for key,value in (("metadata_version",31),("framework_uuid",UUID),("preferred_image_base","0x0")):
  if base.get(key)!=value or report.get(key)!=value or type(value) is int and (type(base.get(key)) is not int or type(report.get(key)) is not int):raise ValueError("Lobby search source identity differs: "+key)
 if not isinstance(base.get("input_pins"),dict) or not isinstance(report.get("input_pins"),dict):raise ValueError("Lobby search source pins must be objects")
 for key,value in (("framework",SOURCE_SHA),("metadata",METADATA_SHA)):
  bp=base.get("input_pins",{}).get(key);rp=report.get("input_pins",{}).get(key)
  if not isinstance(bp,dict) or bp!=rp or bp.get("sha256")!=value or type(bp.get("size")) is not int or bp["size"]<=0:raise ValueError("Lobby search input pin differs")
 if not isinstance(report.get("search_callsite"),dict) or type(report["search_callsite"].get("direct_call_verified")) is not bool:raise ValueError("Lobby search callsite proof type differs")
 if report.get("search_callsite")!={"caller":"HttpMatchmakerManager+<CoRequestGameListFiltered>d__20.MoveNext","callsite_rva":hex(CALLSITE),"return_rva":hex(RETURN),"target_rva":HELPER[6],"direct_call_verified":True}:raise ValueError("Lobby search callsite evidence differs")
 return candidates(report)


def merge_lobby_search_inputs(base,report,extra_contracts):
 selected=validate_report(base,report)
 if not isinstance(base.get("methods"),list) or len(base["methods"])>99999 or not isinstance(extra_contracts,dict) or extra_contracts.get("schema")!="ehr.native-hook-contracts.v1" or not isinstance(extra_contracts.get("methods"),dict):raise ValueError("Invalid bounded native hook inputs")
 merged,contracts=deepcopy(base),deepcopy(extra_contracts);rva=int(HELPER[6],16)
 if TARGET in contracts["methods"] or any(not isinstance(r,dict) or r.get("declaring_type")==HELPER[0] and r.get("name")==HELPER[1] or r.get("native_rva") is not None and address(r["native_rva"])==rva for r in merged["methods"]):raise ValueError("Lobby search entry already owned or aliased")
 merged["methods"].append({"declaring_type":HELPER[0],"name":HELPER[1],"return_type":HELPER[3],"parameters":[{"type":p} for p in HELPER[4]],"static":True,"native_rva":HELPER[6],"token":selected[0]["metadata_token"],"mapping":"codegen_module_token_rid"})
 contracts["methods"][TARGET]={"declaring_type":HELPER[0],"name":HELPER[1],"return":HELPER[3],"parameters":list(HELPER[4]),"static":True,"symbol":SYMBOL}
 return merged,contracts,[TARGET]


def binding_header(manifest,report):
 validate_report(report,report)
 if not isinstance(manifest,dict) or manifest.get("framework_uuid")!=UUID or manifest.get("source_sha256")!=SOURCE_SHA:raise ValueError("Lobby search installed provenance differs")
 hooks=manifest.get("hooks")
 if not isinstance(hooks,list) or len(hooks)>100000 or any(not isinstance(h,dict) for h in hooks):raise ValueError("Invalid bounded installed hook manifest")
 rows=[r for r in hooks if r.get("method")==TARGET]
 if len(rows)!=1:raise ValueError("Lobby search installed hook absent or ambiguous")
 row=rows[0]
 if not isinstance(row.get("signature"),dict) or type(row["signature"].get("static")) is not bool:raise ValueError("Lobby search installed static ABI type differs")
 if any(row.get(k)!=v for k,v in {"method_rva":HELPER[6],"original_rva":HELPER[6],"metadata_token":HELPER[7],"symbol":SYMBOL,"signature":{"return":HELPER[3],"parameters":list(HELPER[4]),"static":True}}.items()):raise ValueError("Lobby search installed ABI differs")
 trampoline=address(row.get("trampoline_rva","0"))
 if trampoline<=0 or trampoline%4 or trampoline in {int(f[6],16) for f in METHODS}|{CALLSITE,RETURN}:raise ValueError("Lobby search trampoline aliases reviewed code")
 for other in hooks:
  if other is row:continue
  if other.get("symbol")==SYMBOL or any(other.get(k) is not None and address(other[k]) in (int(HELPER[6],16),trampoline) for k in ("original_rva","method_rva","trampoline_rva","stub_rva","got_rva")):raise ValueError("Lobby search installed entry or trampoline alias")
 lines=["#pragma once","#include <stdint.h>","// Reviewed source identity; loaded signed image is separately validated.",f'static const char EHRLobbySearchSourceSHA256Hex[] = "{SOURCE_SHA}";',f'static const char EHRLobbySearchMetadataSHA256Hex[] = "{METADATA_SHA}";']
 for f in METHODS:lines.extend([f"static const uintptr_t {f[8]}RVA = {f[6]};",f"static const uint32_t {f[8]}Token = {f[7]};"])
 lines.extend([f"static const uintptr_t EHRLobbySearchTrampolineRVA = {hex(trampoline)};",f"static const uintptr_t EHRLobbySearchCallerReturnRVA = {hex(RETURN)};"])
 return "\n".join(lines)+"\n"


def read_json(path):
 if path.stat().st_size>MAX_JSON_BYTES:raise ValueError("Lobby search JSON exceeds bound")
 value=json.loads(path.read_text())
 if not isinstance(value,dict):raise ValueError("Lobby search JSON must be an object")
 return value
