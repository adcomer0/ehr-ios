#!/usr/bin/env python3
"""Join exact source CLR types with pinned native method candidates.

Produces source declarations, not installed hooks or a runtime resolver. No game
binary is read, and generated candidates remain unavailable until a native
handler, layout checks and actual runtime method association validate them.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re

PIN = "ce23f0d050f617a59507e5bb0fbfff751d4b5134"


def literal(value):
    return json.dumps(value, ensure_ascii=True)


def clr_type(value):
    if not isinstance(value, str) or not value or len(value) > 2048:
        raise ValueError("Missing bounded source CLR type")
    # Roslyn fully qualified names and primitive keywords only. In particular,
    # no statements, comments, attributes, pointers or open generic parameters.
    if not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9:.<> ,\[\]?]*", value):
        raise ValueError("Unsupported source CLR type syntax")
    if "::" in value and not value.startswith("global::"):
        raise ValueError("Unexpected source CLR alias")
    return value.rstrip("?")


def unique(rows, key):
    result = {}
    for row in rows:
        identifier = row.get(key)
        if not isinstance(identifier, str) or not re.fullmatch(r"[a-f0-9]{20}", identifier) or identifier in result:
            raise ValueError("Duplicate or invalid selector identity")
        result[identifier] = row
    return result


def target_id(identifier, candidate):
    identity = (candidate["declaring_type"], candidate["name"], candidate["static"],
                tuple(candidate["parameter_types"]), candidate["return_type"])
    if identity == ("Constants", "GetBroadcastVersion", True, (), "System.Int32"):
        return 1
    if identity == ("Constants", "IsVersionModded", True, (), "System.Boolean"):
        return 2
    value = int.from_bytes(hashlib.sha256(("ehr.static.patch.v1:" + identifier).encode()).digest()[:8], "little")
    if value <= 2:
        raise ValueError("Reserved original route identity collision")
    return value


def join(targets, source_types):
    if targets.get("schema") != "ehr.harmony-native-target-map.v1" or source_types.get("schema") != "ehr.source-patch-clr-types.v1":
        raise ValueError("Unexpected input schema")
    if targets.get("upstream_commit") != PIN or source_types.get("upstreamCommit") != PIN or source_types.get("compileProfile") != "IL2CPP":
        raise ValueError("Source commit/profile mismatch")
    native = unique(targets["selectors"], "selector_id")
    source = unique(source_types["selectors"], "selectorId")
    if native.keys() != source.keys():
        raise ValueError("Source/native selector sets differ")
    result, ids, rvas = [], set(), set()
    for identifier in sorted(native):
        row, types = native[identifier], source[identifier]
        selector = row["selector"]
        if row.get("status") != "exact_metadata_native_candidate" or selector.get("selectorId") != identifier:
            raise ValueError("Selector has no exact native candidate")
        coroutine = selector["methodKind"] == "CoroutineMoveNext"
        if coroutine:
            association = row.get("factory_body_association", {})
            candidate = association.get("body", {})
            if candidate.get("association") != "pinned_factory_class_slot_allocation_return_dataflow_and_metadata_definition":
                raise ValueError("Coroutine body requires allocation/return dataflow association")
            if candidate.get("name") != "MoveNext" or candidate.get("static") is not False or candidate.get("return_type") != "System.Boolean" or candidate.get("parameter_types") != []:
                raise ValueError("Coroutine body signature mismatch")
            # The source manifest describes the factory, not MoveNext. A boxed
            # native Object proxy retains the actual nested iterator identity.
            instance, returned, parameters, modes = "global::Il2CppSystem.Object", "bool", [], []
        else:
            candidate = row["candidate"]
            if types.get("resolutionStatus") != "resolved_managed_reference_signature":
                raise ValueError("Ordinary source CLR signature unresolved")
            instance = None if candidate["static"] else clr_type(types["instanceType"])
            returned = clr_type(types["returnType"])
            parameters = [clr_type(value) for value in types["parameterTypes"]]
            modes = types["parameterRefKinds"]
        count = len(candidate["parameter_types"])
        names = selector["parameterNames"]
        if count != len(parameters) or count != len(modes) or count != len(names) or count > 128 or len(set(names)) != count:
            raise ValueError("Parameter metadata count/name mismatch")
        if any(mode not in ("None", "Ref", "Out", "In") for mode in modes):
            raise ValueError("Unknown source ref kind")
        if any(native_type.endswith("&") != (mode != "None") for native_type, mode in zip(candidate["parameter_types"], modes)):
            raise ValueError("Native/source byref markers differ")
        if candidate.get("shared_entry") is not False or candidate.get("generic") is not False or candidate.get("abstract") is not False:
            raise ValueError("Shared/generic/abstract entry requires a separate handler")
        rva = int(candidate["native_rva"], 0)
        if rva <= 0 or rva % 4 or row["native_rva"] != candidate["native_rva"] or rva in rvas:
            raise ValueError("Invalid or shared native RVA")
        route = target_id(identifier, candidate)
        if route in ids:
            raise ValueError("Original route identity collision")
        ids.add(route); rvas.add(rva)
        owner = candidate["declaring_type"]
        # Namespace separators precede the outer type. Nested type names retain
        # '+' for the exact class gateway; no compiler-generated CLR type needed.
        outer = owner.split("+", 1)[0]
        namespace, separator, _ = outer.rpartition(".")
        native_name = owner[len(namespace) + 1:] if separator else owner
        result.append(dict(selectorId=identifier, targetId=route, nativeRva=hex(rva),
            nativeImage=candidate["owning_image"], nativeNamespace=namespace,
            nativeType=native_name, nativeMethod=candidate["name"], isStatic=candidate["static"],
            nativeReturn=candidate["return_type"], nativeParameters=candidate["parameter_types"],
            instanceType=instance, returnType=None if returned == "void" else returned,
            parameterTypes=parameters, parameterNames=names, parameterRefKinds=modes,
            coroutineBody=coroutine,
            sourceSpec=dict(typeName=selector.get("declaringType", candidate["declaring_type"]),
                memberName=selector.get("methodName", candidate["name"]),methodKind=selector["methodKind"],
                parameterTypes=selector.get("parameterTypes", candidate["parameter_types"]),
                parameterNames=names,image=selector.get("image", candidate["owning_image"]),
                returnType=selector.get("returnType", "System.Collections.IEnumerator" if coroutine else candidate["return_type"]),
                isStatic=selector.get("isStatic", candidate["static"]),
                resolutionStatus=selector.get("resolutionStatus", "factory_resolved_actual_MoveNext_unbound" if coroutine else types["resolutionStatus"]))))
    return result


def emit(rows):
    lines = ["// <auto-generated />", "#nullable enable", "namespace EHR;",
        "// Candidate declarations only. Does not register or enable a hook.",
        "internal static class NativePatchCatalog", "{"]
    lines += ["    internal static readonly NativePatchCandidate[] Candidates =", "    ["]
    for row in rows:
        source=row["sourceSpec"]
        array=lambda values: "[" + ",".join(literal(v) for v in values) + "]"
        spec="new EHRStaticTargetSpec("+",".join(literal(source[k]) for k in ("typeName","memberName","methodKind"))
        spec+=","+array(source["parameterTypes"])+",true,"+literal(source["image"])+","+literal(source["returnType"])
        spec+=","+("true" if source["isStatic"] else "false")+","+array(source["parameterNames"])+","+literal(source["resolutionStatus"])+")"
        lines += [f"        new({row['targetId']}UL,{literal(row['selectorId'])},{spec}),"]
    lines += ["    ];",
        "    internal static NativePatchDefinition[] CreatePassive()", "    {",
        "        var bindings=new global::System.Collections.Generic.Dictionary<string,EHRStaticPatchBinding>(global::System.StringComparer.Ordinal);",
        "        foreach(var candidate in Candidates) bindings.Add(candidate.Selector,new EHRStaticPatchBinding(candidate.Selector,global::System.Array.Empty<EHRStaticPatchDescriptor>()));",
        "        return Create(bindings);", "    }",
        "    internal static NativePatchDefinition[] Create(global::System.Collections.Generic.IReadOnlyDictionary<string,EHRStaticPatchBinding> bindings)",
        "    {", "        var result=new global::System.Collections.Generic.List<NativePatchDefinition>();"]
    for index, row in enumerate(rows):
        array = lambda values: "[" + ",".join(literal(v) for v in values) + "]"
        booleans = lambda values: "[" + ",".join("true" if v else "false" for v in values) + "]"
        type_array = "[" + ",".join("typeof(" + t + ")" for t in row["parameterTypes"]) + "]"
        instance = "null" if row["instanceType"] is None else "typeof(" + row["instanceType"] + ")"
        returned = "null" if row["returnType"] is None else "typeof(" + row["returnType"] + ")"
        spec = "new global::EHR.Generated.BindingSpec(" + ",".join(literal(row[k]) for k in ("nativeImage", "nativeNamespace", "nativeType", "nativeMethod"))
        spec += "," + ("true" if row["isStatic"] else "false") + ",false," + literal(row["nativeReturn"]) + "," + array(row["nativeParameters"]) + ")"
        lines += [f"        if(bindings.TryGetValue({literal(row['selectorId'])},out var binding{index}))",
            f"            result.Add(new({row['targetId']}UL,{literal(row['selectorId'])},{spec},{instance},{type_array},{array(row['parameterNames'])}," +
            booleans(m != "None" for m in row["parameterRefKinds"]) + "," + booleans(m == "Out" for m in row["parameterRefKinds"]) +
            f",{returned},{row['nativeRva']}UL,binding{index}));"]
    return "\n".join(lines + ["        return result.ToArray();", "    }", "}", ""])


def read_pinned(path, digest):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != digest:
        raise ValueError("Input SHA256 mismatch")
    return json.loads(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-map", type=Path, required=True)
    parser.add_argument("--target-map-sha256", required=True)
    parser.add_argument("--source-types", type=Path, required=True)
    parser.add_argument("--source-types-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Choose a new output directory")
    rows = join(read_pinned(args.target_map, args.target_map_sha256), read_pinned(args.source_types, args.source_types_sha256))
    args.output.mkdir(parents=True)
    (args.output / "NativePatchCatalog.g.cs").write_text(emit(rows))
    report = dict(schema="ehr.native-source-patch-candidates.v1", upstreamCommit=PIN,
        sourceInputSha256=args.source_types_sha256, targetInputSha256=args.target_map_sha256,
        count=len(rows), runtimeValidated=False, hooksInstalled=False, fullEHRAvailable=False,
        requiredRuntimeGates=["exact method/native RVA association", "compiled installed handler identity",
            "exact value layouts and native ABI", "real source startup and callback lifecycle"], candidates=rows)
    (args.output / "native-patch-candidates.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"candidate_count": len(rows), "runtime_validated": False, "hooks_installed": False}))


if __name__ == "__main__":
    main()
