"""Read-only lexical Harmony dispatch inventory; no hook is declared executable.

This records exact source signatures, Harmony injection arguments, class/method
attributes, runtime registration and target resolvers for a build-time generator.
It intentionally does not infer native addresses or validate the IL2CPP ABI.
"""
from collections import Counter


MODIFIERS = {"public", "private", "protected", "internal", "static", "unsafe", "extern",
             "virtual", "override", "abstract", "sealed", "new", "async", "partial", "readonly"}
KINDS = {"Prefix", "Postfix", "Finalizer", "Transpiler", "ReversePatch"}
HELPERS = {"TargetMethod", "TargetMethods", "Prepare", "Cleanup"}


def qualified_type(source, declaration):
    namespaces = []
    for i, token in enumerate(source.tokens):
        if token.value != "namespace":
            continue
        j = i + 1
        while j < len(source.tokens) and source.tokens[j].value not in {";", "{"}:
            j += 1
        if j < len(source.tokens) and (source.tokens[j].value == ";" or
                j < declaration["start"] < source.pairs[j]):
            namespaces.append("".join(t.value for t in source.tokens[i + 1:j]))
    parents = sorted((d for d in source.types if d["body"] < declaration["start"] < d["end"]),
                     key=lambda d: d["body"])
    local = "+".join([d["name"] for d in parents] + [declaration["name"]])
    return ".".join(namespaces + [local])


def text(tokens):
    return " ".join(token.value for token in tokens)


def split(tokens, separator=","):
    result, current, depth = [], [], []
    for token in tokens:
        if token.kind not in {"string", "char"}:
            if token.value in "([{<":
                depth.append(token.value)
            elif token.value in ")]}>" and depth:
                depth.pop()
            elif token.value == separator and not depth:
                result.append(current)
                current = []
                continue
        current.append(token)
    if current:
        result.append(current)
    return result


def attributes(source, start):
    """Return complete consecutive attribute groups and first declaration token."""
    result, tokens, i = [], source.tokens, start
    while i < len(tokens) and tokens[i].value == "[":
        end = source.pairs[i]
        for group in split(tokens[i + 1:end]):
            if not group:
                continue
            opening = next((n for n, t in enumerate(group) if t.value == "("), None)
            name_tokens = group if opening is None else group[:opening]
            names = [t.value for t in name_tokens if t.kind == "identifier"]
            if not names:
                continue
            name = names[-1].removesuffix("Attribute")
            arguments = split(group[opening + 1:-1]) if opening is not None else []
            result.append({"name": name, "arguments": [text(a) for a in arguments],
                           "source": {**source.ref(i), "line": group[0].line,
                                      "url": source.ref(i)["url"].split("#L")[0] + f"#L{group[0].line}"}})
        i = end + 1
    return result, i


def declaration_attributes(source, declaration):
    tokens = source.tokens
    i = declaration["start"] - 1
    while i >= 0 and tokens[i].value in MODIFIERS:
        i -= 1
    reverse_pairs = {v: k for k, v in source.pairs.items()}
    while i >= 0 and tokens[i].value == "]":
        i = reverse_pairs[i] - 1
    return attributes(source, i + 1)[0]


def parameter(source, tokens):
    # Parameter attributes are independent of method/class target attributes.
    attrs, remaining = [], list(tokens)
    while remaining and remaining[0].value == "[":
        depth, end = 1, 1
        while end < len(remaining) and depth:
            depth += (remaining[end].value == "[") - (remaining[end].value == "]")
            end += 1
        attrs.append(text(remaining[1:end - 1]))
        remaining = remaining[end:]
    equal = next((i for i, t in enumerate(remaining) if t.value == "="), len(remaining))
    head = remaining[:equal]
    if not head:
        return {"raw": text(tokens), "parse_status": "unresolved"}
    name = head[-1].value
    modifiers = [t.value for t in head[:-1] if t.value in {"ref", "out", "in", "params", "this"}]
    type_tokens = [t for t in head[:-1] if t.value not in {"ref", "out", "in", "params", "this"}]
    injection = None
    if name.startswith("___"):
        injection = "original_instance_field"
    elif name in {"__instance", "__result", "__state", "__exception", "__runOriginal", "__args", "__originalMethod"}:
        injection = name
    elif name.startswith("__") and name[2:].isdigit():
        injection = "original_argument_by_index"
    elif attrs and any("HarmonyArgument" in a for a in attrs):
        injection = "original_argument_by_HarmonyArgument"
    else:
        injection = "original_argument_by_name"
    return {"name": name, "type": text(type_tokens), "modifiers": modifiers,
            "attributes": attrs, "injection": injection, "raw": text(tokens)}


def methods(source, declaration):
    tokens, result = source.tokens, []
    i, end = declaration["body"] + 1, declaration["end"]
    while i < end:
        attrs, start = attributes(source, i)
        j, opening, invalid = start, None, False
        while j < end:
            value = tokens[j].value
            if value == "(":
                opening = j
                break
            if value in {";", "{", "=", "}"}:
                invalid = True
                break
            if value == "[":
                j = source.pairs[j] + 1
                continue
            j += 1
        if opening is None or invalid:
            if j < end and tokens[j].value == "{":
                i = source.pairs[j] + 1
            else:
                i = j + 1
            continue
        close = source.pairs[opening]
        name_index = opening - 1
        # Generic method names have a type parameter list before the arguments.
        if tokens[name_index].value == ">":
            depth = 1
            name_index -= 1
            while name_index > start and depth:
                depth += (tokens[name_index].value == ">") - (tokens[name_index].value == "<")
                name_index -= 1
        if name_index < start or tokens[name_index].kind != "identifier":
            i = close + 1
            continue
        name = tokens[name_index].value
        head = tokens[start:name_index]
        if any(t.value in {"new", "=", "return", "class", "struct", "interface", "enum", "delegate"} for t in head):
            i = close + 1
            continue
        after = close + 1
        while after < end and tokens[after].value not in {"{", ";", "="}:
            after += 1
        body_start = body_end = None
        if after < end and tokens[after].value == "{":
            body_start, body_end = after, source.pairs[after]
            next_i = body_end + 1
        else:
            next_i = after + 1
            while after < end and tokens[after].value == "=" and next_i < end and tokens[next_i].value != ";":
                next_i += 1
        modifiers = [t.value for t in head if t.value in MODIFIERS]
        return_type = text([t for t in head if t.value not in MODIFIERS])
        result.append({"name": name, "return_type": return_type, "modifiers": modifiers,
            "signature": text(tokens[start:close + 1]),
            "parameters": [parameter(source, p) for p in split(tokens[opening + 1:close])],
            "attributes": attrs, "source": source.ref(name_index),
            "body_source": source.ref(body_start) if body_start is not None else None,
            "body_token_range": [body_start, body_end] if body_start is not None else None})
        i = next_i
    return result


def patch_target(attribute):
    import re
    args = attribute["arguments"]
    type_name, member, argument_types, method_kind = None, None, [], None
    for position, argument in enumerate(args):
        match = re.fullmatch(r"typeof\s*\(\s*([\w.\s]+)\s*\)", argument)
        if match:
            resolved = re.sub(r"\s+", "", match[1])
            if position == 0:
                type_name = resolved
            else:
                argument_types.append(resolved)
        match = re.fullmatch(r"nameof\s*\(\s*([\w.\s]+)\s*\)", argument)
        if match:
            member = re.sub(r"\s+", "", match[1]).split(".")[-1]
        if argument.startswith('"') and argument.endswith('"') and member is None:
            member = argument[1:-1]
        match = re.fullmatch(r"MethodType\s*\.\s*(\w+)", argument)
        if match:
            method_kind = match[1]
    return {"type": type_name, "member": member, "argument_types": argument_types,
            "method_kind": method_kind, "arguments": args, "source": attribute["source"]}


def manifest(sources):
    classes, registration, dynamic_code = [], [], []
    for source in sources:
        for declaration in source.types:
            class_attrs = declaration_attributes(source, declaration)
            member_methods = methods(source, declaration)
            class_targets = [patch_target(a) for a in class_attrs if a["name"] == "HarmonyPatch"]
            candidates = []
            for method in member_methods:
                method_patch_attrs = [a for a in method["attributes"] if a["name"] == "HarmonyPatch"]
                annotated = [a["name"].removeprefix("Harmony") for a in method["attributes"]
                             if a["name"].removeprefix("Harmony") in KINDS]
                kind = annotated or ([method["name"]] if (class_targets or method_patch_attrs) and method["name"] in KINDS else [])
                helpers = [a["name"].removeprefix("Harmony") for a in method["attributes"]
                           if a["name"].removeprefix("Harmony") in HELPERS]
                helper = helpers or ([method["name"]] if class_targets and method["name"] in HELPERS else [])
                if not kind and not helper:
                    continue
                targets = [patch_target(a) for a in method["attributes"] if a["name"] == "HarmonyPatch"]
                target_templates = targets or class_targets
                target_templates = [{**t, "type": t["type"] or next((c["type"] for c in class_targets if c["type"]), None)} for t in target_templates]
                clean_method = {k: v for k, v in method.items() if k != "body_token_range"}
                if helper and method["body_token_range"]:
                    lo, hi = method["body_token_range"]
                    clean_method["helper_body_expression"] = text(source.tokens[lo + 1:hi])
                semantics = []
                if "Prefix" in kind and method["return_type"] == "bool":
                    semantics.append("false_can_skip_original_and_affects_later_prefix_dispatch")
                if "Postfix" in kind and method["return_type"] != "void":
                    semantics.append("nonvoid_postfix_requires_Harmony_passthrough_result_semantics")
                if "Finalizer" in kind:
                    semantics.append("managed_exception_observation_or_replacement_must_be_preserved")
                if "Transpiler" in kind:
                    semantics.append("IL_rewrite_requires_native_equivalent_not_runtime_Harmony")
                if any(p.get("name") == "__state" for p in method["parameters"]):
                    semantics.append("per_original_invocation_patch_class_state")
                if any(p.get("name") == "__result" and "ref" in p.get("modifiers", []) for p in method["parameters"]):
                    semantics.append("mutable_original_result")
                if any(p.get("injection", "").startswith("original_argument") and "ref" in p.get("modifiers", []) for p in method["parameters"]):
                    semantics.append("mutable_original_argument")
                candidates.append({**clean_method, "callback_kinds": kind, "helper_kinds": helper,
                    "target_templates": target_templates, "semantic_requirements": semantics,
                    "native_adapter_status": "not_generated_or_ABI_verified_by_inventory"})
            if candidates or class_targets:
                classes.append({"class": declaration["name"], "qualified_type": qualified_type(source, declaration),
                    "source": declaration["source"],
                    "attributes": class_attrs, "class_target_templates": class_targets,
                    "dynamic_target_resolution": any(set(m["helper_kinds"]) & {"TargetMethod", "TargetMethods"} for m in candidates),
                    "callbacks_and_helpers": candidates})
        for i, name, arguments in source.calls():
            if name in {"CreateInstance", "GetTypes", "MakeGenericMethod", "MakeGenericType", "Compile"} and i > 0 and source.tokens[i - 1].value == ".":
                dynamic_code.append({"operation": name, "arguments": [text(a) for a in arguments],
                    "source": source.ref(i), "owner_type": (source.owner(i) or {}).get("name"),
                    "review_action": "preserve_AOT_roots_or_replace_dynamic_construction_with_generated_factory"})
            if name not in {"PatchAll", "Patch", "UnpatchAll", "UnpatchSelf", "Unpatch"}:
                continue
            if i < 1 or source.tokens[i - 1].value != ".":
                continue
            registration.append({"operation": name, "arguments": [text(a) for a in arguments],
                                 "source": source.ref(i), "owner_type": (source.owner(i) or {}).get("name"),
                                 "port_action": "build_time_registration_or_explicit_runtime_policy_required"})
    callbacks = [m for c in classes for m in c["callbacks_and_helpers"] if m["callback_kinds"]]
    return {"schema": "ehr.patch-dispatch-inventory.v1", "compile_profile": "IL2CPP",
        "limits": ["Lexical signatures are source facts; target templates are not resolved IL2CPP members.",
            "Harmony attribute composition, overloads, Prepare/Cleanup policy and patch ordering require semantic generation/review.",
            "No native patch, target address or ABI compatibility is claimed.",
            "Runtime map compatibility patches remain conditional external dependencies."],
        "counts": {"patch_classes": len(classes), "callback_methods": len(callbacks),
            "callback_kind_sites": dict(sorted(Counter(k for m in callbacks for k in m["callback_kinds"]).items())),
            "dynamic_target_classes": sum(c["dynamic_target_resolution"] for c in classes),
            "runtime_registration_or_unregistration_sites": len(registration),
            "reflection_or_dynamic_code_sites_for_AOT_review": len(dynamic_code)},
        "patch_classes": classes, "runtime_registration_sites": registration,
        "reflection_or_dynamic_code_sites_for_AOT_review": dynamic_code}
