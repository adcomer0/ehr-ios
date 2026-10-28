"""Exact, passive EOS diagnostic entry contracts; no EHR target IDs are added.

Input is the existing read-only native mapper's three-selector report. The
normal patcher still proves each selected entry's final relocation and symbol.
"""
from copy import deepcopy

SOURCE_SHA = "42e47c2e676fd5389385d12ddefc45bdcb88a9c3db54285381521abb762ba84f"
METADATA_SHA = "22dd824b108490c49962b7e31c30eae0055ce0b72e39aac3fa159324d6dd529c"
UUID = "a287ea19-e914-3fe9-b2a1-2415ce6e73e9"
PARAMETER = "Epic.OnlineServices.Connect.LoginCallbackInfo&"
METHODS = (
    ("EOSConnectPlatformLoginCallback", "0x1b10078", "0x60000d4", "_ehr_native_eos_platform_login_observer", "EHREOSPlatformLoginTrampolineRVA"),
    ("EOSConnectPlatformSilentLoginCallback", "0x1b137d0", "0x60000f5", "_ehr_native_eos_silent_login_observer", "EHREOSPlatformSilentLoginTrampolineRVA"),
)
GETTER = ("Epic.OnlineServices.Connect.LoginCallbackInfo", "get_ResultCode", "Assembly-CSharp-firstpass.dll", "Epic.OnlineServices.Result", [], "0x1aae088", "0x6001e49")


def selectors():
    rows = [{"selectorId": "eos-diagnostic-"+str(i+1), "image": "Assembly-CSharp.dll",
        "declaringType": "EOSManager", "methodName": name, "methodKind": "Normal",
        "returnType": "System.Void", "parameterTypes": [PARAMETER], "isStatic": False}
        for i, (name, *_rest) in enumerate(METHODS)]
    rows.append({"selectorId": "eos-diagnostic-getter", "image": GETTER[2], "declaringType": GETTER[0],
        "methodName": GETTER[1], "methodKind": "Getter", "returnType": GETTER[3],
        "parameterTypes": [], "isStatic": False})
    return {"schema": "ehr.native-target-selectors.v1", "selectors": rows}


def candidates(report):
    if report.get("schema") != "ehr.harmony-native-target-map.v1":
        raise ValueError("Unsupported EOS diagnostic map schema")
    rows = report.get("selectors", [])
    expected = [("EOSManager", name, "Assembly-CSharp.dll", "System.Void", [PARAMETER], rva, token)
        for name, rva, token, *_rest in METHODS] + [GETTER]
    if len(rows) != 3:
        raise ValueError("EOS diagnostic report requires exactly three metadata candidates")
    result = []
    for owner, name, image, returns, params, rva, token in expected:
        matches = [r for r in rows if r.get("candidate", {}).get("declaring_type") == owner
            and r["candidate"].get("name") == name]
        if len(matches) != 1:
            raise ValueError("Absent/ambiguous EOS metadata candidate")
        row, candidate = matches[0], matches[0]["candidate"]
        if (row.get("status") != "exact_metadata_native_candidate" or
            any(candidate.get(k) is not False for k in ("generic", "abstract", "shared_entry")) or
            candidate.get("owning_image") != image or candidate.get("return_type") != returns or
            candidate.get("parameter_types") != params or candidate.get("static") is not False or
            candidate.get("native_rva") != rva or candidate.get("metadata_token") != token or
            candidate.get("registered_module_entry_count") != 1 or candidate.get("registered_generic_entry_count") != 0):
            raise ValueError("EOS diagnostic exact ABI/entry evidence differs")
        result.append(candidate)
    return result


def merge_eos_login_inputs(base, report, extra_contracts):
    for key, expected in (("metadata_version", 31), ("framework_uuid", UUID), ("preferred_image_base", "0x0")):
        if base.get(key) != expected or report.get(key) != expected:
            raise ValueError("EOS diagnostic input identity mismatch: " + key)
    for key, expected in (("framework", SOURCE_SHA), ("metadata", METADATA_SHA)):
        pin = base.get("input_pins", {}).get(key)
        if not pin or pin.get("sha256") != expected or report.get("input_pins", {}).get(key) != pin:
            raise ValueError("EOS diagnostic input pin mismatch: " + key)
    if extra_contracts.get("schema") != "ehr.native-hook-contracts.v1" or not isinstance(extra_contracts.get("methods"), dict):
        raise ValueError("Unsupported existing native contracts")
    selected = candidates(report)
    merged, contracts, names = deepcopy(base), deepcopy(extra_contracts), []
    for candidate, (name, rva, _token, symbol, _constant) in zip(selected, METHODS):
        key = "EOSManager." + name
        if key in contracts["methods"] or any(m.get("declaring_type") == "EOSManager" and m.get("name") == name
                or int(m.get("native_rva") or "0", 0) == int(rva, 0) for m in merged["methods"]):
            raise ValueError("EOS diagnostic hook duplicate or entry alias")
        merged["methods"].append({"declaring_type": "EOSManager", "name": name,
            "return_type": "System.Void", "parameters": [{"type": PARAMETER}], "static": False,
            "native_rva": rva, "token": candidate["metadata_token"], "mapping": "codegen_module_token_rid"})
        contracts["methods"][key] = {"declaring_type": "EOSManager", "name": name,
            "return": "System.Void", "parameters": [PARAMETER], "static": False, "symbol": symbol}
        names.append(key)
    return merged, contracts, names


def binding_header(manifest):
    if manifest.get("framework_uuid") != UUID or manifest.get("source_sha256") != SOURCE_SHA:
        raise ValueError("EOS installed manifest input provenance differs")
    lines = ["#pragma once", "#include <stdint.h>"]
    sites = set()
    for name, rva, token, symbol, constant in METHODS:
        matches = [r for r in manifest.get("hooks", []) if r.get("method") == "EOSManager." + name]
        if len(matches) != 1:
            raise ValueError("Absent/ambiguous EOS installed entry")
        row = matches[0]
        if (row.get("original_rva") != rva or row.get("metadata_token") != token or row.get("symbol") != symbol or
            row.get("signature") != {"return": "System.Void", "parameters": [PARAMETER], "static": False}):
            raise ValueError("EOS installed entry contract differs")
        value = int(row["trampoline_rva"], 0)
        if value <= 0 or value % 4 or value in sites:
            raise ValueError("Invalid/shared EOS trampoline")
        sites.add(value)
        lines.append("static const uintptr_t " + constant + " = " + hex(value) + ";")
    return "\n".join(lines) + "\n"


def main():
    import argparse
    import json
    from pathlib import Path
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)
    select = sub.add_parser("selectors"); select.add_argument("--output", type=Path, required=True)
    merge = sub.add_parser("merge")
    for key in ("base", "report", "contracts", "output"):
        merge.add_argument("--"+key, type=Path, required=True)
    header = sub.add_parser("header")
    header.add_argument("--manifest", type=Path, required=True); header.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    def read(path):
        if path.stat().st_size > 16 * 1024 * 1024:
            raise ValueError("EOS diagnostic input exceeds bound")
        return json.loads(path.read_text())
    if args.mode == "selectors":
        with args.output.open("x") as stream: json.dump(selectors(), stream, indent=2); stream.write("\n")
    elif args.mode == "header":
        with args.output.open("x") as stream: stream.write(binding_header(read(args.manifest)))
    else:
        merged, contracts, names = merge_eos_login_inputs(read(args.base), read(args.report), read(args.contracts))
        args.output.mkdir(parents=True, exist_ok=False)
        for name, document in (("eos-hook-map.local.json", merged), ("eos-hook-contracts.local.json", contracts),
                ("eos-hook-names.json", names)):
            (args.output/name).write_text(json.dumps(document, indent=2)+"\n")


if __name__ == "__main__": main()
