#!/usr/bin/env python3
"""Generate live ABI-1 facades from compiled IL2CPP refs and native metadata definitions."""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

PRIMITIVES = {"System.Boolean":"bool", "System.Byte":"byte", "System.SByte":"sbyte", "System.Char":"char",
              "System.Int16":"short", "System.UInt16":"ushort", "System.Int32":"int", "System.UInt32":"uint",
              "System.Int64":"long", "System.UInt64":"ulong", "System.Single":"float", "System.Double":"double"}
def canonical(value: str) -> str:
    text=re.sub(r"\[[^\]]+\]", "", value).replace("Il2CppSystem.", "System.")
    if text=="Il2CppInterop.Runtime.InteropTypes.Arrays.Il2CppStringArray":return "System.String[]"
    array=re.fullmatch(r"Il2CppInterop\.Runtime\.InteropTypes\.Arrays\.Il2Cpp(?:StructArray|ReferenceArray|ArrayBase)`1<(.+)>",text)
    return canonical(array.group(1))+"[]" if array else re.sub(r"`[0-9]+(?=<)", "", text)
def ident(value: str) -> str:
    result = value.replace(".", "_").replace("+", "__")
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", result): raise ValueError("unsupported identifier: " + value)
    return result
def quote(value: str) -> str: return json.dumps(value)

def generate(refs: dict, metadata: dict, output: Path, source_surface: bool = False, selectors: dict | None = None, source_profile: dict | None = None, source_components: bool = False) -> dict:
    defs = {canonical(d["name"]):d for d in metadata["typeDefinitions"]}
    enums = {n:d for n,d in defs.items() if canonical(d.get("baseType") or "") == "System.Enum" and "`" not in n}
    values = {n:d for n,d in defs.items() if canonical(d.get("baseType") or "") == "System.ValueType" and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.+]*", n)}
    profile_defs={canonical(d["name"]):d for d in (source_profile or {}).get("typeDefinitions",[])}
    boxed_references={n for n in values if "Il2CppSystem.ValueType" in (profile_defs.get(n,{}).get("baseType") or "")}
    values={n:d for n,d in values.items() if n not in boxed_references}
    value_names: set[str] = set()
    classes = {n:d for n,d in defs.items() if canonical(d.get("baseType") or "") not in ("System.Enum", "System.ValueType") and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.+]*", n)}
    classes.update({n:defs[n] for n in boxed_references})
    class_names: set[str] = set()
    closed_reference_types: dict[str,tuple[str,str]] = {}
    closed_boxed_reference_types: dict[str,tuple[str,str]] = {}
    closed_action_types: dict[str,tuple[str,str]] = {}
    def source_name(name: str) -> str:
        raw=profile_defs.get(name,{}).get("name",name)
        return re.sub(r"\[[^\]]+\]","",raw)
    def csname(name: str) -> str:
        return "global::" + source_name(name).replace("+", ".") if source_surface else ident(name)
    def shape(raw: str, allow_void=False) -> tuple[str,str]:
        name = canonical(raw)
        if "&" in name: raise ValueError("byref/out requires newer tested ABI")
        if "*" in name: raise ValueError("pointer parameter unsupported")
        if name.endswith("[]"):
            element=name[:-2]
            if element.endswith("[]"):raise ValueError("jagged array element codec not generated")
            element_cs,element_kind=shape(element)
            prefix="global::Il2CppInterop.Runtime.InteropTypes.Arrays."
            if element_kind=="string":
                cstype=prefix+"Il2CppStringArray";closed_reference_types[name]=(cstype,"NativeTypeNames.VectorClass(ElementCodecs.Get<string>().NativeClass())");return cstype+"?", "reference"
            array_kind="Il2CppStructArray" if element_kind in ("value","boxed") else "Il2CppReferenceArray"
            cstype=prefix+array_kind+"<"+element_cs.rstrip("?")+">"
            closed_reference_types[name]=(cstype,"NativeTypeNames.VectorClass(ElementCodecs.Get<"+element_cs.rstrip("?")+">().NativeClass())")
            return cstype+"?", "reference"
        def generic_parts(text: str) -> list[str]:
            parts=[];depth=0;start=0
            for i,char in enumerate(text):
                if char=="<":depth+=1
                elif char==">":depth-=1
                elif char=="," and depth==0:parts.append(text[start:i].strip());start=i+1
                if depth<0:raise ValueError("malformed generic argument descriptor")
            if depth!=0:raise ValueError("malformed generic argument descriptor")
            parts.append(text[start:].strip())
            if any(not part for part in parts):raise ValueError("empty generic argument descriptor")
            return parts
        def enum32(name: str) -> bool:
            return name in enums and any(f["name"]=="value__" and canonical(f["type"])=="System.Int32" for f in enums[name]["fields"])
        action_match=re.fullmatch(r"System\.Action<(.+)>",name)
        if action_match:
            arguments=generic_parts(action_match.group(1))
            lowered=[shape(argument) for argument in arguments]
            if len(arguments)==1:
                argument=arguments[0];argument_cs,argument_kind=lowered[0]
                if argument not in ("System.Int32","System.Byte","System.Single") and argument_kind not in ("reference","string"):
                    raise ValueError("typed native Action argument ABI unsupported")
                provider="TypedActionRuntime.NativeClass<"+argument_cs.rstrip("?")+">()"
            elif len(arguments)==3:
                if lowered[0][1] not in ("reference","string") or arguments[1]!="System.Int32" or not enum32(arguments[2]):
                    raise ValueError("native Action3 requires reference/Int32/Int32-enum ABI")
                provider="ComplexDelegateRuntime.TripleClass<"+", ".join(cs.rstrip("?") for cs,_ in lowered)+">()"
            else:raise ValueError("native Action arity unsupported")
            cstype="global::Il2CppSystem.Action<"+", ".join(cs.rstrip("?") for cs,_ in lowered)+">"
            closed_action_types[name]=(cstype,provider)
            return cstype+"?","reference"
        func_match=re.fullmatch(r"System\.Func<(.+)>",name)
        if func_match:
            arguments=generic_parts(func_match.group(1))
            if arguments==["System.Boolean"]:
                cstype="global::Il2CppSystem.Func<bool>";provider="NativeSystemTypes.FuncClass<bool>()"
            elif len(arguments)==2 and arguments[1]=="System.Boolean":
                argument_cs,argument_kind=shape(arguments[0])
                if argument_kind not in ("reference","string"):raise ValueError("native Func2 requires reference/Boolean ABI")
                cstype="global::Il2CppSystem.Func<"+argument_cs.rstrip("?")+", bool>"
                provider="ComplexDelegateRuntime.FunctionClass<"+argument_cs.rstrip("?")+", bool>()"
            else:raise ValueError("native Func argument/result ABI unsupported")
            closed_action_types[name]=(cstype,provider)
            return cstype+"?","reference"
        scene_match=re.fullmatch(r"UnityEngine\.Events\.UnityAction<(.+)>",name)
        if scene_match:
            arguments=generic_parts(scene_match.group(1))
            if len(arguments)!=2 or arguments[0]!="UnityEngine.SceneManagement.Scene" or not enum32(arguments[1]):
                raise ValueError("native UnityAction2 requires Scene/Int32-enum ABI")
            lowered=[shape(argument) for argument in arguments]
            cs_arguments=", ".join(cs.rstrip("?") for cs,_ in lowered)
            cstype="global::EHR.Generated.UnityEngine_Events_UnityAction<"+cs_arguments+">"
            closed_action_types[name]=(cstype,"ComplexDelegateRuntime.SceneClass<"+cs_arguments+">()")
            return cstype+"?","reference"
        queue_match=re.fullmatch(r"System\.Collections\.Generic\.Queue<(.+)>",name)
        if queue_match:
            element,_=shape(queue_match.group(1));cstype="global::Il2CppSystem.Collections.Generic.Queue<"+element.rstrip("?")+">"
            closed_reference_types[name]=(cstype,cstype+".NativeClass")
            return cstype+"?","reference"
        handle_match=re.fullmatch(r"UnityEngine\.ResourceManagement\.AsyncOperations\.AsyncOperationHandle<(.+)>",name)
        if handle_match:
            element,_=shape(handle_match.group(1));cstype="global::UnityEngine.ResourceManagement.AsyncOperations.AsyncOperationHandle<"+element.rstrip("?")+">"
            closed_boxed_reference_types[name]=(cstype,cstype+".NativeClass")
            return cstype+"?","boxedref"
        sequence_match=re.fullmatch(r"SequenceBuffer<(.+)>",name)
        if sequence_match:
            element,_=shape(sequence_match.group(1));cstype="global::SequenceBuffer<"+element.rstrip("?")+">"
            closed_reference_types[name]=(cstype,cstype+".NativeClass")
            return cstype+"?","reference"
        dictionary_match=re.fullmatch(r"System\.Collections\.Generic\.Dictionary<(.+)>",name)
        if dictionary_match:
            parts=[];depth=0;start=0;text=dictionary_match.group(1)
            for i,char in enumerate(text):
                if char=="<":depth+=1
                elif char==">":depth-=1
                elif char=="," and depth==0:parts.append(text[start:i].strip());start=i+1
            parts.append(text[start:].strip())
            if len(parts)!=2:raise ValueError("dictionary descriptor requires two exact types")
            key,_=shape(parts[0]);value,_=shape(parts[1])
            cstype="global::Il2CppSystem.Collections.Generic.Dictionary<"+key.rstrip("?")+", "+value.rstrip("?")+">";closed_reference_types[name]=(cstype,cstype+".NativeClass")
            return cstype+"?", "reference"
        set_match=re.fullmatch(r"System\.Collections\.Generic\.HashSet<(.+)>",name)
        if set_match:
            element_cs,_=shape(set_match.group(1))
            cstype="global::Il2CppSystem.Collections.Generic.HashSet<"+element_cs.rstrip("?")+">";closed_reference_types[name]=(cstype,cstype+".NativeClass")
            return cstype+"?","reference"
        list_match=re.fullmatch(r"System\.Collections\.Generic\.List<(.+)>",name)
        if list_match:
            element_cs,_=shape(list_match.group(1))
            cstype="global::Il2CppSystem.Collections.Generic.List<"+element_cs.rstrip("?")+">";closed_reference_types[name]=(cstype,cstype+".NativeClass")
            return cstype+"?", "reference"
        if "<" in name or "`" in name or "[" in name or "]" in name: raise ValueError("live generic collection adapter required")
        if name == "System.Void" and allow_void: return "void", "void"
        if name == "System.String": return "string?", "string"
        if name == "System.Action":return "global::Il2CppSystem.Action?","reference"
        if name == "System.Text.StringBuilder":return "global::Il2CppSystem.Text.StringBuilder?","reference"
        if name in PRIMITIVES: return PRIMITIVES[name], "value"
        if name in enums: return csname(name), "value"
        if name in values:
            value_names.add(name); return csname(name), "boxed"
        if name in classes:
            class_names.add(name); return csname(name) + "?", "boxedref" if name in boxed_references else "reference"
        if name == "System.Object": return "global::Il2CppSystem.Object?", "reference"
        if name == "System.Collections.IEnumerator":return "global::Il2CppSystem.Collections.IEnumerator?", "reference"
        if name in defs: raise ValueError("value receiver/struct/nested type adapter required")
        raise ValueError("external native type metadata/adapter not provided")
    bindings, unsupported, modeled = [], [], []
    available_assemblies={d.get("image","Assembly-CSharp.dll").removesuffix(".dll") for d in defs.values()}
    source_rows = [r for r in refs["members"] if r["assembly"] in available_assemblies]
    for reference in refs.get("typeReferences",[]):
        name=canonical(reference["name"])
        if reference["assembly"] in available_assemblies:
            if name in classes:class_names.add(name)
            elif name in values:value_names.add(name)
    selector_rows=[];unresolved_selectors=[];selector_type_failures=[]
    for selector in (selectors or {}).get("selectors",[]):
        # A skipped/unsupported method facade must not drop the source frame's
        # independently needed parameter/result codecs. This includes ref/out
        # elements and known factory signatures whose MoveNext is still unbound.
        for name in dict.fromkeys([selector["declaringType"],selector["returnType"],*selector["parameterTypes"]]):
            if not isinstance(name,str):continue
            try:shape(name.removesuffix('&'),allow_void=True)
            except ValueError as error:selector_type_failures.append({"selectorId":selector["selectorId"],"type":name,"reason":str(error)})
        if selector["resolutionStatus"]!="resolved_managed_reference_signature":
            unresolved_selectors.append(selector);continue
        selector_rows.append({"metadataToken":0,"sourceKind":"hook-selector","selectorId":selector["selectorId"],
            "assembly":selector["image"],"declaringType":"["+selector["image"]+"]"+selector["declaringType"],
            "name":selector["methodName"],"kind":"method","returnOrFieldType":selector["returnType"],
            "parameterTypes":selector["parameterTypes"],"isStatic":selector["isStatic"],"genericArity":0,
            "hasByRef":any('&' in p for p in selector["parameterTypes"]),"hasPointer":any('*' in p for p in selector["parameterTypes"])})
    # Harmony nameof targets are strings, not necessarily MemberRefs. Label
    # this explicit read-only probe separately from upstream reference counts.
    probe_rows = [{"metadataToken":0,"assembly":"Assembly-CSharp","declaringType":"[Assembly-CSharp]Constants",
                   "name":"GetBroadcastVersion","kind":"method","returnOrFieldType":"System.Int32",
                   "parameterTypes":[],"isStatic":True,"genericArity":0,"hasByRef":False,"hasPointer":False}]
    if any(r["declaringType"] == "[Assembly-CSharp]Constants" and r["name"] == "GetBroadcastVersion" for r in source_rows): probe_rows=[]
    required_rows=[]
    for row in source_rows + selector_rows:
        parent=canonical(row["declaringType"]); counterpart={"op_Equality":"op_Inequality","op_Inequality":"op_Equality"}.get(row["name"])
        if parent in values and counterpart and not any(canonical(r["declaringType"])==parent and r["name"]==counterpart and r["parameterTypes"]==row["parameterTypes"] for r in source_rows+selector_rows+required_rows):
            candidates=[m for m in defs[parent]["methods"] if m["name"]==counterpart and [canonical(p) for p in m["parameters"]]==[canonical(p) for p in row["parameterTypes"]]]
            if len(candidates)==1:required_rows.append(dict(row,metadataToken=0,sourceKind="required-operator-pair",name=counterpart))
    for row in source_rows + probe_rows + selector_rows + required_rows:
        parent = canonical(row["declaringType"])
        try:
            if parent not in classes and parent not in values: raise ValueError("generic declaring type unsupported")
            (value_names if parent in values else class_names).add(parent)
            definition = defs[parent]
            generic_unity=(row["genericArity"]==1 and
                ((parent=="UnityEngine.Object" and row["name"] in ("Instantiate","FindObjectsOfType","FindObjectOfType") and row["isStatic"]) or
                 (parent=="UnityEngine.ScriptableObject" and row["name"]=="CreateInstance" and row["isStatic"]) or
                 (parent=="InnerNet.MessageExtensions" and row["name"]=="ReadNetObject" and row["isStatic"]) or
                 (parent=="ObjectPoolBehavior" and row["name"]=="Get" and not row["isStatic"]) or
                 (parent=="MatchMaker" and row["name"]=="Connecting" and not row["isStatic"]) or
                 (parent=="PlayerTask" and row["name"]=="PlayerHasTaskOfType" and row["isStatic"]) or
                 (parent in ("UnityEngine.GameObject","UnityEngine.Component") and row["name"] in ("GetComponent","GetComponentInChildren","GetComponentsInChildren","GetComponentInParent","AddComponent") and not row["isStatic"])))
            if row["genericArity"] and not generic_unity: raise ValueError("generic method inflation unsupported")
            if row["returnOrFieldType"].endswith('&'): raise ValueError("byref return unsupported")
            if row["hasPointer"]: raise ValueError("pointer parameter unsupported")
            name = row["name"]
            if name.startswith(".") and name!=".ctor": raise ValueError("native object construction/lifecycle adapter required")
            fields = {f["name"]:f for f in definition["fields"]}
            field_name = name[4:] if name.startswith(("get_", "set_")) else name
            is_get = name.startswith("get_")
            is_set = name.startswith("set_")
            field = fields.get(field_name) if row["kind"] == "field" or is_get or is_set else None
            if field is not None:
                if row.get("sourceKind")=="hook-selector":raise ValueError("native field proxy has no native method-entry target")
                native_type = canonical(field["type"])
                source_type = canonical(row["parameterTypes"][0] if is_set else row["returnOrFieldType"])
                if native_type != source_type: raise ValueError("interop proxy/native field type mismatch")
                cstype, kind = shape(field["type"])
                if is_set and field["isReadOnly"]: raise ValueError("readonly native field has no writable facade")
                op = "write" if is_set else "read"
                spec = {"image":definition.get("image","Assembly-CSharp.dll"), "namespace":parent.split("+")[0].rpartition(".")[0], "type":(parent.split("+")[0].rpartition(".")[2]+("+"+parent.split("+",1)[1] if "+" in parent else "")),
                        "member":field_name,"isStatic":field["isStatic"],"isField":True,"resultType":native_type,"parameters":[]}
                modeled.append({"row":row,"parent":parent,"name":field_name,"operation":op,"spec":spec,"csType":cstype,"shape":kind})
                if row["kind"]=="field" and not field["isReadOnly"]:
                    modeled.append({"row":row,"parent":parent,"name":field_name,"operation":"write","spec":spec,"csType":cstype,"shape":kind})
            else:
                params = [canonical(p) for p in row["parameterTypes"]]
                ret = canonical(row["returnOrFieldType"])
                matches = [m for m in definition["methods"] if m["name"] == name and (m["genericArity"] == 0 or generic_unity) and
                           [canonical(p) for p in m["parameters"]] == params and canonical(m["returnType"]) == ret and m["isStatic"] == row["isStatic"]]
                engine_color=(not matches and parent=="UnityEngine.ColorUtility" and name=="TryParseHtmlString" and params==["System.String","UnityEngine.Color&"] and ret=="System.Boolean" and row["isStatic"])
                if engine_color:
                    helper=[m for m in profile_defs.get(parent,{}).get("methods",[]) if m["name"]==name and [canonical(p) for p in m["parameters"]]==params and canonical(m["returnType"])==ret and m["isStatic"]]
                    if len(helper)!=1:raise ValueError("exact source Color engine helper unavailable")
                    matches=helper
                if len(matches) != 1: raise ValueError("native exact method signature absent or ambiguous")
                if generic_unity:
                    if ret not in ("!!0","!!0[]","System.Boolean") or any("!" in p and p!="!!0" for p in params):raise ValueError("generic Unity signature shape unsupported")
                    if ret=="System.Boolean":cstype,kind="bool","value"
                    else:cstype,kind=("T?","reference") if ret=="!!0" else ("global::Il2CppInterop.Runtime.InteropTypes.Arrays.Il2CppReferenceArray<T>?","reference")
                    param_shapes=[("T?","reference") if p=="!!0" else shape(p) for p in params]
                else:
                    cstype, kind = shape(row["returnOrFieldType"], allow_void=True)
                    param_shapes = [shape(p[:-1] if p.endswith('&') else p) for p in row["parameterTypes"]]
                modes=matches[0].get("parameterModes",["ref" if p.endswith('&') else "value" for p in params])
                if any(p.endswith('&') and s[1] not in ('value','boxed') and mode!='out' for p,s,mode in zip(params,param_shapes,modes)):
                    raise ValueError("ref managed reference exception-side-effect transport unsupported")
                reflected_refs=any(p.endswith('&') and s[1]!='value' for p,s in zip(params,param_shapes))
                source_matches=[m for m in profile_defs.get(parent,{}).get("methods",[]) if m["name"]==name and [canonical(p) for p in m["parameters"]]==params and m["isStatic"]==row["isStatic"]]
                preferred=[m for m in source_matches if all(('Il2CppInterop.Runtime.InteropTypes.Arrays.' in a)==('Il2CppInterop.Runtime.InteropTypes.Arrays.' in b) for a,b in zip(m['parameters'],row['parameterTypes']))]
                source_method=preferred[0] if len(preferred)==1 else source_matches[0] if len(source_matches)==1 else matches[0]
                public_names=source_method.get("parameterNames",["p"+str(i) for i in range(len(params))])
                public_names=[("@"+name) if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*",name) else "p"+str(i) for i,name in enumerate(public_names)]
                defaults=source_method.get("parameterDefaults",[None]*len(params))
                spec = {"image":definition.get("image","Assembly-CSharp.dll"), "namespace":parent.split("+")[0].rpartition(".")[0], "type":(parent.split("+")[0].rpartition(".")[2]+("+"+parent.split("+",1)[1] if "+" in parent else "")),
                        "member":name,"isStatic":row["isStatic"],"isField":False,"resultType":ret,"parameters":params}
                source_params=bool(params and params[-1]=="System.Object[]" and any(m.get("parameterIsParams",[False]*len(params))[-1] for m in source_matches))
                modeled.append({"row":row,"parent":parent,"name":name,"operation":"engineColor" if engine_color else "generic" if generic_unity else "construct" if name==".ctor" else "method","spec":spec,"csType":cstype,"shape":kind,"paramShapes":param_shapes,"paramModes":modes,"publicNames":public_names,"defaults":defaults,"isExtension":source_method.get("isExtension",False),"reflectedRefs":reflected_refs,"sourceParams":source_params})
        except ValueError as error:
            unsupported.append({"metadataToken":row["metadataToken"],"declaringType":parent,"member":row["name"],"reason":str(error),"sourceKind":row.get("sourceKind","direct"),"selectorId":row.get("selectorId")})
    # Stable metadata IDs in source; no native addresses or field offsets.
    unique: dict[str,int] = {}
    for model in modeled:
        if model["operation"] in ("generic","engineColor"):continue # real generic metadata or explicit engine adapter, not invented MethodInfo
        key = json.dumps(model["spec"], sort_keys=True)
        if key not in unique:
            unique[key] = len(bindings); bindings.append(model["spec"])
        model["bindingIndex"] = unique[key]
    pending=list(class_names)
    while pending:
        base=canonical(defs[pending.pop()].get("baseType") or "")
        if re.fullmatch(r"DestroyableSingleton<.+>",base):base="UnityEngine.MonoBehaviour"
        if base in classes and base not in class_names: class_names.add(base);pending.append(base)
    def begin_type(name: str) -> tuple[list[str],str,int]:
        if not source_surface:return [],ident(name),0
        parts=source_name(name).split("+");space,_,outer=parts[0].rpartition(".");opened=[]
        if space:opened.append("namespace "+space+" {")
        for index,part in enumerate(parts[:-1]):
            container=outer if index==0 else part
            container_native=canonical("+".join(parts[:index+1]))
            opened.append("public partial "+("struct " if container_native in values else "class ")+container+" {")
        return opened,parts[-1] if len(parts)>1 else outer,len(opened)
    lines = ["// Generated from IL2CPP-profile used references + native definitions. No native object offsets.","#nullable enable", "using System;", "using EHR.Generated;"]
    lines += ["namespace EHR.Generated {" if source_surface else "namespace EHR.Generated;", "internal static class GeneratedBindings", "{", "    internal static readonly BindingSpec[] All = ["]
    for b in bindings:
        lines.append("        new(" + ", ".join([quote(b["image"]),quote(b["namespace"]),quote(b["type"]),quote(b["member"]),str(b["isStatic"]).lower(),str(b["isField"]).lower(),quote(b["resultType"]),"[" + ", ".join(map(quote,b["parameters"])) + "]"]) + "),")
    lines += ["    ];", "}"]
    lines += ["internal static class GeneratedElementCodecs", "{", "    internal static void RegisterAll()", "    {"]
    for name, definition in sorted(enums.items()):
        value_field=next((f for f in definition["fields"] if f["name"]=="value__"),None)
        if value_field is None or canonical(value_field["type"]) not in PRIMITIVES:continue
        space,_,short=name.split("+")[0].rpartition(".");short+=("+"+name.split("+",1)[1]) if "+" in name else "";cs=csname(name)
        lines.append(f"        ElementCodecs.Register<{cs}>(new PrimitiveCodec<{cs}>({quote(definition.get('image','Assembly-CSharp.dll'))}, {quote(space)}, {quote(short)}));")
    for name in sorted(value_names):
        space,_,short=name.split("+")[0].rpartition(".");short+=("+"+name.split("+",1)[1]) if "+" in name else "";cs=csname(name)
        lines.append(f"        ElementCodecs.Register<{cs}>(new NativeValueCodec<{cs}>({quote(defs[name].get('image','Assembly-CSharp.dll'))}, {quote(space)}, {quote(short)}, static owned => new {cs}(owned))); ")
    for name in sorted(class_names):
        space,_,short=name.split("+")[0].rpartition(".");short+=("+"+name.split("+",1)[1]) if "+" in name else "";cs=csname(name)
        lines.append(f"        ElementCodecs.Register<{cs}>(new ReferenceCodec<{cs}>({quote(defs[name].get('image','Assembly-CSharp.dll'))}, {quote(space)}, {quote(short)}, static token => new {cs}(token)));")
    for name,(cs,provider) in sorted(closed_reference_types.items()):
        lines.append(f"        ElementCodecs.Register<{cs}>(new ClosedReferenceCodec<{cs}>(static()=>{provider},static token=>new {cs}(token,true))); ")
    for name,(cs,provider) in sorted(closed_boxed_reference_types.items()):
        lines.append(f"        ElementCodecs.Register<{cs}>(new ClosedBoxedReferenceCodec<{cs}>(static()=>{provider},static token=>new {cs}(token,true))); ")
    for name,(cs,provider) in sorted(closed_action_types.items()):
        lines.append(f"        ElementCodecs.Register<{cs}>(new ClosedReferenceCodec<{cs}>(static()=>{provider},static token=>new {cs}(token)));")
    lines += ["    }", "}"]
    lines += ["internal static class GeneratedNativeTypes", "{", "    internal static readonly NativeTypeDescriptor[] All = ["]
    for name,definition in sorted(defs.items()):
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.+`]*",name):continue
        space,_,short=name.split("+")[0].rpartition(".");short+=("+"+name.split("+",1)[1]) if "+" in name else ""
        lines.append("        new("+", ".join(map(quote,[name,definition.get("image","Assembly-CSharp.dll"),space,short]))+"),")
    lines += ["    ];", "}"]
    if source_surface: lines += ["}"]
    for name, definition in sorted(enums.items()):
        value_field = next((f for f in definition["fields"] if f["name"] == "value__"),None)
        if value_field is None or canonical(value_field["type"]) not in PRIMITIVES: continue
        opened,declaration,close_count=begin_type(name);lines+=opened
        lines += ["public enum " + declaration + " : " + PRIMITIVES[canonical(value_field["type"])], "{"]
        for field in definition["fields"]:
            if field["constant"] is not None and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*",field["name"]):
                lines.append("    @" + field["name"] + " = " + str(field["constant"]) + ",")
        lines += ["}"]
        lines += ["}"]*close_count
    def invoke_lines(model: dict, args_name="null", count=0, ref_indices=(),override_call=None) -> list[str]:
        index=model["bindingIndex"]; instance="0" if model["spec"]["isStatic"] else "Token"
        call = f"FacadeRuntime.ReadField(GeneratedBindings.All[{index}], {instance})" if model["operation"]=="read" else f"FacadeRuntime.Invoke(GeneratedBindings.All[{index}], {instance}, {args_name}, {count})"
        if ref_indices:call=f"LiveCollections.InvokeWithRefs(GeneratedBindings.All[{index}], {instance}, {args_name}, {count}, outputs, {len(ref_indices)})"
        if override_call:call=override_call
        result=["using var result = " + call + ";"]
        result += [f"{model.get('publicNames',['p'+str(j) for j in range(len(model['paramShapes']))])[i]} = local{i};" for i in ref_indices]
        if model["shape"]=="boxed": result += [f"return new {model['csType']}(new RuntimeObject(result.Detach()));"]
        elif model["shape"]=="value": result += [f"return FacadeRuntime.ReadValue<{model['csType']}>(result);"]
        elif model["shape"]=="string": result += ["return FacadeRuntime.ReadString(result);"]
        elif model["shape"] in ("reference","boxedref"):
            target=model["csType"].rstrip("?")
            extra=", true" if target.startswith(("global::Il2CppSystem.Collections.Generic.List<","global::Il2CppSystem.Collections.Generic.HashSet<","global::Il2CppSystem.Collections.Generic.Dictionary<","global::Il2CppSystem.Collections.Generic.Queue<","global::Il2CppInterop.Runtime.InteropTypes.Arrays.","global::SequenceBuffer<","global::UnityEngine.ResourceManagement.AsyncOperations.AsyncOperationHandle<")) else ""
            result += [f"return result.Token == 0 ? null : new {target}(result.Detach(){extra});"]
        return result
    def parameters_text(model: dict,with_defaults=True) -> str:
        result=[]
        for i,(cstype,kind) in enumerate(model["paramShapes"]):
            text=(model["paramModes"][i]+" " if model["spec"]["parameters"][i].endswith("&") else "")+cstype+" "+model.get("publicNames",["p"+str(j) for j in range(len(model["paramShapes"]))])[i]
            default=model.get("defaults",[None]*len(model["paramShapes"]))[i]
            if with_defaults and default is not None:
                value=default["value"]
                if value is None:literal="null"
                elif isinstance(value,bool):literal=str(value).lower()
                elif isinstance(value,str):literal=quote(value)
                elif cstype=="char":literal="(char)"+str(value)
                else:
                    literal=str(value)+( "f" if cstype=="float" else "" )
                    if kind=="value" and canonical(model["spec"]["parameters"][i]) in enums:literal="("+cstype+")"+literal
                text+=" = "+literal
            result.append(text)
        return ", ".join(result)
    def argument_lines(types: list[str], shapes: list[tuple[str,str]], names: list[str]) -> list[str]:
        result=[]
        if not names:return result
        result += [f"NativeArgument* arguments = stackalloc NativeArgument[{len(names)}];"]
        for i,(native,cs,name) in enumerate(zip(types,shapes,names)):
            if cs[1]=="value": result += [f"arguments[{i}] = FacadeRuntime.Value(&{name}, {quote(native)});"]
            elif cs[1]=="boxedref": result += [f"using var boxed{i} = {name} is null ? throw new ArgumentNullException(nameof({name})) : FacadeRuntime.Retain({name});",f"arguments[{i}] = NativeValues.Argument(boxed{i});"]
            elif cs[1]=="boxed": result += [f"using var boxed{i} = NativeValues.Box({name});",f"arguments[{i}] = NativeValues.Argument(boxed{i});"]
            elif cs[1]=="string": result += [f"using var string{i} = FacadeRuntime.String({name});",f"arguments[{i}] = FacadeRuntime.Reference(string{i});"]
            else:result += [f"arguments[{i}] = FacadeRuntime.Reference({name});"]
        return result
    def inherited_name(parent: str, name: str, parameter_shapes=None) -> bool:
        base=canonical(defs[parent].get("baseType") or "")
        while base in classes:
            if any(m["parent"]==base and (m["name"][4:] if m["name"].startswith(("get_","set_")) else m["name"])==name and
                   (parameter_shapes is None or m.get("paramShapes")==parameter_shapes) for m in modeled):return True
            base=canonical(defs[base].get("baseType") or "")
        return name in ("GetHashCode","ToString","GetType","Dispose") and not parameter_shapes
    for parent in sorted(class_names | value_names):
        is_value=parent in values
        opened,cls,close_count=begin_type(parent)
        base=canonical(defs[parent].get("baseType") or "")
        singleton=re.fullmatch(r"DestroyableSingleton<(.+)>",base)
        base_cs=("global::" if source_surface else "")+"DestroyableSingleton<"+csname(singleton.group(1))+">" if singleton else (csname(base) if base in class_names else "global::Il2CppSystem.Object")
        lines+=opened
        if is_value:
            image=quote(defs[parent].get("image","Assembly-CSharp.dll")); space=quote(parent.split("+")[0].rpartition(".")[0]); short=quote((parent.split("+")[0].rpartition(".")[2]+("+"+parent.split("+",1)[1] if "+" in parent else "")))
            lines += [f"public unsafe partial struct {cls} : INativeValue", "{", "    private RuntimeObject? storage;",f"    internal {cls}(RuntimeObject owned) {{ storage=owned; }}",f"    public RuntimeObject NativeBox => storage ??= NativeValues.Default({image},{space},{short});", "    private ulong Token => NativeBox.Token;", "    private void EnsureWritable() { storage=NativeValues.Clone(NativeBox); }"]
        else:
            lines += [f"public unsafe partial class {cls} : {base_cs}", "{",f"    internal {cls}(ulong ownedToken) : base(ownedToken) {{ }}"]
            if parent in boxed_references and not any(m["parent"]==parent and m["operation"]=="construct" and not m["paramShapes"] for m in modeled):
                image=quote(defs[parent].get("image","Assembly-CSharp.dll"));space=quote(parent.split("+")[0].rpartition(".")[0]);short=quote(parent.split("+")[0].rpartition(".")[2]+("+"+parent.split("+",1)[1] if "+" in parent else ""))
                lines += [f"    public {cls}() : base(NativeValues.Default({image},{space},{short}).Detach()) {{ }}"]
        parent_models=[m for m in modeled if m["parent"]==parent]
        # Constants were inlined into the compiled source, so they have no
        # MemberRef/native field lookup. Preserve pinned source constants as
        # constants, never as invented runtime fields.
        constant_fields={f['name']:f for f in profile_defs.get(parent,{}).get('fields',[]) if f.get('constant') is not None and f.get('isStatic') and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',f['name'])}
        for name,f in sorted(constant_fields.items()):
            native=canonical(f['type']);value=f['constant']
            if native not in PRIMITIVES and native!='System.String':continue
            if any(m['name']==name for m in parent_models):continue
            cstype=PRIMITIVES.get(native,'string')
            if value in ('Infinity','-Infinity','NaN') and cstype in ('float','double'):literal=cstype+'.'+{'Infinity':'PositiveInfinity','-Infinity':'NegativeInfinity','NaN':'NaN'}[value]
            elif cstype=='string':literal=quote(value)
            elif cstype=='char':literal='(char)'+str(ord(value) if isinstance(value,str) else value)
            elif isinstance(value,bool):literal=str(value).lower()
            else:literal=str(value)+('f' if cstype=='float' else '')
            lines += [f"    public const {cstype} @{name} = {literal};"]
        fields:dict[str,list[dict]]={}
        methods=[]
        for m in parent_models:
            if m["spec"]["isField"]:fields.setdefault(m["name"],[]).append(m)
            else:methods.append(m)
        for name,accessors in sorted(fields.items()):
            first=accessors[0]; static="static " if first["spec"]["isStatic"] else ""
            hidden="new " if inherited_name(parent,name) else ""
            lines += [f"    public {hidden}{static}{first['csType']} @{name}", "    {"]
            getter=next((m for m in accessors if m["operation"]=="read"),None)
            setter=next((m for m in accessors if m["operation"]=="write"),None)
            if getter:lines += ["        get", "        {"]+["            "+s for s in invoke_lines(getter)]+["        }"]
            if setter:
                lines += ["        set", "        {"]+(["            EnsureWritable();"] if is_value and not setter["spec"]["isStatic"] else [])+[f"            {setter['csType']} argumentValue = value;"]
                arg=argument_lines([setter["spec"]["resultType"]],[(setter["csType"],setter["shape"])],["argumentValue"])
                instance="0" if setter["spec"]["isStatic"] else "Token"
                lines += ["            "+s for s in arg]+[f"            FacadeRuntime.WriteField(GeneratedBindings.All[{setter['bindingIndex']}], {instance}, arguments[0]);","        }"]
            lines += ["    }"]
        properties={}
        for m in methods:
            if m["name"].startswith("get_") and not m["paramShapes"] and m["shape"]!="void":properties.setdefault(m["name"][4:],{})["get"]=m
            elif m["name"].startswith("set_") and len(m["paramShapes"])==1 and m["shape"]=="void" and not m["spec"]["parameters"][0].endswith('&'):properties.setdefault(m["name"][4:],{})["set"]=m
        emitted=set()
        for name,accessors in sorted(properties.items()):
            getter=accessors.get("get");setter=accessors.get("set")
            cstype=getter["csType"] if getter else setter["paramShapes"][0][0]
            if getter and setter and (getter["csType"]!=setter["paramShapes"][0][0] or getter["spec"]["isStatic"]!=setter["spec"]["isStatic"]):continue
            first=getter or setter;static="static " if first["spec"]["isStatic"] else ""
            hidden="new " if inherited_name(parent,name) else ""
            lines += [f"    public {hidden}{static}{cstype} @{name}","    {"]
            if getter:
                lines += ["        get","        {"]+(["            EnsureWritable();"] if is_value and not getter["spec"]["isStatic"] else [])+["            "+s for s in invoke_lines(getter)]+["        }"]
                emitted.update(id(m) for m in methods if m["name"]==getter["name"] and m["spec"]==getter["spec"])
            if setter:
                body=(["EnsureWritable();"] if is_value and not setter["spec"]["isStatic"] else [])+[f"{cstype} argumentValue=value;"]+argument_lines(setter["spec"]["parameters"],setter["paramShapes"],["argumentValue"])+invoke_lines(setter,"arguments",1)
                lines += ["        set","        {"]+["            "+s for s in body]+["        }"]
                emitted.update(id(m) for m in methods if m["name"]==setter["name"] and m["spec"]==setter["spec"])
            lines += ["    }"]
        seen={};seen_constructors=set()
        for m in methods:
            if id(m) in emitted:continue
            if is_value and m["name"]=="GetHashCode" and not m["paramShapes"]:continue
            if is_value and m["name"]=="Equals" and m["spec"]["parameters"]==["System.Object"]:continue
            if m["operation"]=="engineColor":
                value=csname("UnityEngine.Color")
                lines += [f"    public static bool @TryParseHtmlString({parameters_text(m)})", "    {",f"        bool parsed=NativeEngineColors.Parse({m['publicNames'][0]},out uint rgba);",f"        {m['publicNames'][1]}=new {value}(((rgba>>24)&255)/255f,((rgba>>16)&255)/255f,((rgba>>8)&255)/255f,(rgba&255)/255f);","        return parsed;", "    }"]
                continue
            if m["operation"]=="generic":
                signature=(m["name"],tuple(s[0] for s in m["paramShapes"]))
                if signature in seen:continue
                seen[signature]=m["spec"]
                static="static " if m["spec"]["isStatic"] else ""
                image=quote(defs[parent].get("image","Assembly-CSharp.dll"));space=quote(parent.rpartition(".")[0]);short=quote(parent.rpartition(".")[2])
                patterns=", ".join(quote(p) for p in m["spec"]["parameters"])
                body=[f"ulong method=NativeGenericMethods.Lookup(FacadeRuntime.Class({image},{space},{short}),{quote(m['name'])},{quote(m['spec']['resultType'])},[{patterns}],[ElementCodecs.Get<T>().NativeClass()],{str(m['spec']['isStatic']).lower()});"]
                if source_components and not m['paramShapes'] and (parent,m['name']) in (("UnityEngine.GameObject","AddComponent"),("UnityEngine.GameObject","GetComponent"),("UnityEngine.Component","GetComponent")):
                    source_call="(T?)SourceComponentRuntime.Add(typeof(T),this)" if m['name']=="AddComponent" else "SourceComponentFacades.Get<T>(this,"+("true" if parent=="UnityEngine.GameObject" else "false")+")"
                    body.insert(0,"if(SourceComponentRuntime.IsSource(typeof(T)))return "+source_call+";")
                body+=argument_lines(m["spec"]["parameters"],m["paramShapes"],m["publicNames"])
                instance="0" if m["spec"]["isStatic"] else "Token"
                body += [f"using var result=FacadeRuntime.InvokeResolved(method,{instance},{'arguments' if m['paramShapes'] else 'null'},{len(m['paramShapes'])});"]
                if m["spec"]["resultType"]=="!!0[]":body += ["return result.Token==0?null:new global::Il2CppInterop.Runtime.InteropTypes.Arrays.Il2CppReferenceArray<T>(result.Detach(),true);"]
                elif m["spec"]["resultType"]=="System.Boolean":body += ["return FacadeRuntime.ReadValue<bool>(result);"]
                else:body += ["return (T?)ElementCodecs.Get<T>().Read(result);"]
                lines += [f"    public {static}{m['csType']} @{m['name']}<T>({parameters_text(m)}) where T:RuntimeObject", "    {"]+["        "+s for s in body]+["    }"]
                continue
            if m["operation"]=="construct":
                signature=tuple(p[0] for p in m["paramShapes"])
                if signature in seen_constructors:continue
                seen_constructors.add(signature)
                if source_components and parent=="UnityEngine.MonoBehaviour" and not m["paramShapes"]:
                    lines += [f"    public {cls}() : base(SourceComponentConstruction.Take()) {{ SourceComponentConstruction.Bind(this); }}"]
                    continue
                if is_value:lines += [f"    public {cls}({parameters_text(m)})", "    {"]
                else:
                    helper="CreateNative"+str(m["bindingIndex"])
                    invocation=", ".join(m["publicNames"])
                    lines += [f"    public {cls}({parameters_text(m)}) : base({helper}({invocation})) {{ }}",f"    private static ulong {helper}({parameters_text(m,False)})", "    {"]
                for i,p in enumerate(m["paramShapes"]):
                    if p[1]=="boxedref":lines.append(f"        ArgumentNullException.ThrowIfNull({m['publicNames'][i]});")
                    lines.append(f"        using var ctorArg{i}=ElementCodecs.Get<{p[0].rstrip('?')}>().Box({m['publicNames'][i]});")
                constructor_args=", ".join(f"ctorArg{i}" for i in range(len(m["paramShapes"])))
                parameter_classes=", ".join(f"ElementCodecs.Get<{p[0].rstrip('?')}>().NativeClass()" for p in m["paramShapes"])
                image=quote(defs[parent].get("image","Assembly-CSharp.dll"));space=quote(parent.split("+")[0].rpartition(".")[0]);short=quote(parent.split("+")[0].rpartition(".")[2]+("+"+parent.split("+",1)[1] if "+" in parent else ""))
                call=f"NativeConstructors.Create(FacadeRuntime.Class({image},{space},{short}),[{parameter_classes}],[{constructor_args}])"
                lines += [f"        storage=new RuntimeObject({call});" if is_value else f"        return {call};", "    }"]
                continue
            signature=(m["name"],tuple(s[0] for s in m["paramShapes"]))
            if signature in seen:
                if seen[signature] == m["spec"]:continue # duplicate proxy aliases to the same exact native signature
                raise ValueError("C# overload collapse: " + parent + "." + m["name"])
            seen[signature]=m["spec"]
            parameters=parameters_text(m)
            static="static " if m["spec"]["isStatic"] else ""
            if parent=="UnityEngine.Object" and m["name"]=="op_Implicit":declaration=f"public static implicit operator bool({parameters})"
            elif parent=="UnityEngine.Object" and m["name"] in ("op_Equality","op_Inequality"):declaration=f"public static bool operator {'==' if m['name']=='op_Equality' else '!='}({parameters})"
            elif is_value and m["name"].startswith("op_"):
                operators={"op_Addition":"+","op_Subtraction":"-","op_Multiply":"*","op_Division":"/","op_Equality":"==","op_Inequality":"!=","op_UnaryNegation":"-"}
                if m["name"] in ("op_Implicit","op_Explicit"):declaration=f"public static {'implicit' if m['name']=='op_Implicit' else 'explicit'} operator {m['csType']}({parameters})"
                elif m["name"] in operators:declaration=f"public static {m['csType']} operator {operators[m['name']]}({parameters})"
                else:raise ValueError("Unsupported value operator: "+m["name"])
            elif is_value and m["name"]=="ToString" and not m["paramShapes"]:declaration="public override string? ToString()"
            else:declaration=f"public {'new ' if not is_value and inherited_name(parent,m['name'],m['paramShapes']) else ''}{static}{m['csType']} @{m['name']}({parameters})"
            lines += ["    "+declaration, "    {"]
            ref_indices=[i for i,p in enumerate(m["spec"]["parameters"]) if p.endswith('&')]
            if m.get("reflectedRefs"):
                body=(["EnsureWritable();"] if is_value and not m["spec"]["isStatic"] else [])
                for i,(cstype,kind) in enumerate(m["paramShapes"]):
                    codec="ElementCodecs.Get<"+cstype.rstrip("?")+">()"
                    if i in ref_indices and m["paramModes"][i]=="out" and kind in ("reference","string"):
                        body += [f"using var reflectedArg{i}=new RuntimeObject(0);"]
                    elif i in ref_indices and m["paramModes"][i]=="out":body += [f"using var reflectedArg{i}=LiveReflection.Construct({codec}.NativeClass(),[]);"]
                    elif i in ref_indices and kind=="boxed":body += [f"using var inputArg{i}={codec}.Box({m['publicNames'][i]});",f"using var reflectedArg{i}=NativeValues.Clone(inputArg{i});"]
                    else:body += [f"using var reflectedArg{i}={codec}.Box({m['publicNames'][i]});"]
                instance="0" if m["spec"]["isStatic"] else "Token"
                args=", ".join("reflectedArg"+str(i) for i in range(len(m["paramShapes"])))
                body += [f"using var invocation=NativeReflectedCall.Invoke(GeneratedBindings.All[{m['bindingIndex']}],{instance},[{args}]);"]
                for i in ref_indices:body += [f"{m['publicNames'][i]}=({m['paramShapes'][i][0]})ElementCodecs.Get<{m['paramShapes'][i][0].rstrip('?')}>().Read(invocation.Argument({i}))!;"]
                body+=invoke_lines(m,override_call="invocation.TakeResult()")
                lines += ["        "+s for s in body]+["    }"]
                continue
            names=["local"+str(i) if i in ref_indices else m["publicNames"][i] for i in range(len(m["paramShapes"]))]
            body=(["EnsureWritable();"] if is_value and not m["spec"]["isStatic"] else [])+[f"{m['paramShapes'][i][0]} local{i} = "+("default;" if m["paramModes"][i]=="out" else f"{m['publicNames'][i]};") for i in ref_indices]
            body+=argument_lines([p.rstrip('&') for p in m["spec"]["parameters"]],m["paramShapes"],names)
            if ref_indices:
                body += [f"ByRefOutput* outputs = stackalloc ByRefOutput[{len(ref_indices)}];"]
                body += [f"outputs[{j}] = new ByRefOutput {{ ArgumentIndex = {i}, ValueClass = arguments[{i}].Token, Bytes = &local{i}, ByteCount = (nuint)sizeof({m['paramShapes'][i][0]}) }};" for j,i in enumerate(ref_indices)]
            body += invoke_lines(m,"arguments" if names else "null",len(names),ref_indices)
            lines += ["        "+s for s in body]+["    }"]
            if m.get("sourceParams"):
                leading=dict(m,paramShapes=m["paramShapes"][:-1],publicNames=m["publicNames"][:-1],defaults=m["defaults"][:-1])
                prefix=parameters_text(leading)
                last=m["publicNames"][-1]
                declaration=f"public {static}{m['csType']} @{m['name']}({prefix+(', ' if prefix else '')}params object?[]? {last})"
                invocation=", ".join(m["publicNames"][:-1]+["nativeParts"])
                lines += ["    "+declaration,"    {",f"        using var nativeParts=NativeParams.Create({last});",f"        {'return ' if m['shape']!='void' else ''}@{m['name']}({invocation});","    }"]
        if is_value:
            lines += [f"    public override bool Equals(object? other)=>other is {cls} value && NativeValues.Equal(NativeBox,value.NativeBox);", "    public override int GetHashCode()=>NativeValues.Hash(NativeBox);"]
        if parent=="UnityEngine.Object":
            lines += ["    public override bool Equals(object? other)=>base.Equals(other);","    public override int GetHashCode()=>base.GetHashCode();"]
        lines += ["}"]
        extensions=[m for m in methods if m.get("isExtension") and m["spec"]["isStatic"] and m["paramShapes"]]
        if extensions:
            lines += [f"public static unsafe class {cls}_SourceExtensions", "{"]
            ext_seen=set()
            for m in extensions:
                signature=(m["name"],tuple(s[0] for s in m["paramShapes"]))
                if signature in ext_seen:continue
                ext_seen.add(signature)
                generic="<T>" if m["operation"]=="generic" else ""
                constraints=" where T:RuntimeObject" if generic else ""
                parameters="this "+parameters_text(m)
                invocation=", ".join((m["paramModes"][i]+" " if p.endswith("&") else "")+m["publicNames"][i] for i,p in enumerate(m["spec"]["parameters"]))
                lines += [f"    public static {m['csType']} @{m['name']}{generic}({parameters}){constraints} => {csname(parent)}.@{m['name']}{generic}({invocation});"]
            lines += ["}"]
        lines += ["}"]*close_count
    # Real generic owner; no synthetic host singleton storage.
    if any(re.fullmatch(r"DestroyableSingleton<.+>",canonical(defs[n].get("baseType") or "")) for n in class_names):
        lines += [f"public unsafe class DestroyableSingleton<T> : {csname('UnityEngine.MonoBehaviour')} where T:RuntimeObject", "{", "    protected internal DestroyableSingleton(ulong ownedToken):base(ownedToken) {}", "    public static T? Instance=>NativeSingletons.Instance<T>();", "    public static bool InstanceExists=>NativeSingletons.Exists<T>();", "}"]
    output.mkdir(parents=True,exist_ok=True)
    generated=output/("SourceSurface.g.cs" if source_surface else "GeneratedFacades.g.cs")
    generated.write_text("\n".join(line.rstrip() for line in lines)+"\n")
    if source_surface:
        aliases=['// Own compatibility aliases for the earlier flat R&D selftests; original source uses its real namespaces.']
        for name in sorted(class_names|value_names|set(enums)):
            if ident(name)!=name:aliases.append('global using '+ident(name)+' = global::'+name.replace('+','.')+';')
        (output/'SourceAliases.g.cs').write_text('\n'.join(aliases)+'\n')
    report={"formatVersion":1,"profile":"EHR v8.0.3 IL2CPP, Steam GameLibs2026.9.29 metadata", "upstreamCommit":"ce23f0d050f617a59507e5bb0fbfff751d4b5134",
            "inputReferenceImageSha256":refs["inputSha256"],"inputDefinitionImageSha256":metadata["inputSha256"],
            "sourceGameMemberReferences":sum(r["assembly"]=='Assembly-CSharp' for r in source_rows),"sourceNativeMemberReferences":len(source_rows),"generatedSourceMemberReferences":len({(m["row"]["assembly"],m["row"]["metadataToken"]) for m in modeled if m["row"]["metadataToken"] != 0}),"explicitProbeReferences":len(probe_rows),"hookSelectorReferences":len(selector_rows),"unresolvedHookSelectors":unresolved_selectors,"uniqueNativeBindings":len(bindings),
            "unavailableSelectorSignatureTypes":selector_type_failures,
            "generatedBoxedValueClasses":len(boxed_references&class_names),"generatedValueStructs":len(value_names),"generatedClasses":len(class_names),"unsupportedReferenceCount":len(unsupported),"unsupportedByReason":dict(Counter(r["reason"] for r in unsupported)),
            "bindings":bindings,"genericMethodAdapters":[m["spec"] for m in modeled if m["operation"]=="generic"],"engineAdapters":[m["spec"] for m in modeled if m["operation"]=="engineColor"],"unsupported":unsupported,"generatedSha256":hashlib.sha256(generated.read_bytes()).hexdigest(),
            "actualGameBindingValidationPerformed":False,"fullEHRPort":False,"originalNamespaces":source_surface,
            "notes":["Generated member references are not features or runtime proof.","Harmony string-only targets require a separate patch/custom-attribute inventory.","Supported arrays and List<T> remain live native objects; unsupported generic shapes are reported explicitly.","Facade names are in EHR.Generated; full-source symbol/hierarchy/Unity Object/delegate/lifecycle adaptation remains required.","Reference members return owning strong-root wrappers, with explicit Dispose and deferred finalizer release.","Native definitions originate from Steam; exact live iOS signatures must be validated before invoking."]}
    (output/"facade-coverage.json").write_text(json.dumps(report,indent=2)+"\n")
    return report

def verify_pins(pins: dict, inputs: dict[str,Path | None]) -> None:
    if pins.get("formatVersion")!=1 or pins.get("upstreamCommit")!="ce23f0d050f617a59507e5bb0fbfff751d4b5134":raise ValueError("Unsupported input-pin manifest/version/commit")
    expected=pins.get("inputs")
    if not isinstance(expected,dict) or set(expected)!={name for name,path in inputs.items() if path is not None}:raise ValueError("Pin entries must match every provided input exactly")
    for name,path in inputs.items():
        if path is None:continue
        digest=expected[name].get("sha256","")
        if not re.fullmatch(r"[0-9a-f]{64}",digest) or hashlib.sha256(path.read_bytes()).hexdigest()!=digest:raise ValueError("Input SHA256 pin mismatch: "+name)

def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pins",type=Path,required=True,help="Own JSON manifest pinning SHA256 of every input report, not the game DLLs")
    parser.add_argument("--references",type=Path,required=True)
    parser.add_argument("--native-definitions",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--source-surface",action="store_true",help="Emit original type namespaces/inheritance for full-source compile diagnostics")
    parser.add_argument("--source-components",action="store_true",help="Bind MonoBehaviour source construction to the registered native component factory")
    parser.add_argument("--source-profile",type=Path,help="Read-only IL2CPP interop type definitions to preserve class versus value-struct source shapes")
    parser.add_argument("--selectors",type=Path,help="Semantically resolved Harmony target selectors to include nameof-only methods")
    args=parser.parse_args()
    verify_pins(json.loads(args.pins.read_text()),{"references":args.references,"nativeDefinitions":args.native_definitions,"sourceProfile":args.source_profile,"selectors":args.selectors})
    report=generate(json.loads(args.references.read_text()),json.loads(args.native_definitions.read_text()),args.output,args.source_surface,json.loads(args.selectors.read_text()) if args.selectors else None,json.loads(args.source_profile.read_text()) if args.source_profile else None,args.source_components)
    print(json.dumps({k:report[k] for k in ("sourceGameMemberReferences","generatedSourceMemberReferences","uniqueNativeBindings","generatedClasses","unsupportedReferenceCount","unsupportedByReason")},indent=2))
if __name__=="__main__":main()
