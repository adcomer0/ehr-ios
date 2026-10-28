from __future__ import annotations

import copy
import hashlib
import struct
import unittest

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from patch_native_entries import Image, METHODS, PAGE, PatchError, branch, decode_leb, read, select_hooks, sha, transform, uleb, validate_program, validate_relocated_instruction


def command(kind, body):
    size = (8 + len(body) + 7) & -8
    return struct.pack("<II", kind, size) + body + b"\0" * (size - 8 - len(body))


def synthetic_image():
    """Entirely original synthetic Mach-O; contains no game byte fixture."""
    blob = bytearray(0x8100)
    section = struct.pack("<16s16sQQIIIIIIII", b"__text", b"__TEXT", 0x1000, 0x100, 0x1000, 2, 0x8080, 1, 0x80000400, 0, 0, 0)
    text = command(0x19, struct.pack("<16sQQQQiiII", b"__TEXT", 0, 0x4000, 0, 0x4000, 5, 5, 1, 0) + section)
    data = command(0x19, struct.pack("<16sQQQQiiII", b"__DATA", 0x4000, 0x8000, 0x4000, 0x4000, 3, 3, 0, 0))
    linkedit = command(0x19, struct.pack("<16sQQQQiiII", b"__LINKEDIT", 0xC000, 0x4000, 0x8000, 0x100, 1, 1, 0, 0))
    rebase = b"\x11\x21\x00\x51\x00"
    normal = b"\x11\x40_old\0\x51\x71\x00\x90\x00"
    blob[0x8000:0x8000 + len(rebase)] = rebase
    blob[0x8010:0x8010 + len(normal)] = normal
    dyld = command(0x80000022, struct.pack("<10I", 0x8000, len(rebase), 0x8010, len(normal), 0, 0, 0, 0, 0, 0))
    symtab = command(2, struct.pack("<4I", 0x8040, 1, 0x8050, 16))
    dynamic = [0] * 18
    dynamic[12], dynamic[13] = 0x8060, 1
    dysymtab = command(0xB, struct.pack("<18I", *dynamic))
    identity = command(0x1B, bytes(range(16)))
    encryption = command(0x2C, struct.pack("<4I", 0x1000, 0x100, 0, 0))
    functions = command(0x26, struct.pack("<II", 0x8070, 2))
    library = command(0xC, struct.pack("<4I", 24, 0, 0x10000, 0x10000) + b"/usr/lib/libSystem.B.dylib\0")
    cmds = [text, data, linkedit, dyld, symtab, dysymtab, identity, encryption, functions, library]
    joined = b"".join(cmds)
    struct.pack_into("<8I", blob, 0, 0xFEEDFACF, 0x100000C, 0, 6, len(cmds), len(joined), 0, 0)
    blob[32:32 + len(joined)] = joined
    # Independent instruction choices: SUB SP,#32 and MOVZ W0,#7. These are
    # original test prologues, not copied game instructions.
    struct.pack_into("<4I", blob, 0x1000, 0xD10083FF, 0xD503201F, 0xD503201F, 0xD65F03C0)
    struct.pack_into("<4I", blob, 0x1020, 0x528000E0, 0xD65F03C0, 0xD503201F, 0xD503201F)
    report = {"framework_uuid": "00010203-0405-0607-0809-0a0b0c0d0e0f", "methods": []}
    for index, (method_name, contract) in enumerate(METHODS.items()):
        declaring, name = method_name.rsplit(".", 1)
        report["methods"].append({"declaring_type": declaring, "name": name, "return_type": contract["return"], "parameters": [{"type": value} for value in contract["parameters"]], "static": contract["static"], "mapping": "codegen_module_token_rid", "native_rva": hex(0x1000 + index * 0x20), "token": hex(0x06000001 + index)})
    return bytes(blob), report


def changed_command(blob, target, mutate):
    result = bytearray(blob)
    cursor = 32
    for _ in range(read(blob, "<I", 16)[0]):
        kind, size = read(blob, "<II", cursor)
        if kind == target:
            mutate(result, cursor)
            return bytes(result)
        cursor += size
    raise AssertionError("Command not found")


class PatcherTests(unittest.TestCase):
    def private_fixture(self):
        original,report=synthetic_image();blob=bytearray(original)
        struct.pack_into('<I',blob,0x1080,0x528000E0)
        original=bytes(blob)
        report['input_pins']={'framework':{'sha256':sha(original)},'metadata':{'sha256':'f'*64}}
        plan={'schema':'ehr.static-class-private-hooks.v1','native_entry_kind':'private_runtime_function_not_managed_method',
              'framework_uuid':report['framework_uuid'],'source_framework_sha256':sha(original),'metadata_sha256':'f'*64,
              'hooks':[{'target':'Owned.Runtime.Function','rva':'0x1080','symbol':'_ehr_owned_private',
                        'abi':'const void *(int32_t index)','hidden_MethodInfo_argument':False,
                        'prologue_sha256':sha(original[0x1080:0x1100])}]}
        return original,report,plan

    def test_private_entries_remain_distinct_from_managed_metadata(self):
        original,report,plan=self.private_fixture()
        patched,manifest=transform(original,report,['PlayerControl.MurderPlayer'],'@executable_path/Frameworks/Hooks.dylib',private_entries=plan)
        self.assertNotEqual(original,patched)
        private=manifest['hooks'][1]
        self.assertIsNone(private['metadata_token'])
        self.assertEqual(private['signature']['native_entry_kind'],'private_runtime_function_not_managed_method')
        self.assertFalse(private['signature']['hidden_MethodInfo_argument'])
        self.assertNotIn('return',private['signature'])

    def test_private_entry_pin_mismatches_fail_closed(self):
        for key in ('framework_uuid','source_framework_sha256','metadata_sha256'):
            with self.subTest(key=key):
                original,report,plan=self.private_fixture();plan[key]='0'*64
                with self.assertRaisesRegex(PatchError,'input pin mismatch'):
                    transform(original,report,['PlayerControl.MurderPlayer'],'@executable_path/Frameworks/Hooks.dylib',private_entries=plan)

    def test_private_entry_prologue_is_required_and_checked(self):
        for value in (None,'0'*64,'invalid'):
            with self.subTest(value=value):
                original,report,plan=self.private_fixture();plan['hooks'][0]['prologue_sha256']=value
                with self.assertRaisesRegex(PatchError,'prologue'):
                    transform(original,report,['PlayerControl.MurderPlayer'],'@executable_path/Frameworks/Hooks.dylib',private_entries=plan)

    def test_private_entry_alias_and_hidden_context_are_rejected(self):
        original,report,plan=self.private_fixture();plan['hooks']*=2
        with self.assertRaisesRegex(PatchError,'Duplicate'):
            transform(original,report,['PlayerControl.MurderPlayer'],'@executable_path/Frameworks/Hooks.dylib',private_entries=plan)
        original,report,plan=self.private_fixture();plan['hooks'][0]['hidden_MethodInfo_argument']=True
        with self.assertRaisesRegex(PatchError,'entry ABI'):
            transform(original,report,['PlayerControl.MurderPlayer'],'@executable_path/Frameworks/Hooks.dylib',private_entries=plan)

    def test_private_entry_cannot_share_an_existing_managed_entry(self):
        original,report,plan=self.private_fixture();plan['hooks'][0]['rva']='0x1000'
        plan['hooks'][0]['prologue_sha256']=sha(original[0x1000:0x1080])
        with self.assertRaisesRegex(PatchError,'share a native entry'):
            transform(original,report,['PlayerControl.MurderPlayer'],'@executable_path/Frameworks/Hooks.dylib',private_entries=plan)

    def test_large_explicit_hook_set_uses_sized_code_and_data_segments(self):
        original, report = synthetic_image()
        blob = bytearray(changed_command(original, 0x19, lambda b, c: struct.pack_into("<Q", b, c + 72 + 40, 0x3000)))
        report = copy.deepcopy(report)
        extra, keys = {}, []
        for index in range(300):
            key = "Fixture.Call" + str(index)
            keys.append(key)
            extra[key] = {"declaring_type": "Fixture", "name": "Call" + str(index),
                          "return": "System.Int32", "parameters": [], "static": True,
                          "symbol": "_ehr_fixture_" + str(index)}
            offset = 0x1000 + index * 16
            struct.pack_into("<I", blob, offset, 0x52800000 | (index << 5))
            report["methods"].append({"declaring_type": "Fixture", "name": "Call" + str(index),
                "return_type": "System.Int32", "parameters": [], "static": True,
                "mapping": "codegen_module_token_rid", "native_rva": hex(offset), "token": hex(0x06001000 + index)})
        patched, manifest = transform(bytes(blob), report, keys, "@executable_path/Frameworks/Hooks.dylib", extra)
        self.assertEqual(len(manifest["hooks"]), 300)
        self.assertEqual(manifest["layout"]["text_bytes"], PAGE * 2)
        self.assertEqual(manifest["layout"]["data_bytes"], PAGE)
        image = Image(patched, allow_instrumented=True)
        self.assertEqual(image.linkedit.fileoff, 0x8000 + PAGE * 3)
        for hook in (manifest["hooks"][0], manifest["hooks"][-1]):
            trampoline = image.va_to_file(int(hook["trampoline_preferred_va"], 16))
            original_entry = int(hook["method_file_offset"], 16)
            self.assertEqual(read(patched, "<I", trampoline), read(blob, "<I", original_entry))
        self.assertEqual(bytes(blob[0x8000:]), patched[image.linkedit.fileoff:len(blob) + PAGE * 3])

    def test_shared_native_entry_requires_combined_dispatch(self):
        original, report = synthetic_image()
        report["methods"][1]["native_rva"] = report["methods"][0]["native_rva"]
        with self.assertRaisesRegex(PatchError, "share a native entry"):
            transform(original, report, list(METHODS), "@executable_path/Frameworks/Hooks.dylib")

    def test_exact_overload_contract_selects_one_signature(self):
        _, report = synthetic_image()
        overload = copy.deepcopy(report["methods"][0])
        overload["parameters"] = []
        report["methods"].append(overload)
        selected = select_hooks(report, ["PlayerControl.MurderPlayer"])
        self.assertEqual(selected[0]["signature"]["parameters"], ["PlayerControl", "MurderResultFlags"])

    def test_extra_contracts_cannot_replace_defaults_or_omit_native_shape(self):
        _, report = synthetic_image()
        for extra in ({"Constants.GetBroadcastVersion": METHODS["Constants.GetBroadcastVersion"]},
                      {"Extra": {"static": 1}}, {"Extra": {"static": True}}):
            with self.assertRaises(PatchError):
                select_hooks(report, ["Extra"], extra)

    def test_two_hooks_preserve_mappings_code_and_original_linkedit(self):
        original, report = synthetic_image()
        snapshot = bytes(original)
        patched, manifest = transform(original, report, list(METHODS), "@executable_path/Frameworks/EHRNativeHooks.dylib")
        self.assertEqual(original, snapshot)
        self.assertEqual(len(manifest["hooks"]), 2)
        old, new = Image(original), Image(patched, allow_instrumented=True)
        self.assertEqual(new.linkedit.fileoff, old.linkedit.fileoff + 2 * PAGE)
        self.assertEqual(new.linkedit.vmaddr, old.linkedit.vmaddr + 2 * PAGE)
        self.assertEqual([s.name for s in new.segments], ["__TEXT", "__DATA", "__EHR_TEXT", "__EHR_DATA", "__LINKEDIT"])
        self.assertEqual(patched[old.linkedit.fileoff + 2 * PAGE:len(original) + 2 * PAGE], original[old.linkedit.fileoff:])
        self.assertEqual(manifest["output_sha256"], hashlib.sha256(patched).hexdigest())
        for hook in manifest["hooks"]:
            source = int(hook["original_preferred_va"], 16)
            stub = int(hook["stub_preferred_va"], 16)
            entryword = read(patched, "<I", source)[0]
            imm = entryword & 0x3FFFFFF
            if imm & 0x2000000:
                imm -= 0x4000000
            self.assertEqual(source + imm * 4, stub)
            tramp = int(hook["trampoline_preferred_va"], 16)
            copied = read(patched, "<I", new.va_to_file(tramp))[0]
            self.assertEqual(copied, read(original, "<I", source)[0])
            self.assertTrue(manifest["invariants"]["encryption_commands_unchanged"])

    def test_all_known_file_offset_fields_relocated(self):
        original, report = synthetic_image()
        patched, _ = transform(original, report, ["PlayerControl.MurderPlayer"], "@executable_path/Frameworks/Hooks.dylib")
        new = Image(patched, allow_instrumented=True)
        self.assertEqual(read(new.command((2,)), "<I", 8)[0], 0x8040 + 2 * PAGE)
        self.assertEqual(read(new.command((2,)), "<I", 16)[0], 0x8050 + 2 * PAGE)
        self.assertEqual(read(new.command((0xB,)), "<I", 8 + 12 * 4)[0], 0x8060 + 2 * PAGE)
        self.assertEqual(read(new.command((0x26,)), "<I", 8)[0], 0x8070 + 2 * PAGE)
        text = next(s for s in new.segments if s.name == "__TEXT")
        self.assertEqual(read(new.commands[text.command_index], "<I", 72 + 56)[0], 0x8080 + 2 * PAGE)

    def test_got_stub_decodes_to_correct_target(self):
        original, report = synthetic_image()
        patched, manifest = transform(original, report, list(METHODS), "@executable_path/Frameworks/Hooks.dylib")
        image = Image(patched, allow_instrumented=True)
        for hook in manifest["hooks"]:
            stub = int(hook["stub_preferred_va"], 16)
            adrp, ldr, br = read(patched, "<3I", image.va_to_file(stub, 12))
            immediate = ((adrp >> 5) & 0x7FFFF) << 2 | ((adrp >> 29) & 3)
            if immediate & (1 << 20):
                immediate -= 1 << 21
            page = (stub & ~4095) + immediate * 4096
            got = page + ((ldr >> 10) & 4095) * 8
            self.assertEqual(got, int(hook["got_preferred_va"], 16))
            self.assertEqual(br, 0xD61F0200)

    def test_new_segments_have_sections_covering_code_and_bound_pointers(self):
        original, report = synthetic_image()
        patched, manifest = transform(original, report, list(METHODS), "@executable_path/Frameworks/Hooks.dylib")
        old, new = Image(original), Image(patched, allow_instrumented=True)
        # New sections occur only after ALL original section-bearing segments,
        # so existing one-based section numbers retain their meaning.
        old_section_names = []
        for segment in old.segments:
            raw = old.commands[segment.command_index]
            old_section_names.extend(bytes(raw[72 + i * 80:104 + i * 80]) for i in range(segment.nsects))
        new_section_names = []
        for segment in new.segments:
            raw = new.commands[segment.command_index]
            new_section_names.extend(bytes(raw[72 + i * 80:104 + i * 80]) for i in range(segment.nsects))
        self.assertEqual(new_section_names[:len(old_section_names)], old_section_names)
        for name, field in (("__EHR_TEXT", "stub_preferred_va"), ("__EHR_DATA", "got_preferred_va")):
            segment = next(s for s in new.segments if s.name == name)
            self.assertEqual(segment.nsects, 1)
            raw = new.commands[segment.command_index]
            address, size, offset, alignment, relocation, nreloc, flags = read(raw, "<QQIIIII", 72 + 32)
            self.assertEqual((address, size, offset), (segment.vmaddr, PAGE, segment.fileoff))
            self.assertEqual((relocation, nreloc), (0, 0))
            self.assertEqual(flags & 255, 0)  # S_REGULAR, no indirect table
            for hook in manifest["hooks"]:
                value = int(hook[field], 16)
                self.assertTrue(address <= value < address + size)

    def test_rebase_and_bind_segment_indices_are_checked(self):
        for kind, data in (("rebase", b"\x22\x00\x00"), ("normal", b"\x72\x00\x00")):
            with self.assertRaises(PatchError):
                validate_program(data, kind, 2)
        self.assertEqual(validate_program(b"\x11\x21\x00\x51", "rebase", 2), b"\x11\x21\x00\x51")

    def test_bind_tail_threaded_and_truncation_rejected(self):
        for data in (b"\x00\x11", b"\xD0\x00", b"\x20\x80", b"\x40unterminated"):
            with self.assertRaises(PatchError):
                validate_program(data, "normal", 2)
        self.assertEqual(validate_program(b"\x11\x00\x11\x00", "lazy", 2), b"\x11")

    def test_pc_relative_and_control_flow_first_words_rejected(self):
        for word in (0x90000000, 0x14000000, 0xD65F03C0, 0xD503233F, 0x10000000):
            with self.assertRaises(PatchError):
                validate_relocated_instruction(word)
        self.assertIn("SUB", validate_relocated_instruction(0xD10083FF))
        self.assertIn("MOVZ", validate_relocated_instruction(0x528000E0))

    def test_branch_range_rejected_and_negative_branch_supported(self):
        with self.assertRaises(PatchError):
            branch(0, 1 << 27)
        with self.assertRaises(PatchError):
            branch(0, 3)
        self.assertEqual(branch(16, 0), 0x17FFFFFC)

    def test_unknown_command_encryption_chained_fixups_rejected(self):
        original, _ = synthetic_image()
        unknown = changed_command(original, 0x26, lambda b, c: struct.pack_into("<I", b, c, 0x31))
        encrypted = changed_command(original, 0x2C, lambda b, c: struct.pack_into("<I", b, c + 16, 1))
        chained = changed_command(original, 0x26, lambda b, c: struct.pack_into("<I", b, c, 0x80000034))
        for data in (unknown, encrypted, chained):
            with self.assertRaises(PatchError):
                Image(data)

    def test_uuid_signature_contract_and_header_padding_fail_closed(self):
        original, report = synthetic_image()
        wrong = copy.deepcopy(report)
        wrong["framework_uuid"] = "not-this-build"
        with self.assertRaises(PatchError):
            transform(original, wrong, ["PlayerControl.MurderPlayer"], "@executable_path/Frameworks/Hooks.dylib")
        wrong = copy.deepcopy(report)
        wrong["methods"][0]["return_type"] = "System.Boolean"
        with self.assertRaises(PatchError):
            select_hooks(wrong, ["PlayerControl.MurderPlayer"])
        dirty = bytearray(original)
        headerend = 32 + Image(original).sizeofcmds
        dirty[headerend] = 1
        with self.assertRaises(PatchError):
            transform(dirty, report, ["PlayerControl.MurderPlayer"], "@executable_path/Frameworks/Hooks.dylib")

    def test_uleb_roundtrip_and_overflow(self):
        for value in (0, 15, 128, 16384, (1 << 64) - 1):
            encoded = uleb(value)
            self.assertEqual(decode_leb(encoded, 0), (value, len(encoded)))
        with self.assertRaises(PatchError):
            decode_leb(b"\xFF" * 10 + b"\x00", 0)


if __name__ == "__main__":
    unittest.main()
