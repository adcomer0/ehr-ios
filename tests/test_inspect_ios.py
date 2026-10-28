from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
import plistlib
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from inspect_ios import Limits, exit_code, inspect_path, text_report


def command(number, body, endian="<", alignment=8):
    length = 8 + len(body)
    padding = (-length) % alignment
    return struct.pack(endian + "II", number, length + padding) + body + b"\0" * padding


def macho(cpu=0x0100000C, subtype=0, platform=2, encrypted=0, endian="<", bits=64, commands_extra=b"", extra_count=0, legacy=False, filetype=2):
    align = 8 if bits == 64 else 4
    if legacy:
        build = command(0x25, struct.pack(endian + "II", 0x110200, 0x1A0000), endian, align)
    else:
        build = command(0x32, struct.pack(endian + "IIII", platform, 0x110200, 0x1A0000, 0), endian, align)
    identity = command(0x1B, bytes(range(16)), endian, align)
    encryption = command(0x2C if bits == 64 else 0x21, struct.pack(endian + "III", 0, 0, encrypted) + (b"\0" * 4 if bits == 64 else b""), endian, align)
    commands = build + identity + encryption + commands_extra
    magic = 0xFEEDFACF if bits == 64 else 0xFEEDFACE
    values = [magic, cpu, subtype, filetype, 3 + extra_count, len(commands), 0x200000]
    if bits == 64:
        values.append(0)
    return struct.pack(endian + ("I" * len(values)), *values) + commands + b"\0" * 32


def fat(images, endian=">", wide=False):
    record_size = 32 if wide else 20
    offset = 8 + len(images) * record_size
    records, body = [], bytearray()
    for image in images:
        byte_order = "<" if image[:4] in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe") else ">"
        cpu, subtype = struct.unpack_from(byte_order + "II", image, 4)
        values = (cpu, subtype, offset, len(image), 0, 0) if wide else (cpu, subtype, offset, len(image), 0)
        records.append(struct.pack(endian + ("IIQQII" if wide else "IIIII"), *values))
        body.extend(image)
        offset += len(image)
    magic = 0xCAFEBABF if wide else 0xCAFEBABE
    return struct.pack(endian + "II", magic, len(images)) + b"".join(records) + body


def files(main=None, framework=None, metadata=None):
    info = {"CFBundleIdentifier": "example.test.amongus", "CFBundleShortVersionString": "19.0.0", "CFBundleVersion": "1234", "CFBundleExecutable": "Among Us"}
    return {
        "Info.plist": plistlib.dumps(info),
        "Among Us": macho() if main is None else main,
        "Frameworks/UnityFramework.framework/UnityFramework": macho(filetype=6) if framework is None else framework,
        "Data/Managed/Metadata/global-metadata.dat": struct.pack("<II", 0xFAB11BAF, 29) + b"\0" * 64 if metadata is None else metadata,
    }


class InspectorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def app(self, values=None):
        target = self.root / "Among Us.app"
        target.mkdir(exist_ok=True)
        for name, data in (files() if values is None else values).items():
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        return target

    def ipa(self, values=None, extras=(), compression=zipfile.ZIP_DEFLATED):
        target = self.root / "input.ipa"
        with zipfile.ZipFile(target, "w", compression=compression) as archive:
            for name, data in (files() if values is None else values).items():
                archive.writestr("Payload/Among Us.app/" + name, data)
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                for name, data in extras:
                    archive.writestr(name, data)
        return target

    def codes(self, report):
        return {value["code"] for value in report["issues"]}

    def test_device_input_is_only_analysis_candidate_and_unmodified(self):
        app = self.app()
        before = {str(p.relative_to(app)): (p.read_bytes(), p.stat().st_mtime_ns) for p in app.rglob("*") if p.is_file()}
        report = inspect_path(app)
        self.assertEqual(report["readiness"], "candidate")
        self.assertEqual(exit_code(report), 0)
        self.assertFalse(report["playable_port"])
        self.assertEqual(report["game_adapter"], "unimplemented")
        self.assertEqual(report["bundle"]["build"], "1234")
        self.assertEqual(report["metadata"][0]["version"], 29)
        main = next(v for v in report["images"] if v["path"] == "Among Us")
        self.assertEqual(main["sha256"], hashlib.sha256(before["Among Us"][0]).hexdigest())
        self.assertEqual(main["slices"][0]["minimum_os"], "17.2.0")
        self.assertEqual(main["slices"][0]["uuid"], "00010203-0405-0607-0809-0a0b0c0d0e0f")
        after = {str(p.relative_to(app)): (p.read_bytes(), p.stat().st_mtime_ns) for p in app.rglob("*") if p.is_file()}
        self.assertEqual(before, after)

    def test_ipa_matches_bundle_result_and_is_not_extracted(self):
        ipa = self.ipa()
        original = ipa.read_bytes()
        report = inspect_path(ipa)
        self.assertEqual(report["readiness"], "candidate")
        self.assertEqual(report["input_kind"], "ipa")
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ["input.ipa"])
        self.assertEqual(ipa.read_bytes(), original)

    def test_encrypted_embedded_framework_blocks_even_when_main_is_clear(self):
        report = inspect_path(self.app(files(framework=macho(encrypted=1, filetype=6))))
        self.assertEqual(report["readiness"], "blocked")
        self.assertEqual(exit_code(report), 2)
        encrypted = next(v for v in report["issues"] if v["code"] == "encrypted_image")
        self.assertIn("UnityFramework", encrypted["path"])

    def test_encrypted_main_records_range_without_changing_flag(self):
        data = bytearray(macho(encrypted=1))
        encryption = data.index(struct.pack("<II", 0x2C, 24))
        struct.pack_into("<II", data, encryption + 8, len(data) - 16, 16)
        app = self.app(files(main=bytes(data)))
        report = inspect_path(app)
        image = next(v for v in report["images"] if v["path"] == "Among Us")
        self.assertEqual(image["slices"][0]["encryption"][0]["cryptid"], 1)
        self.assertEqual(image["slices"][0]["encryption"][0]["size"], 16)
        self.assertEqual((app / "Among Us").read_bytes(), bytes(data))

    def test_fat32_and_fat64_both_endiannesses(self):
        for wide in (False, True):
            for endian in ("<", ">"):
                with self.subTest(wide=wide, endian=endian):
                    data = fat([macho(cpu=12, bits=32), macho()], endian, wide)
                    report = inspect_path(self.app(files(main=data)))
                    self.assertEqual(report["readiness"], "candidate")
                    image = next(v for v in report["images"] if v["path"] == "Among Us")
                    self.assertEqual(len(image["slices"]), 2)
                    self.assertEqual(image["sha256"], hashlib.sha256(data).hexdigest())

    def test_big_endian_thin_header(self):
        report = inspect_path(self.app(files(main=macho(endian=">"))))
        self.assertEqual(report["readiness"], "candidate")
        image = next(v for v in report["images"] if v["path"] == "Among Us")
        self.assertEqual(image["slices"][0]["endianness"], "big")

    def test_simulator_arm64_is_not_device_arm64(self):
        report = inspect_path(self.app(files(main=macho(platform=7))))
        self.assertEqual(report["readiness"], "blocked")
        self.assertIn("missing_device_arm64", self.codes(report))
        self.assertIn("non_device_platform", self.codes(report))

    def test_legacy_x86_iphoneos_command_is_classified_simulator(self):
        report = inspect_path(self.app(files(main=macho(cpu=0x01000007, legacy=True))))
        image = next(v for v in report["images"] if v["path"] == "Among Us")
        self.assertEqual(image["slices"][0]["platform"], "iOS Simulator")
        self.assertEqual(report["readiness"], "blocked")

    def test_non_unity_native_harness_is_blocked(self):
        values = files()
        del values["Frameworks/UnityFramework.framework/UnityFramework"]
        del values["Data/Managed/Metadata/global-metadata.dat"]
        report = inspect_path(self.app(values))
        self.assertEqual(report["readiness"], "blocked")
        self.assertTrue({"missing_unityframework", "missing_metadata"} <= self.codes(report))

    def test_missing_main_invalid(self):
        values = files()
        del values["Among Us"]
        report = inspect_path(self.app(values))
        self.assertEqual(exit_code(report), 3)
        self.assertIn("missing_executable", self.codes(report))

    def test_truncated_load_commands_and_header(self):
        for data in (macho()[:12], macho()[:40]):
            with self.subTest(size=len(data)):
                report = inspect_path(self.app(files(main=data)))
                self.assertEqual(report["readiness"], "invalid")

    def test_invalid_command_count_size_and_alignment(self):
        original = macho()
        for offset, value in ((16, 999999), (20, 0xFFFFFFFF), (36, 0), (36, 7), (36, 0xFFFFFFF8)):
            data = bytearray(original)
            struct.pack_into("<I", data, offset, value)
            with self.subTest(offset=offset, value=value):
                report = inspect_path(self.app(files(main=bytes(data))))
                self.assertEqual(exit_code(report), 3)

    def test_encryption_range_must_be_inside_slice_not_just_fat_file(self):
        data = bytearray(macho(encrypted=1))
        encryption = data.index(struct.pack("<II", 0x2C, 24))
        struct.pack_into("<II", data, encryption + 8, len(data), 1)
        report = inspect_path(self.app(files(main=fat([bytes(data), macho(subtype=2)]))))
        self.assertIn("out_of_bounds", self.codes(report))
        self.assertEqual(exit_code(report), 3)

    def test_fat_bounds_overlap_cpu_mismatch_and_alignment(self):
        original = fat([macho(), macho(subtype=2)])
        cases = [(16, len(original) + 1), (20, len(original) + 1), (16, 0), (8, 7), (24, 32)]
        for offset, value in cases:
            with self.subTest(offset=offset, value=value):
                data = bytearray(original)
                struct.pack_into(">I", data, offset, value)
                report = inspect_path(self.app(files(main=bytes(data))))
                self.assertEqual(exit_code(report), 3)

    def test_segment_and_linkedit_ranges_checked(self):
        segment = command(0x19, struct.pack("<16sQQQQiiII", b"__TEXT", 0, 0x1000, 0xFFFFFF00, 256, 7, 5, 0, 0))
        linkedit = command(0x1D, struct.pack("<II", 0xFFFFFF00, 256))
        for extra in (segment, linkedit):
            report = inspect_path(self.app(files(main=macho(commands_extra=extra, extra_count=1))))
            self.assertIn("out_of_bounds", self.codes(report))
            self.assertEqual(exit_code(report), 3)

    def test_metadata_truncated_and_unrecognized(self):
        report = inspect_path(self.app(files(metadata=b"bad")))
        self.assertEqual(exit_code(report), 3)
        report = inspect_path(self.app(files(metadata=b"x" * 32)))
        self.assertEqual(exit_code(report), 2)
        self.assertIn("unrecognized_metadata", self.codes(report))

    def test_zip_traversal_absolute_backslash_and_control_paths(self):
        for bad in ("../escape", "/absolute", "Payload/../escape", "Payload\\escape", "C:/escape", "Payload/./escape", "Payload//escape", "Payload/line\nfeed"):
            with self.subTest(path=repr(bad)):
                report = inspect_path(self.ipa(extras=[(bad, b"unsafe")]))
                self.assertEqual(exit_code(report), 3)
                self.assertIn("unsafe_path", self.codes(report))

    def test_zip_duplicate_exact_case_and_unicode_paths(self):
        duplicate = "Payload/Among Us.app/Among Us"
        for extras in ([(duplicate, b"again")], [(duplicate.upper(), b"again")], [("x/\u00e9", b"a"), ("x/e\u0301", b"b")]):
            report = inspect_path(self.ipa(extras=extras))
            self.assertEqual(exit_code(report), 3)
            self.assertIn("duplicate_path", self.codes(report))

    def test_zip_escaping_symlink_is_rejected_without_following(self):
        link = zipfile.ZipInfo("Payload/Among Us.app/escape")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        report = inspect_path(self.ipa(extras=[(link, b"../../outside")]))
        self.assertIn("symlink_entry", self.codes(report))
        self.assertEqual(exit_code(report), 3)

    def test_directory_symlink_is_rejected(self):
        app = self.app()
        (app / "escaping").symlink_to(self.root)
        report = inspect_path(app)
        self.assertIn("symlink_entry", self.codes(report))
        self.assertEqual(exit_code(report), 3)

    def test_ambiguous_app_and_malformed_zip(self):
        report = inspect_path(self.ipa(extras=[("Payload/Other.app/Info.plist", plistlib.dumps({}))]))
        self.assertIn("ambiguous_app", self.codes(report))
        target = self.root / "bad.ipa"
        target.write_bytes(b"not a zip")
        self.assertEqual(exit_code(inspect_path(target)), 3)

    def test_zip_preflight_limits_are_applied_before_directory_open(self):
        ipa = self.ipa()
        self.assertIn("entry_limit", self.codes(inspect_path(ipa, Limits(entries=2))))
        self.assertIn("size_limit", self.codes(inspect_path(ipa, Limits(central_directory_bytes=1))))
        self.assertIn("size_limit", self.codes(inspect_path(ipa, Limits(file_bytes=16))))

    def test_zip_actual_directory_count_is_checked_before_zipfile_allocation(self):
        ipa = self.ipa()
        data = bytearray(ipa.read_bytes())
        end = data.rindex(b"PK\x05\x06")
        struct.pack_into("<HH", data, end + 8, 1, 1)
        ipa.write_bytes(data)
        with mock.patch("inspect_ios.zipfile.ZipFile", side_effect=AssertionError("ZipFile must not be allocated")):
            report = inspect_path(ipa)
        self.assertEqual(exit_code(report), 3)
        self.assertIn("invalid_archive", self.codes(report))

    def test_main_must_be_executable_not_dylib(self):
        report = inspect_path(self.app(files(main=macho(filetype=6))))
        self.assertEqual(exit_code(report), 3)
        self.assertIn("invalid_main_type", self.codes(report))

    def test_zip_local_member_bounds_malformed(self):
        ipa = self.ipa(compression=zipfile.ZIP_STORED)
        data = bytearray(ipa.read_bytes())
        central = data.index(b"PK\x01\x02")
        struct.pack_into("<I", data, central + 42, len(data) + 1)
        ipa.write_bytes(data)
        report = inspect_path(ipa)
        self.assertEqual(exit_code(report), 3)
        self.assertIn("out_of_bounds", self.codes(report))

    def test_profiles_and_private_plist_values_never_enter_reports(self):
        private_marker = "PRIVATE-DEVICE-ID-0123456789"
        values = files()
        info = plistlib.loads(values["Info.plist"])
        info["PrivateData"] = private_marker
        values["Info.plist"] = plistlib.dumps(info)
        values["embedded.mobileprovision"] = private_marker.encode()
        report = inspect_path(self.ipa(values))
        self.assertEqual(exit_code(report), 0)
        self.assertNotIn(private_marker, json.dumps(report))
        self.assertNotIn(private_marker, text_report(report))
        self.assertNotIn("embedded.mobileprovision", json.dumps(report))

    def test_cli_json_and_return_codes(self):
        script = Path(__file__).resolve().parents[1] / "tools" / "inspect_ios.py"
        app = self.app()
        process = subprocess.run([sys.executable, str(script), str(app), "--format", "json"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(json.loads(process.stdout)["game_adapter"], "unimplemented")
        missing = subprocess.run([sys.executable, str(script), str(self.root / "missing.app"), "--format", "json"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(missing.returncode, 3)
        self.assertEqual(json.loads(missing.stdout)["readiness"], "invalid")


if __name__ == "__main__":
    unittest.main()
