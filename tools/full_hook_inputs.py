"""Join pinned full-source targets with independently compiled native contracts.

This selects declarations only. The patcher still validates framework bytes,
metadata signatures, unique entry sites and relocations. Runtime availability
requires the separately checked installed-site evidence.
"""
from copy import deepcopy
import re

PIN="ce23f0d050f617a59507e5bb0fbfff751d4b5134"
LEGACY={
    "PlayerControl.MurderPlayer":("PlayerControl","MurderPlayer","System.Void",("PlayerControl","MurderResultFlags"),False),
    "Constants.GetBroadcastVersion":("Constants","GetBroadcastVersion","System.Int32",(),True),
    "Constants.IsVersionModded":("Constants","IsVersionModded","System.Boolean",(),True),
}

def identity(row):
    return (row["declaring_type"],row["name"],row["return_type"],tuple(row["parameter_types"]),row["static"])

def merge_full_inputs(base,targets,catalog,contracts):
    if targets.get("schema")!="ehr.harmony-native-target-map.v1" or targets.get("upstream_commit")!=PIN:
        raise ValueError("Unsupported pinned full native target map")
    if catalog.get("schema")!="ehr.native-source-patch-candidates.v1" or catalog.get("upstreamCommit")!=PIN:
        raise ValueError("Unsupported pinned source/native catalog")
    if contracts.get("schema")!="ehr.native-hook-contracts.v1" or not isinstance(contracts.get("methods"),dict):
        raise ValueError("Unsupported compiled full native contracts")
    for key in ("metadata_version","framework_uuid","preferred_image_base"):
        if targets.get(key)!=base.get(key):raise ValueError("Full native map input mismatch: "+key)
    for key in ("framework","metadata"):
        if not base.get("input_pins",{}).get(key) or targets.get("input_pins",{}).get(key)!=base["input_pins"][key]:
            raise ValueError("Full native map input mismatch: "+key)
    source={row["selector_id"]:row for row in targets["selectors"]}
    rows=catalog["candidates"]
    if len(source)!=len(targets["selectors"]) or len(rows)>512 or len({r["selectorId"] for r in rows})!=len(rows):
        raise ValueError("Duplicate or oversized full native candidate set")
    if source.keys()!={r["selectorId"] for r in rows}:raise ValueError("Full native selector sets differ")
    expected={"ehr.full."+r["selectorId"] for r in rows}
    if contracts["methods"].keys()!=expected:raise ValueError("Compiled full native contract set differs")
    result=deepcopy(base);selected=[];aliases={};seen_entries=set();seen_routes=set()
    for row in rows:
        identifier=row["selectorId"];entry=source[identifier]
        if not re.fullmatch("[a-f0-9]{20}",identifier) or entry.get("status")!="exact_metadata_native_candidate":
            raise ValueError("Invalid or unresolved full native selector")
        coroutine=row["coroutineBody"]
        candidate=entry.get("factory_body_association",{}).get("body",{}) if coroutine else entry.get("candidate",{})
        if coroutine and candidate.get("association")!="pinned_factory_class_slot_allocation_return_dataflow_and_metadata_definition":
            raise ValueError("Full coroutine body lacks exact factory association")
        if any(candidate.get(key) is not False for key in ("shared_entry","generic","abstract")):
            raise ValueError("Full native entry requires unimplemented combined/generic handler")
        key="ehr.full."+identifier;contract=contracts["methods"][key]
        expected_contract={"declaring_type":candidate["declaring_type"],"name":candidate["name"],
            "return":candidate["return_type"],"parameters":candidate["parameter_types"],
            "static":candidate["static"],"symbol":"_ehr_full_hook_"+identifier}
        if contract!=expected_contract:raise ValueError("Compiled native contract signature differs")
        outer=candidate["declaring_type"].split("+",1)[0];namespace,separator,_=outer.rpartition(".")
        native_type=candidate["declaring_type"][len(namespace)+1:] if separator else candidate["declaring_type"]
        if (row["nativeImage"],row["nativeNamespace"],row["nativeType"],row["nativeMethod"],row["nativeReturn"],row["nativeParameters"],row["isStatic"],row["nativeRva"])!=(candidate["owning_image"],namespace,native_type,candidate["name"],candidate["return_type"],candidate["parameter_types"],candidate["static"],candidate["native_rva"]):
            raise ValueError("Source/native catalog binding differs from pinned candidate")
        rva=int(candidate["native_rva"],0);route=row["targetId"]
        if rva<=0 or rva%4 or rva in seen_entries or route<=0 or route in seen_routes:
            raise ValueError("Duplicate/invalid full native entry or route")
        seen_entries.add(rva);seen_routes.add(route)
        if identity(candidate)==LEGACY["Constants.GetBroadcastVersion"] and route!=1 or identity(candidate)==LEGACY["Constants.IsVersionModded"] and route!=2:
            raise ValueError("Full native catalog contradicts reserved original routes")
        item={"declaring_type":candidate["declaring_type"],"name":candidate["name"],
            "return_type":candidate["return_type"],"parameters":[{"type":t} for t in candidate["parameter_types"]],
            "static":candidate["static"],"native_rva":candidate["native_rva"],"token":candidate["metadata_token"],
            "mapping":"codegen_module_token_rid"}
        same=[m for m in result["methods"] if (m["declaring_type"],m["name"],m["return_type"],tuple(p["type"] for p in m["parameters"]),m["static"])==identity(candidate)]
        if len(same)>1 or same and (same[0]["native_rva"]!=item["native_rva"] or same[0]["token"]!=item["token"]):
            raise ValueError("Existing native map contradicts full candidate")
        if not same:result["methods"].append(item)
        selected.append(key)
        for legacy,signature in LEGACY.items():
            if identity(candidate)==signature:
                if legacy in aliases:raise ValueError("Ambiguous legacy trampoline alias")
                aliases[legacy]=key
    if aliases.keys()!=LEGACY.keys():raise ValueError("Full native catalog lacks required legacy trampoline identities")
    return result,deepcopy(contracts),selected,aliases
