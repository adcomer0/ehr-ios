"""Exact pre-sign contracts for an explicit itch provider entry.

The platform implementation and early silent entry select the provider; the
final wrapper only observes a genuine completed flow. Connect.Login remains a
read-only validation fact, without a hook or trampoline. Outer login, guest
behavior, exact original callbacks, permissions and real EOS results remain the
runtime adapter's responsibility. The guest boundary must forward the original
or fail closed; it must never synthesize a completed migration. Offline
candidates are not runtime proofs.
"""
from copy import deepcopy
import uuid

from eos_login_hook_inputs import SOURCE_SHA, METADATA_SHA, UUID

GAME = "Assembly-CSharp.dll"
FIRSTPASS = "Assembly-CSharp-firstpass.dll"
CONNECT = "Epic.OnlineServices.Connect."
PLATFORM = "Epic.OnlineServices.Platform."
CALLBACK = CONNECT + "OnLoginCallback"
LOGIN_INFO = CONNECT + "LoginCallbackInfo&"
MAX_METHODS = 100000
MAX_JSON_BYTES = 16 * 1024 * 1024

# owner, method, image, return, parameters, RVA, token, generated RVA name
IMPL = ("EOSManager", "LoginWithCorrectPlatformImpl", GAME, "System.Void",
        (CALLBACK, "System.Action"), "0x1b0fee8", "0x600011b", "EHRItchAuthImplRVA")
SYMBOL = "_ehr_native_eos_itch_platform_impl"
TARGET = IMPL[0] + "." + IMPL[1]
TRAMPOLINE = "EHRItchAuthImplTrampolineRVA"
IMPL_NATIVE_ABI = "void(void *receiver, void *successCallback, void *failureAction, const void *methodInfo)"
FINAL = ("EOSManager", "EndFinalPartsOfLoginFlowFullAccount", GAME, "System.Void", (),
         "0x1b14364", "0x60000fe", "EHRItchAuthFinalRVA")
FINAL_SYMBOL = "_ehr_native_eos_itch_final_completed"
SILENT = ("EOSManager", "LoginSilentlyImpl", GAME, "System.Void", (),
          "0x1b0ed68", "0x6000121", "EHRItchAuthSilentRVA")
CONNECT_LOGIN = (CONNECT + "ConnectInterface", "Login", FIRSTPASS, "System.Void",
                 (CONNECT + "LoginOptions&", "System.Object", CALLBACK),
                 "0x1aab220", "0x6001dc6", "EHRItchAuthConnectLoginRVA")
FAILURE_UI = ("AccountManager", "SignInFail", GAME, "System.Void", ("EOSManager+EOS_ERRORS", "System.Action"),
              "0x1b05eac", "0x6000024", "EHRItchAuthFailureUIRVA")
GUEST_PRODUCT_USER = ("EOSManager", "get_DeviceIDProductUserId", GAME, "System.String", (),
                      "0x1b0da60", "0x60000bf", "EHRItchAuthDeviceIDProductUserIdRVA")
GUEST_MIGRATION = ("EOSManager", "CheckGuestAccountMigrationStuff", GAME, "System.Void", (),
                   "0x1b126fc", "0x60000e6", "EHRItchAuthGuestMigrationRVA")
HOOKS = ((IMPL, SYMBOL, TRAMPOLINE), (FINAL, FINAL_SYMBOL, "EHRItchAuthFinalTrampolineRVA"),
         (SILENT, "_ehr_native_eos_itch_silent_login", "EHRItchAuthSilentTrampolineRVA"),
         (GUEST_MIGRATION, "_ehr_native_eos_itch_guest_migration", "EHRItchAuthGuestMigrationTrampolineRVA"))
CONNECT_NATIVE_ABI = "void(void *receiver, void *loginOptionsByRef, void *clientData, void *callback, const void *methodInfo)"

# Only HOOKS owns entry replacements; the other rows are validation facts.
# Retry calls Impl with the original delegates and must not gain another owner.
METHODS = (IMPL,
    ("EOSManager", "LoginWithCorrectPlatform", GAME, "System.Void", (),
     "0x1b0fd70", "0x60000d3", "EHRItchAuthLoginRVA"),
    ("EOSManager", "RetryAuthAndLoginImpl", GAME, "System.Void", (CALLBACK, "System.Action"),
     "0x1b10bd0", "0x6000122", "EHRItchAuthRetryRVA"),
    ("EOSManager", "InitializeHelper", GAME, "System.Void", (),
     "0x1b14ebc", "0x600011c", "EHRItchInitializeHelperRVA"),
    ("EOSManager", "QuickLogin", GAME, "System.Void", (),
     "0x1b1506c", "0x600011d", "EHRItchAuthQuickLoginRVA"),
    SILENT,
    ("EOSManager", "EOSConnectPlatformLoginCallback", GAME, "System.Void", (LOGIN_INFO,),
     "0x1b10078", "0x60000d4", "EHRItchAuthNormalCallbackRVA"),
    ("EOSManager", "EOSConnectPlatformSilentLoginCallback", GAME, "System.Void", (LOGIN_INFO,),
     "0x1b137d0", "0x60000f5", "EHRItchAuthSilentCallbackRVA"),
    ("EOSManager", "get_PlatformInterface", GAME, PLATFORM + "PlatformInterface", (),
     "0x1b0d8f8", "0x60000bb", "EHRItchGetPlatformRVA"),
    (PLATFORM + "PlatformInterface", "GetConnectInterface", FIRSTPASS, CONNECT + "ConnectInterface", (),
     "0x1a68234", "0x60011a9", "EHRItchGetConnectRVA"),
    ("Epic.OnlineServices.Handle", "get_InnerHandle", FIRSTPASS, "System.IntPtr", (),
     "0x19ff120", "0x600013b", "EHRItchGetHandleRVA"),
    (CONNECT + "LoginCallbackInfoInternal", "Get", FIRSTPASS, "System.Void", (LOGIN_INFO,),
     "0x1aae144", "0x6001e54", "EHRItchMarshalCallbackRVA"),
    (CALLBACK, "Invoke", FIRSTPASS, "System.Void", (LOGIN_INFO,),
     "0x1aafe10", "0x6001ea8", "EHRItchInvokeCallbackRVA"),
    (CONNECT + "CredentialsInternal", "Set", FIRSTPASS, "System.Void", (CONNECT + "Credentials&",),
     "0x1aad608", "0x6001e07", "EHRItchCredentialsSetRVA"),
    (CONNECT + "LoginOptionsInternal", "Set", FIRSTPASS, "System.Void", (CONNECT + "LoginOptions&",),
     "0x1aab3bc", "0x6001e59", "EHRItchLoginOptionsSetRVA"),
    FINAL,
    FAILURE_UI,
    CONNECT_LOGIN,
    GUEST_PRODUCT_USER,
    GUEST_MIGRATION,
)


def selectors():
    return {"schema": "ehr.native-target-selectors.v1", "selectors": [
        {"selectorId": "itch-auth-" + str(index + 1), "image": image,
         "declaringType": owner, "methodName": name,
         "methodKind": "Getter" if name.startswith("get_") else "Normal",
         "returnType": returns, "parameterTypes": list(params), "isStatic": False}
        for index, (owner, name, image, returns, params, *_rest) in enumerate(METHODS)]}


def _rva(value):
    try:
        if not isinstance(value, str):
            raise ValueError()
        result = int(value, 0)
        if result <= 0 or result >= 1 << 64 or result % 4:
            raise ValueError()
        return result
    except (TypeError, ValueError):
        raise ValueError("Invalid itch auth entry address") from None


def candidates(report):
    if not isinstance(report, dict):
        raise ValueError("Invalid itch auth candidate document")
    rows = report.get("selectors")
    if (report.get("schema") != "ehr.harmony-native-target-map.v1" or
            report.get("runtime_execution_performed") is not False or
            report.get("native_hooks_installed") is not False or
            not isinstance(rows, list) or len(rows) != len(METHODS) or
            any(not isinstance(row, dict) for row in rows)):
        raise ValueError("Itch auth requires an exact, nonexecuting metadata candidate report")
    result = []
    for expected, fact in zip(selectors()["selectors"], METHODS):
        owner, name, image, returns, params, rva, token, _constant = fact
        matches = [row for row in rows if row.get("selector_id") == expected["selectorId"]]
        if len(matches) != 1:
            raise ValueError("Absent/ambiguous itch auth metadata candidate")
        row, candidate = matches[0], matches[0].get("candidate")
        if not isinstance(candidate, dict) or row.get("selector") != expected:
            raise ValueError("Itch auth selector identity differs")
        if (row.get("status") != "exact_metadata_native_candidate" or
                candidate.get("association") != "offline_codegen_module_token_rid_candidate" or
                candidate.get("runtime_association_verified") is not False or
                candidate.get("declaring_type") != owner or candidate.get("name") != name or
                candidate.get("owning_image") != image or candidate.get("return_type") != returns or
                candidate.get("parameter_types") != list(params) or candidate.get("native_rva") != rva or
                candidate.get("metadata_token") != token or
                any(candidate.get(key) is not False for key in ("static", "generic", "abstract", "shared_entry")) or
                type(candidate.get("registered_module_entry_count")) is not int or
                candidate["registered_module_entry_count"] != 1 or
                type(candidate.get("registered_generic_entry_count")) is not int or
                candidate["registered_generic_entry_count"] != 0):
            raise ValueError("Itch auth exact method ABI/entry evidence differs")
        if any(fact == hook[0] for hook in HOOKS):
            relocation = candidate.get("first_instruction_relocation")
            if not isinstance(relocation, dict) or relocation.get("status") != "supported_at_report_probe_slot":
                raise ValueError("Itch auth hook has no reviewed relocatable entry")
        result.append(candidate)
    return result


def validate_report(base, report):
    if not isinstance(base, dict) or not isinstance(report, dict):
        raise ValueError("Invalid itch auth input document")
    for key, expected in (("metadata_version", 31), ("framework_uuid", UUID), ("preferred_image_base", "0x0")):
        if base.get(key) != expected or report.get(key) != expected:
            raise ValueError("Itch auth input identity differs: " + key)
    for key, sha in (("framework", SOURCE_SHA), ("metadata", METADATA_SHA)):
        base_pins, report_pins = base.get("input_pins"), report.get("input_pins")
        if not isinstance(base_pins, dict) or not isinstance(report_pins, dict):
            raise ValueError("Invalid itch auth input pins")
        pin = base_pins.get(key)
        if (not isinstance(pin, dict) or pin.get("sha256") != sha or
                type(pin.get("size")) is not int or pin["size"] <= 0 or
                report_pins.get(key) != pin):
            raise ValueError("Itch auth input pin differs: " + key)
    return candidates(report)


def merge_itch_auth_inputs(base, report, extra_contracts):
    selected = validate_report(base, report)
    methods = base.get("methods")
    if (not isinstance(methods, list) or len(methods) + len(HOOKS) > MAX_METHODS or
            any(not isinstance(method, dict) for method in methods)):
        raise ValueError("Invalid/bounded existing native map")
    if (not isinstance(extra_contracts, dict) or extra_contracts.get("schema") != "ehr.native-hook-contracts.v1" or
            not isinstance(extra_contracts.get("methods"), dict) or len(extra_contracts["methods"]) + len(HOOKS) > MAX_METHODS):
        raise ValueError("Invalid/bounded existing native contracts")
    merged, contracts = deepcopy(base), deepcopy(extra_contracts)
    names = []
    for fact, symbol, _trampoline in HOOKS:
        owner, name, _image, returns, params, rva, token, _constant = fact
        target = owner + "." + name
        if target in contracts["methods"] or any(
                (row.get("declaring_type") == owner and row.get("name") == name) or
                (row.get("native_rva") is not None and _rva(row["native_rva"]) == _rva(rva)) for row in merged["methods"]):
            raise ValueError("Itch auth hook duplicate or entry alias")
        candidate = selected[METHODS.index(fact)]
        merged["methods"].append({"declaring_type": owner, "name": name, "return_type": returns,
            "parameters": [{"type": value} for value in params], "static": False,
            "native_rva": rva, "token": candidate["metadata_token"], "mapping": "codegen_module_token_rid"})
        contracts["methods"][target] = {"declaring_type": owner, "name": name, "return": returns,
            "parameters": list(params), "static": False, "symbol": symbol}
        names.append(target)
    return merged, contracts, names


def binding_header(manifest, report):
    validate_report(report, report)
    if (not isinstance(manifest, dict) or manifest.get("framework_uuid") != UUID or
            manifest.get("source_sha256") != SOURCE_SHA):
        raise ValueError("Itch auth installed manifest provenance differs")
    hooks = manifest.get("hooks")
    if (not isinstance(hooks, list) or len(hooks) > MAX_METHODS or any(not isinstance(row, dict) for row in hooks)):
        raise ValueError("Invalid/bounded itch auth installed manifest")
    sites = {_rva(fact[5]) for fact in METHODS}
    installed = []
    for fact, symbol, constant in HOOKS:
        target = fact[0] + "." + fact[1]
        rows = [row for row in hooks if row.get("method") == target]
        if len(rows) != 1:
            raise ValueError("Absent/ambiguous itch auth installed entry")
        row = rows[0]
        if (row.get("method_rva") != fact[5] or row.get("original_rva") != fact[5] or
                row.get("metadata_token") != fact[6] or row.get("symbol") != symbol or
                row.get("signature") != {"return": fact[3], "parameters": list(fact[4]), "static": False}):
            raise ValueError("Itch auth installed contract differs")
        trampoline = _rva(row.get("trampoline_rva"))
        if trampoline in sites:
            raise ValueError("Itch auth trampoline aliases a reviewed method")
        sites.add(trampoline)
        for other in hooks:
            if other is row:
                continue
            if (other.get("symbol") == symbol or any(
                    other.get(key) is not None and _rva(other[key]) == _rva(fact[5])
                    for key in ("original_rva", "method_rva"))):
                raise ValueError("Itch auth installed entry has another owner")
            for key in ("original_rva", "method_rva", "trampoline_rva", "stub_rva", "got_rva"):
                if other.get(key) is not None and _rva(other[key]) == trampoline:
                    raise ValueError("Itch auth trampoline aliases an installed entry")
        installed.append((constant, trampoline))
    lines = ["#pragma once", "#include <stdint.h>",
        "// Reviewed source identity; runtime must also validate the final loaded image.",
        'static const char EHRItchAuthSourceSHA256Hex[] = "' + SOURCE_SHA + '";',
        'static const char EHRItchAuthMetadataSHA256Hex[] = "' + METADATA_SHA + '";',
        "static const uint8_t EHRItchAuthFrameworkUUID[16] = {" +
            ",".join(str(value) for value in uuid.UUID(UUID).bytes) + "};",
        "// Instance ABI retains both exact delegate references and hidden MethodInfo."]
    lines.extend("static const uintptr_t " + constant + " = " + hex(value) + ";" for constant, value in installed)
    lines.extend("static const uintptr_t " + fact[7] + " = " + fact[5] + ";" for fact in METHODS)
    return "\n".join(lines) + "\n"


def read_json(path):
    import json
    if path.stat().st_size > MAX_JSON_BYTES:
        raise ValueError("Itch auth JSON input exceeds bound")
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError("Itch auth JSON document must be an object")
    return value


def private_output(path):
    resolved = path.resolve()
    if any((parent / ".git").exists() for parent in (resolved, *resolved.parents)):
        raise ValueError("Generated itch auth inputs must remain outside Git")
    return resolved


def main():
    import argparse
    import json
    import os
    from pathlib import Path
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)
    select = sub.add_parser("selectors"); select.add_argument("--output", type=Path, required=True)
    merge = sub.add_parser("merge")
    for key in ("base", "report", "contracts", "output"):
        merge.add_argument("--" + key, type=Path, required=True)
    header = sub.add_parser("header")
    for key in ("manifest", "report", "output"):
        header.add_argument("--" + key, type=Path, required=True)
    args = parser.parse_args()
    output = private_output(args.output)
    if args.mode == "merge":
        merged, contracts, names = merge_itch_auth_inputs(read_json(args.base), read_json(args.report), read_json(args.contracts))
        output.mkdir(parents=True, exist_ok=False, mode=0o700)
        documents = (("itch-auth-hook-map.local.json", merged), ("itch-auth-hook-contracts.local.json", contracts),
                     ("itch-auth-hook-names.json", names))
        for filename, document in documents:
            fd = os.open(output / filename, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as stream: json.dump(document, stream, indent=2); stream.write("\n")
    else:
        text = (json.dumps(selectors(), indent=2) + "\n" if args.mode == "selectors" else
                binding_header(read_json(args.manifest), read_json(args.report)))
        output.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream: stream.write(text)


if __name__ == "__main__": main()
