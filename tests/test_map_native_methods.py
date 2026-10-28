from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from map_native_methods import MachO, Metadata, ParseError, TypeNames, build_report, find_module


def fixture_metadata():
    names = ["", "Assembly-CSharp.dll", "PlayerControl", "Constants", "Empty", "MurderPlayer", "GetBroadcastVersion", "target", "resultFlags"]
    pool, offsets = bytearray(), {}
    for name in names:
        offsets[name] = len(pool)
        pool.extend(name.encode() + b"\0")
    data, pairs = bytearray(256), [(256, 0)] * 31

    def table(index, payload):
        pairs[index] = len(data), len(payload)
        data.extend(payload)

    table(2, pool)
    rows = []
    for i, (name, start, count) in enumerate((("PlayerControl", 0, 1), ("Constants", 1, 1), ("Empty", 0xFFFFFFFF, 0))):
        row = [0] * 26
        row[0], row[1], row[9], row[16], row[25] = offsets[name], offsets[""], start, count, 0x02000001 + i
        rows.append(struct.pack("<16I8H2I", *row))
    table(19, b"".join(rows))
    methods = struct.pack("<IiiiiiI4H", offsets["MurderPlayer"], 0, 3, 0, 0, -1, 0x06000001, 0x86, 0, 65535, 2)
    methods += struct.pack("<IiiiiiI4H", offsets["GetBroadcastVersion"], 1, 3, 0, 2, -1, 0x06000002, 0x96, 0, 65535, 0)
    table(5, methods)
    table(10, struct.pack("<III", offsets["target"], 0x08000001, 0) + struct.pack("<III", offsets["resultFlags"], 0x08000002, 1))
    table(20, struct.pack("<10I", offsets["Assembly-CSharp.dll"], 0, 0, 3, 0, 0, 0xFFFFFFFF, 0x20000001, 0, 0))
    struct.pack_into("<II", data, 0, 0xFAB11BAF, 31)
    for i, pair in enumerate(pairs):
        struct.pack_into("<II", data, 8 + i * 8, *pair)
    return bytes(data)


def fixture_native(cryptid=0, chained=False):
    data = bytearray(0x4000)
    commands = []
    for name, va, size, protection in ((b"__TEXT", 0, 0x2000, 5), (b"__DATA_CONST", 0x2000, 0x1000, 3), (b"__DATA", 0x3000, 0x1000, 3)):
        commands.append(struct.pack("<II16sQQQQiiII", 0x19, 72, name, va, size, va, size, 7, protection, 0, 0))
    commands.append(struct.pack("<II16s", 0x1B, 24, bytes(range(16))))
    commands.append(struct.pack("<6I", 0x80000034 if chained else 0x2C, 24, 0x1000, 0x100, cryptid, 0))
    strings = b"\0_il2cpp_runtime_invoke\0_PlayerControl_MurderPlayer\0"
    commands.append(struct.pack("<6I", 2, 24, 0x3800, 2, 0x3900, len(strings)))
    blob = b"".join(commands)
    struct.pack_into("<8I", data, 0, 0xFEEDFACF, 0x100000C, 0, 6, len(commands), len(blob), 0, 0)
    data[32:32 + len(blob)] = blob
    data[0x1800:0x1814] = b"Assembly-CSharp.dll\0"
    struct.pack_into("<3Q", data, 0x2100, 0x1800, 2, 0x3200)
    struct.pack_into("<Q", data, 0x3100, 0x2100)
    struct.pack_into("<2Q", data, 0x3200, 0x1000, 0x1010)
    struct.pack_into("<4Q", data, 0x3300, 0x3400, 0x3410, 0x3420, 0x3430)
    for address, value, kind in ((0x3400, 0, 18), (0x3410, 0, 9), (0x3420, 0, 2), (0x3430, 0, 8)):
        struct.pack_into("<QI", data, address, value, kind << 16)
    data[0x3900:0x3900 + len(strings)] = strings
    struct.pack_into("<IBBHQ", data, 0x3800, 1, 15, 1, 0, 0x1100)
    struct.pack_into("<IBBHQ", data, 0x3810, len(b"\0_il2cpp_runtime_invoke\0"), 15, 1, 0, 0x1000)
    return bytes(data)


class SymbolMapTests(unittest.TestCase):
    def test_metadata31_method_stride_and_empty_type_sentinel(self):
        metadata = Metadata(fixture_metadata())
        self.assertEqual(list(metadata.methods_for_type(2)), [])
        first = list(metadata.methods_for_type(0))[0][1]
        self.assertEqual(first[6], 0x06000001)
        self.assertEqual(first[10], 2)
        self.assertEqual(metadata.image_method_count(metadata.images[0]), 2)

    def test_token_rid_maps_to_existing_code_pointer(self):
        report = build_report(MachO(fixture_native()), Metadata(fixture_metadata()))
        murder = next(m for m in report["methods"] if m["name"] == "MurderPlayer")
        broadcast = next(m for m in report["methods"] if m["name"] == "GetBroadcastVersion")
        self.assertEqual(murder["native_rva"], "0x1000")
        self.assertEqual(broadcast["native_rva"], "0x1010")
        self.assertTrue(broadcast["static"])
        self.assertEqual(report["symtab"]["relevant_method_or_registration_symbols_retained"], 1)
        self.assertFalse(report["native_hooks_installed"])

    def test_types_resolve_via_unique_native_type_table_without_runtime(self):
        names = TypeNames(MachO(fixture_native()), Metadata(fixture_metadata()), {"types": 0x3300, "types_count": 4})
        self.assertEqual(names.at_index(0), "PlayerControl")
        self.assertEqual(names.at_index(1), "System.UInt32")
        self.assertEqual(names.at_index(2), "System.Boolean")
        self.assertEqual(names.at_index(3), "System.Int32")

    def test_encrypted_or_chained_images_rejected(self):
        for data in (fixture_native(cryptid=1), fixture_native(chained=True)):
            with self.assertRaises(ParseError):
                MachO(data)

    def test_non_executable_method_pointer_rejected(self):
        data = bytearray(fixture_native())
        struct.pack_into("<Q", data, 0x3200, 0x3100)
        with self.assertRaises(ParseError):
            find_module(MachO(data), Metadata(fixture_metadata()), "Assembly-CSharp.dll")

    def test_wrong_metadata_version_and_out_of_bounds_rejected(self):
        data = bytearray(fixture_metadata())
        struct.pack_into("<I", data, 4, 29)
        with self.assertRaises(ParseError):
            Metadata(data)
        data = bytearray(fixture_metadata())
        struct.pack_into("<I", data, 8 + 19 * 8, len(data) + 1)
        with self.assertRaises(ParseError):
            Metadata(data)

    def test_cli_pins_inputs_and_never_replaces_existing_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            native, metadata, report = root / "UnityFramework", root / "global-metadata.dat", root / "map.json"
            native.write_bytes(fixture_native())
            metadata.write_bytes(fixture_metadata())
            originals = native.read_bytes(), metadata.read_bytes()
            command = [sys.executable, str(Path(__file__).resolve().parents[1] / "tools/map_native_methods.py"), "--framework", str(native), "--metadata", str(metadata), "--output", str(report)]
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            parsed = json.loads(report.read_text())
            self.assertEqual(parsed["input_pins"]["framework"]["sha256"], hashlib.sha256(originals[0]).hexdigest())
            self.assertEqual((native.read_bytes(), metadata.read_bytes()), originals)
            evidence = report.read_bytes()
            again = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(again.returncode, 2)
            self.assertEqual(report.read_bytes(), evidence)


if __name__ == "__main__":
    unittest.main()
