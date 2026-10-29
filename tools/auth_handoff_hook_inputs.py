"""Exact passive Apple-to-EOS handoff entry contracts; no target IDs are added."""
from copy import deepcopy

from eos_login_hook_inputs import SOURCE_SHA, METADATA_SHA, UUID

FIRSTPASS = "Assembly-CSharp-firstpass.dll"
PREFIX = "Epic.OnlineServices.Connect."
# owner, name, image, return, parameters, RVA, token, symbol, header constant
METHODS = (
    ("EOSManager", "OnGetCredentials", "Assembly-CSharp.dll", "System.Void",
     ["AppleAuth.Interfaces.ICredential"], "0x1b15150", "0x600011e",
     "_ehr_native_auth_handoff_credentials", "EHRAuthHandoffCredentialsTrampolineRVA"),
    (PREFIX + "ConnectInterface", "Login", FIRSTPASS, "System.Void",
     [PREFIX + "LoginOptions&", "System.Object", PREFIX + "OnLoginCallback"],
     "0x1aab220", "0x6001dc6", "_ehr_native_auth_handoff_login", "EHRAuthHandoffLoginTrampolineRVA"),
    (PREFIX + "CredentialsInternal", "Set", FIRSTPASS, "System.Void",
     [PREFIX + "Credentials&"], "0x1aad608", "0x6001e07",
     "_ehr_native_auth_handoff_set", "EHRAuthHandoffSetTrampolineRVA"),
)
GETTER = (PREFIX + "Credentials", "get_Type", FIRSTPASS,
          "Epic.OnlineServices.ExternalCredentialType", [], "0x1aad5f8", "0x6001e05")
MAX_METHODS = 100000


def selectors():
    facts = [row[:7] for row in METHODS] + [GETTER]
    return {"schema": "ehr.native-target-selectors.v1", "selectors": [
        {"selectorId": "auth-handoff-" + str(i + 1), "image": image,
         "declaringType": owner, "methodName": name,
         "methodKind": "Getter" if name == "get_Type" else "Normal",
         "returnType": returns, "parameterTypes": list(params), "isStatic": False}
        for i, (owner, name, image, returns, params, *_rest) in enumerate(facts)]}


def candidates(report):
    rows = report.get("selectors")
    if (report.get("schema") != "ehr.harmony-native-target-map.v1" or
            not isinstance(rows, list) or len(rows) != 4):
        raise ValueError("Auth handoff requires exactly four metadata candidates")
    result = []
    for owner, name, image, returns, params, rva, token in [r[:7] for r in METHODS] + [GETTER]:
        matches = [r for r in rows if isinstance(r, dict) and isinstance(r.get("candidate"), dict)
                   and r["candidate"].get("declaring_type") == owner and r["candidate"].get("name") == name]
        if len(matches) != 1:
            raise ValueError("Absent/ambiguous auth handoff metadata candidate")
        row, candidate = matches[0], matches[0]["candidate"]
        if (row.get("status") != "exact_metadata_native_candidate" or
                any(candidate.get(k) is not False for k in ("static", "generic", "abstract", "shared_entry")) or
                candidate.get("owning_image") != image or candidate.get("return_type") != returns or
                candidate.get("parameter_types") != params or candidate.get("native_rva") != rva or
                candidate.get("metadata_token") != token or
                type(candidate.get("registered_module_entry_count")) is not int or
                candidate["registered_module_entry_count"] != 1 or
                type(candidate.get("registered_generic_entry_count")) is not int or
                candidate["registered_generic_entry_count"] != 0):
            raise ValueError("Auth handoff exact ABI/entry evidence differs")
        result.append(candidate)
    return result


def validate_report(base, report):
    for key, expected in (("metadata_version", 31), ("framework_uuid", UUID), ("preferred_image_base", "0x0")):
        if base.get(key) != expected or report.get(key) != expected:
            raise ValueError("Auth handoff input identity mismatch: " + key)
    for key, expected in (("framework", SOURCE_SHA), ("metadata", METADATA_SHA)):
        pin = base.get("input_pins", {}).get(key)
        if not isinstance(pin, dict) or pin.get("sha256") != expected or report.get("input_pins", {}).get(key) != pin:
            raise ValueError("Auth handoff input pin mismatch: " + key)
    return candidates(report)


def _rva(value):
    try:
        if not isinstance(value, str):
            raise ValueError()
        result = int(value, 0)
        if result <= 0 or result >= 1 << 64 or result % 4:
            raise ValueError()
        return result
    except (TypeError, ValueError):
        raise ValueError("Invalid auth handoff entry address") from None


def merge_auth_handoff_inputs(base, report, extra_contracts):
    selected = validate_report(base, report)
    methods = base.get("methods")
    if not isinstance(methods, list) or len(methods) > MAX_METHODS or any(not isinstance(m, dict) for m in methods):
        raise ValueError("Invalid/bounded existing native map")
    if extra_contracts.get("schema") != "ehr.native-hook-contracts.v1" or not isinstance(extra_contracts.get("methods"), dict):
        raise ValueError("Unsupported existing native contracts")
    merged, contracts, names = deepcopy(base), deepcopy(extra_contracts), []
    for candidate, (owner, name, _image, returns, params, rva, _token, symbol, _constant) in zip(selected, METHODS):
        key = owner + "." + name
        if key in contracts["methods"] or any(
                (m.get("declaring_type") == owner and m.get("name") == name) or
                (m.get("native_rva") is not None and _rva(m["native_rva"]) == _rva(rva))
                for m in merged["methods"]):
            raise ValueError("Auth handoff hook duplicate or entry alias")
        merged["methods"].append({"declaring_type": owner, "name": name, "return_type": returns,
            "parameters": [{"type": t} for t in params], "static": False, "native_rva": rva,
            "token": candidate["metadata_token"], "mapping": "codegen_module_token_rid"})
        contracts["methods"][key] = {"declaring_type": owner, "name": name, "return": returns,
            "parameters": list(params), "static": False, "symbol": symbol}
        names.append(key)
    return merged, contracts, names


def binding_header(manifest):
    if manifest.get("framework_uuid") != UUID or manifest.get("source_sha256") != SOURCE_SHA:
        raise ValueError("Auth handoff installed manifest provenance differs")
    hooks = manifest.get("hooks")
    if not isinstance(hooks, list) or len(hooks) > MAX_METHODS or any(not isinstance(r, dict) for r in hooks):
        raise ValueError("Invalid/bounded auth handoff installed manifest")
    lines = ["#pragma once", "#include <stdint.h>"]
    sites = {_rva(r[5]) for r in METHODS} | {_rva(GETTER[5])}
    for owner, name, _image, returns, params, rva, token, symbol, constant in METHODS:
        rows = [r for r in hooks if r.get("method") == owner + "." + name]
        if len(rows) != 1:
            raise ValueError("Absent/ambiguous auth handoff installed entry")
        row = rows[0]
        if (row.get("original_rva") != rva or row.get("method_rva") != rva or row.get("metadata_token") != token or
                row.get("symbol") != symbol or row.get("signature") != {
                    "return": returns, "parameters": params, "static": False}):
            raise ValueError("Auth handoff installed entry contract differs")
        value = _rva(row.get("trampoline_rva"))
        if value in sites:
            raise ValueError("Shared/aliased auth handoff trampoline")
        sites.add(value)
        lines.append("static const uintptr_t " + constant + " = " + hex(value) + ";")
    lines.append("static const uintptr_t EHRAuthHandoffCredentialTypeGetterRVA = " + GETTER[5] + ";")
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
        merge.add_argument("--" + key, type=Path, required=True)
    header = sub.add_parser("header")
    header.add_argument("--manifest", type=Path, required=True); header.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if any((p / ".git").exists() for p in args.output.resolve().parents):
        parser.error("Generated auth handoff inputs must remain outside Git")
    def read(path):
        if path.stat().st_size > 16 * 1024 * 1024:
            raise ValueError("Auth handoff input exceeds bound")
        return json.loads(path.read_text())
    if args.mode == "selectors":
        with args.output.open("x") as stream: json.dump(selectors(), stream, indent=2); stream.write("\n")
    elif args.mode == "header":
        with args.output.open("x") as stream: stream.write(binding_header(read(args.manifest)))
    else:
        merged, contracts, names = merge_auth_handoff_inputs(read(args.base), read(args.report), read(args.contracts))
        args.output.mkdir(parents=True, exist_ok=False)
        for name, document in (("auth-handoff-hook-map.local.json", merged),
                ("auth-handoff-hook-contracts.local.json", contracts), ("auth-handoff-hook-names.json", names)):
            (args.output / name).write_text(json.dumps(document, indent=2) + "\n")


if __name__ == "__main__": main()
