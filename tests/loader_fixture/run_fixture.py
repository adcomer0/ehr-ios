#!/usr/bin/env python3
"""Build and run ONLY original-source macOS loader fixtures.

The same production entry writer is exercised on an ordinary ad-hoc-signed
macOS arm64 dylib. This is native-loader evidence, never actual game evidence.
No game input, assets, instruction fixtures, signing profiles or secrets used.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import struct
import subprocess
import sys
import uuid

STAGE = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(STAGE))
from patch_native_entries import DYLD_INFO, Image, read, sha


def run(arguments):
    result = subprocess.run([str(x) for x in arguments], check=True, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
    return result.stdout.strip()


def defined_symbols(data, image):
    command = image.command((2,))
    offset, count, string_offset, string_size = struct.unpack_from("<4I", command, 8)
    strings = data[string_offset:string_offset + string_size]
    result = {}
    for index in range(count):
        name_index, kind, section, _, value = struct.unpack_from("<IBBHQ", data, offset + index * 16)
        if kind & 0xE0 or kind & 0x0E != 0x0E or not section:
            continue
        end = strings.find(b"\0", name_index)
        name = strings[name_index:end].decode("utf-8")
        result[name] = value
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True,
                        help="New artifact directory; refuses an existing path")
    args = parser.parse_args()
    if sys.platform != "darwin" or platform.machine() != "arm64":
        parser.error("This fixture requires a native Apple Silicon macOS host")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    sources = Path(__file__).resolve().parent
    framework_dir = output / "Frameworks"
    framework_dir.mkdir()
    clang = run(["xcrun", "--find", "clang"])
    base_flags = [clang, "-target", "arm64-apple-macos13.0"]
    c_flags = [*base_flags, "-std=c11", "-Wall", "-Wextra", "-Werror"]
    run([*base_flags, "-c", sources / "fixture.S", "-o", output / "fixture.o"])
    run([*c_flags, "-c", sources / "fixture_data.c", "-o", output / "fixture_data.o"])
    original = output / "OriginalFixture.dylib"
    run([*base_flags, "-dynamiclib", output / "fixture.o", output / "fixture_data.o",
         "-Wl,-install_name,@rpath/OriginalFixture.dylib", "-Wl,-no_fixup_chains",
         "-Wl,-headerpad,0x4000", "-o", original])
    run(["codesign", "--force", "--sign", "-", original])
    original_data = original.read_bytes()
    image = Image(original_data, require_unsigned=False)
    symbols = defined_symbols(original_data, image)
    methods = []
    fixtures = [
        ("PlayerControl", "MurderPlayer", "_fixture_murder", "System.Void", False,
         [{"type": "PlayerControl"}, {"type": "MurderResultFlags"}]),
        ("Constants", "GetBroadcastVersion", "_fixture_version", "System.Int32", True, []),
        ("Fixture", "ADRP", "_fixture_adrp", "System.UInt64", True, []),
        ("Fixture", "ADR", "_fixture_adr", "System.UInt64", True, []),
        ("Fixture", "STP", "_fixture_stp", "System.Int32", True, []),
        ("Fixture", "STPD", "_fixture_stpd", "System.Double", True,
         [{"type": "System.Double"}, {"type": "System.Double"}, {"type": "System.IntPtr"}]),
        ("Fixture", "LDRB", "_fixture_ldrb", "System.UInt32", True, [{"type": "System.IntPtr"}]),
        ("Fixture", "LDRW", "_fixture_ldrw", "System.UInt32", True, [{"type": "System.IntPtr"}]),
        ("Fixture", "LDRX", "_fixture_ldrx", "System.UInt64", True, [{"type": "System.IntPtr"}]),
        ("Fixture", "LDPW", "_fixture_ldpw", "System.UInt32", True, [{"type": "System.IntPtr"}]),
    ]
    for index, (declaring, name, symbol, returns, static, parameters) in enumerate(fixtures):
        methods.append({"declaring_type": declaring, "name": name, "return_type": returns,
                        "parameters": parameters, "static": static, "token": hex(0x06000001 + index),
                        "mapping": "codegen_module_token_rid",
                        "native_rva": hex(symbols[symbol] - image.preferred_base),
                        "fixture_source_symbol": symbol})
    report = {"fixture_only": True,
              "note": "Logical method contract labels exercise the production validator; no game metadata was read.",
              "framework_uuid": image.uuid,
              "input_pins": {"framework": {"sha256": sha(original_data)}}, "methods": methods}
    map_path = output / "fixture-method-map.json"
    map_path.write_text(json.dumps(report, indent=2) + "\n")
    contracts = {"schema": "ehr.native-hook-contracts.v1", "methods": {}}
    extra_names = []
    for declaring, name, _, returns, static, parameters in fixtures[2:]:
        extra_names.append(name)
        contracts["methods"][declaring + "." + name] = {
            "declaring_type": declaring, "name": name, "return": returns,
            "parameters": [p["type"] for p in parameters], "static": static,
            "symbol": "_ehr_fixture_" + name.lower() + "_hook"}
    contracts_path = output / "fixture-contracts.json"
    contracts_path.write_text(json.dumps(contracts, indent=2) + "\n")
    patched = output / "PatchedFixture.dylib"
    patch_command = [sys.executable, STAGE / "patch_native_entries.py", "--input", original,
         "--map", map_path, "--output", patched, "--hook", "PlayerControl.MurderPlayer",
         "--hook", "Constants.GetBroadcastVersion", "--contracts", contracts_path]
    for name in extra_names:
        patch_command += ["--hook", "Fixture." + name]
    run(patch_command)
    manifest_path = patched.with_name(patched.name + ".manifest.json")
    manifest = json.loads(manifest_path.read_text())
    hooks = {hook["method"]: hook for hook in manifest["hooks"]}
    header = "static const unsigned char fixture_uuid[16] = {%s};\n" % ",".join(
        "0x%02x" % byte for byte in uuid.UUID(image.uuid).bytes)
    header += "#define FIXTURE_MURDER_TRAMPOLINE %sULL\n" % hooks["PlayerControl.MurderPlayer"]["trampoline_preferred_va"]
    header += "#define FIXTURE_VERSION_TRAMPOLINE %sULL\n" % hooks["Constants.GetBroadcastVersion"]["trampoline_preferred_va"]
    for name in extra_names:
        header += "#define FIXTURE_%s_TRAMPOLINE %sULL\n" % (name, hooks["Fixture." + name]["trampoline_preferred_va"])
    if hooks["Fixture.ADRP"]["relocation"]["strategy"] != "ADRP":
        raise RuntimeError("Original ADRP fixture did not exercise address-aware page relocation")
    if hooks["Fixture.ADR"]["relocation"]["strategy"] != "ADRP+ADD":
        raise RuntimeError("Original ADR fixture did not force an expanded trampoline")
    if not hooks["Fixture.STP"]["relocation"]["kind"].startswith("STP"):
        raise RuntimeError("Original STP fixture did not exercise its pre-index prologue")
    (output / "fixture_pins.h").write_text(header)
    helper = framework_dir / "EHRNativeHooks.dylib"
    run([*c_flags, "-dynamiclib", "-I", output, sources / "hooks.c", "-o", helper,
         "-Wl,-install_name,@executable_path/Frameworks/EHRNativeHooks.dylib"])
    harness = output / "harness"
    run([*c_flags, sources / "harness.c", "-o", harness])
    for executable in (helper, patched, harness):
        run(["codesign", "--force", "--sign", "-", executable])
        run(["codesign", "--verify", "--strict", "--verbose=2", executable])
    # Plain nm can skip dyld binds when a fixture retains its symbol table.
    # Force the exact LLVM bind-validation path used for stripped large apps.
    dyld_symbols = run(["xcrun", "nm", "--dyldinfo-only", patched])
    expected_bindings = ["_ehr_native_murder_hook", "_ehr_native_broadcast_version_hook"] + [
        "_ehr_fixture_" + name.lower() + "_hook" for name in extra_names]
    if not all(symbol in dyld_symbols for symbol in expected_bindings):
        raise RuntimeError("Apple nm did not expose every native handler binding")
    run(["xcrun", "dyld_info", "-validate_only", patched])
    runs = [json.loads(run([harness, patched])) for _ in range(2)]
    if not all(item["pass"] for item in runs):
        raise RuntimeError("A loader fixture assertion failed")
    if runs[0]["loaded_base"] == runs[1]["loaded_base"]:
        raise RuntimeError("Two fixture launches did not exhibit different ASLR bases")
    if sha(original.read_bytes()) != sha(original_data):
        raise RuntimeError("Original fixture changed")
    result = {"purpose": "Own-source macOS arm64 native loader integration test",
              "actual_game_executed": False, "runtime_executable_memory_writes": False,
              "signing": "Ordinary ad-hoc codesign of original-source native macOS test code",
              "classic_dyld_bind_stream": True,
              "apple_nm_forced_dyldinfo_validation": True,
              "apple_dyld_info_validation": True,
              "original_dyld_info_offsets_and_sizes": list(read(image.command(DYLD_INFO), "<10I", 8)),
              "source_sha256": {path.name: sha(path.read_bytes()) for path in [
                  sources / "fixture.S", sources / "fixture_data.c", sources / "hooks.c",
                  sources / "harness.c", sources / "run_fixture.py", STAGE / "patch_native_entries.py"]},
              "original_fixture_sha256": sha(original_data),
              "signed_patched_fixture_sha256": sha(patched.read_bytes()),
              "framework_uuid": image.uuid, "source_fixture_unchanged": True,
              "entry_writer": str(STAGE / "patch_native_entries.py"),
              "entry_manifest": str(manifest_path), "different_aslr_bases": True,
              "pc_relative_targets_verified_by_runtime_symbol_address": True,
              "adr_expanded_to_adrp_add": True,
              "stp_preindex_stack_frame_executed": True,
              "stpd_preindex_callee_saved_lanes_verified": True,
              "integer_load_widths_offsets_and_values_verified": True,
              "hook_count": len(fixtures),
              "runs": runs,
              "limitations": ["This validates the static writer and native loader using original test code.",
                              "It does not establish iOS provisioning, game startup, metadata ABI correctness or role compatibility."]}
    result_path = output / "loader-proof.json"
    result_path.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"pass": True, "proof": str(result_path), "runs": runs}, indent=2))


if __name__ == "__main__":
    main()
