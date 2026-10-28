"""Validate the optional exact-version iterator carrier hook input.

This combines declarations and input pins only. The final patcher still verifies
the framework hash, exact signatures, distinct entries and final relocations.
"""
from copy import deepcopy

OWNER = "System.Collections.ArrayList+ArrayListEnumeratorSimple"
ITERATOR_METHODS = (
    ("MoveNext", "System.Boolean", "0x367ade0", "_ehr_native_iterator_move_next_hook", "EHRIteratorMoveTrampolineRVA"),
    ("get_Current", "System.Object", "0x367afe4", "_ehr_native_iterator_current_hook", "EHRIteratorCurrentTrampolineRVA"),
    ("Reset", "System.Void", "0x367b0dc", "_ehr_native_iterator_reset_hook", "EHRIteratorResetTrampolineRVA"),
)


def merge_iterator_inputs(base, iterator, extra_contracts):
    if iterator.get("schema") != "ehr.harmony-native-target-map.v1":
        raise ValueError("Unsupported iterator map schema")
    for key in ("metadata_version", "framework_uuid", "preferred_image_base"):
        if iterator.get(key) != base.get(key):
            raise ValueError("Iterator map does not match the game input: " + key)
    for key in ("framework", "metadata"):
        expected = base.get("input_pins", {}).get(key)
        if not expected or iterator.get("input_pins", {}).get(key) != expected:
            raise ValueError("Iterator map does not match the game input pin: " + key)
    merged, contracts = deepcopy(base), deepcopy(extra_contracts)
    if contracts.get("schema") != "ehr.native-hook-contracts.v1" or not isinstance(contracts.get("methods"), dict):
        raise ValueError("Unsupported existing hook contracts")
    names = []
    for name, returns, rva, symbol, _ in ITERATOR_METHODS:
        matches = [entry for entry in iterator.get("selectors", [])
                   if entry.get("candidate", {}).get("declaring_type") == OWNER and
                   entry["candidate"].get("name") == name]
        if len(matches) != 1:
            raise ValueError("Absent/ambiguous iterator candidate: " + name)
        entry, candidate = matches[0], matches[0]["candidate"]
        if (entry.get("status") != "exact_metadata_native_candidate" or
            candidate.get("owning_image") != "mscorlib.dll" or candidate.get("return_type") != returns or
            candidate.get("parameter_types") != [] or candidate.get("static") is not False or
            candidate.get("generic") is not False or candidate.get("abstract") is not False or
            candidate.get("shared_entry") is not False or candidate.get("native_rva") != rva or
            candidate.get("registered_module_entry_count") != 1 or candidate.get("registered_generic_entry_count") != 0):
            raise ValueError("Unsupported exact iterator signature/entry: " + name)
        key = OWNER + "." + name
        if key in contracts["methods"] or any(m["declaring_type"] == OWNER and m["name"] == name for m in merged["methods"]):
            raise ValueError("Iterator hook is already present: " + name)
        merged["methods"].append({"declaring_type": OWNER, "name": name,
            "return_type": returns, "parameters": [], "static": False,
            "native_rva": rva, "token": candidate["metadata_token"], "mapping": "codegen_module_token_rid"})
        contracts["methods"][key] = {"declaring_type": OWNER, "name": name,
            "return": returns, "parameters": [], "static": False, "symbol": symbol}
        names.append(key)
    return merged, contracts, names
