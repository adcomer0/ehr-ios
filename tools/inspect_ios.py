#!/usr/bin/env python3
"""Read-only, dependency-free inspection of candidate iOS Unity mod inputs.

This is a bounded structural audit, not an installer, decryptor, signature
verifier, game adapter, or playable port. IPA members are never extracted.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import struct
import sys
import unicodedata
import uuid
import zipfile


@dataclass(frozen=True)
class Limits:
    entries: int = 50000
    total_bytes: int = 8 * 1024**3
    file_bytes: int = 1024**3
    archive_bytes: int = 4 * 1024**3
    plist_bytes: int = 2 * 1024**2
    load_command_bytes: int = 16 * 1024**2
    load_commands: int = 16384
    fat_slices: int = 32
    central_directory_bytes: int = 64 * 1024**2


class InspectionError(Exception):
    def __init__(self, code, message, path=None):
        super().__init__(message)
        self.code, self.message, self.path = code, message, path


MAGICS = {
    b"\xce\xfa\xed\xfe": ("thin", "<", False),
    b"\xcf\xfa\xed\xfe": ("thin", "<", True),
    b"\xfe\xed\xfa\xce": ("thin", ">", False),
    b"\xfe\xed\xfa\xcf": ("thin", ">", True),
    b"\xca\xfe\xba\xbe": ("fat", ">", False),
    b"\xbe\xba\xfe\xca": ("fat", "<", False),
    b"\xca\xfe\xba\xbf": ("fat", ">", True),
    b"\xbf\xba\xfe\xca": ("fat", "<", True),
}
PLATFORMS = {
    1: "macOS", 2: "iOS", 3: "tvOS", 4: "watchOS", 5: "bridgeOS",
    6: "Mac Catalyst", 7: "iOS Simulator", 8: "tvOS Simulator",
    9: "watchOS Simulator", 10: "DriverKit", 11: "visionOS",
    12: "visionOS Simulator",
}
LEGACY_PLATFORMS = {0x24: 1, 0x25: 2, 0x2F: 3, 0x30: 4}
ARCHITECTURES = {7: "x86", 0x01000007: "x86_64", 12: "arm", 0x0100000C: "arm64"}
LINKEDIT_COMMANDS = {0x1D, 0x1E, 0x26, 0x29, 0x2B, 0x2E, 0x80000033, 0x80000034}


def checked_range(offset, size, limit, description):
    if offset < 0 or size < 0 or offset > limit or size > limit - offset:
        raise InspectionError("out_of_bounds", description + " is outside its containing file/slice")


def safe_name(raw, directory=False):
    if not raw or "\\" in raw or "\x00" in raw or any(ord(c) < 32 or ord(c) == 127 for c in raw):
        raise InspectionError("unsafe_path", "Archive/bundle contains an unsafe path")
    value = raw[:-1] if directory and raw.endswith("/") else raw
    parts = value.split("/")
    if not value or value.startswith("/") or any(p in ("", ".", "..") for p in parts) or ":" in parts[0]:
        raise InspectionError("unsafe_path", "Archive/bundle contains an absolute or traversing path")
    return value


class Entry:
    def __init__(self, name, size, opener):
        self.name, self.size, self._opener = name, size, opener

    def open(self):
        return self._opener()

    def prefix(self, size):
        with self.open() as stream:
            return stream.read(size)


class Source:
    def __init__(self, path, limits):
        self.path, self.limits, self.entries = path, limits, {}
        self.archive = None
        self.app_prefix = ""
        self.kind = "app" if path.suffix.lower() == ".app" else "ipa"

    def __enter__(self):
        try:
            if self.path.is_symlink():
                raise InspectionError("symlink_input", "Input itself must not be a symbolic link")
            if self.kind == "app":
                self._directory()
            else:
                self._zip()
            return self
        except Exception:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *_):
        if self.archive:
            self.archive.close()
            self.archive = None

    def _directory(self):
        if not self.path.is_dir():
            raise InspectionError("invalid_input", "An .app input must be a directory")
        total, count = 0, 0
        for directory, dirs, files in os.walk(self.path, followlinks=False):
            for name in sorted(dirs + files):
                candidate = Path(directory) / name
                rel = candidate.relative_to(self.path).as_posix()
                safe_name(rel)
                info = candidate.lstat()
                count += 1
                if count > self.limits.entries:
                    raise InspectionError("entry_limit", "Bundle exceeds the entry-count limit")
                if stat.S_ISLNK(info.st_mode):
                    raise InspectionError("symlink_entry", "Symbolic links are unsupported in audited inputs", rel)
                if stat.S_ISDIR(info.st_mode):
                    continue
                if not stat.S_ISREG(info.st_mode):
                    raise InspectionError("non_regular_entry", "Bundle contains a non-regular file", rel)
                total += info.st_size
                self._size_check(info.st_size, total)

                @contextmanager
                def opener(p=candidate, expected=info):
                    fd = os.open(p, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
                    try:
                        actual = os.fstat(fd)
                        if not stat.S_ISREG(actual.st_mode) or (actual.st_dev, actual.st_ino, actual.st_size) != (expected.st_dev, expected.st_ino, expected.st_size):
                            raise InspectionError("input_changed", "Bundle changed during inspection")
                        with os.fdopen(fd, "rb") as stream:
                            fd = None
                            yield stream
                    finally:
                        if fd is not None:
                            os.close(fd)

                self.entries[rel] = Entry(rel, info.st_size, opener)

    def _size_check(self, size, total):
        if size > self.limits.file_bytes or total > self.limits.total_bytes:
            raise InspectionError("size_limit", "Input exceeds configured uncompressed size limits")

    def _zip(self):
        if not self.path.is_file():
            raise InspectionError("invalid_input", "An .ipa input must be a regular file")
        if self.path.stat().st_size > self.limits.archive_bytes:
            raise InspectionError("size_limit", "IPA exceeds the archive-size limit")
        expected_count, central_offset = self._zip_preflight()
        self.archive = zipfile.ZipFile(self.path, "r")
        infos = self.archive.infolist()
        if len(infos) != expected_count:
            raise InspectionError("invalid_archive", "ZIP directory entry count is inconsistent")
        seen, total, app_names, accepted, regions = set(), 0, set(), [], []
        for info in infos:
            raw = info.orig_filename
            name = safe_name(raw, info.is_dir())
            key = unicodedata.normalize("NFC", name).casefold()
            if key in seen:
                raise InspectionError("duplicate_path", "IPA has duplicate or case/Unicode-ambiguous paths", name)
            seen.add(key)
            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode):
                raise InspectionError("symlink_entry", "Symbolic links are unsupported in audited IPAs", name)
            kind = stat.S_IFMT(mode)
            if kind and kind not in (stat.S_IFREG, stat.S_IFDIR):
                raise InspectionError("non_regular_entry", "IPA contains a non-regular entry", name)
            if info.flag_bits & 1:
                raise InspectionError("encrypted_archive", "Password-encrypted ZIP members are unsupported", name)
            if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                raise InspectionError("unsupported_compression", "IPA must use stored or deflated ZIP members", name)
            checked_range(info.header_offset, 30, central_offset, "ZIP local header")
            self.archive.fp.seek(info.header_offset)
            local = self.archive.fp.read(30)
            if len(local) != 30 or local[:4] != b"PK\x03\x04":
                raise InspectionError("invalid_archive", "ZIP local header is invalid", name)
            name_size, extra_size = struct.unpack_from("<HH", local, 26)
            start = info.header_offset + 30 + name_size + extra_size
            checked_range(start, info.compress_size, central_offset, "ZIP compressed member")
            regions.append((info.header_offset, start + info.compress_size))
            if info.is_dir():
                if info.file_size:
                    raise InspectionError("invalid_archive", "A directory member contains file data", name)
                continue
            total += info.file_size
            self._size_check(info.file_size, total)
            parts = name.split("/")
            if len(parts) == 3 and parts[0] == "Payload" and parts[1].endswith(".app") and parts[2] == "Info.plist":
                app_names.add("/".join(parts[:2]) + "/")
            accepted.append((name, info))
        previous_end = 0
        for start, end in sorted(regions):
            if start < previous_end:
                raise InspectionError("invalid_archive", "ZIP local members overlap")
            previous_end = end
        if len(app_names) != 1:
            raise InspectionError("ambiguous_app", "IPA must contain exactly one Payload/*.app/Info.plist")
        self.app_prefix = next(iter(app_names))
        for name, info in accepted:
            if name.startswith(self.app_prefix):
                rel = name[len(self.app_prefix):]

                @contextmanager
                def opener(member=info):
                    with self.archive.open(member, "r") as stream:
                        yield stream

                self.entries[rel] = Entry(rel, info.file_size, opener)

    def _zip_preflight(self):
        """Bound central-directory allocation before stdlib ZipFile reads it."""
        size = self.path.stat().st_size
        with self.path.open("rb") as stream:
            tail_size = min(size, 65535 + 22)
            stream.seek(size - tail_size)
            tail = stream.read(tail_size)
            index = tail.rfind(b"PK\x05\x06")
            if index < 0 or len(tail) - index < 22:
                raise InspectionError("invalid_archive", "ZIP end-of-directory record is missing/truncated")
            _, disk, cd_disk, disk_count, count, cd_size, cd_offset, comment_size = struct.unpack_from("<4s4H2IH", tail, index)
            record_offset = size - tail_size + index
            if record_offset + 22 + comment_size != size or disk != 0 or cd_disk != 0 or disk_count != count:
                raise InspectionError("invalid_archive", "ZIP end record is inconsistent or multi-disk")
            boundary = record_offset
            if count == 0xFFFF or cd_size == 0xFFFFFFFF or cd_offset == 0xFFFFFFFF:
                if record_offset < 20:
                    raise InspectionError("invalid_archive", "ZIP64 locator is missing")
                stream.seek(record_offset - 20)
                locator = stream.read(20)
                signature, disk64, offset64, disks = struct.unpack("<4sIQI", locator)
                if signature != b"PK\x06\x07" or disk64 or disks != 1:
                    raise InspectionError("invalid_archive", "ZIP64 locator is invalid/multi-disk")
                checked_range(offset64, 56, record_offset - 20, "ZIP64 end record")
                stream.seek(offset64)
                record = stream.read(56)
                values = struct.unpack("<4sQ2H2I4Q", record)
                signature64, length64, _, _, disk64, cd_disk64, disk_count64, count64, size64, start64 = values
                if signature64 != b"PK\x06\x06" or length64 < 44 or length64 > 65535 or disk64 or cd_disk64 or disk_count64 != count64:
                    raise InspectionError("invalid_archive", "ZIP64 end record is inconsistent")
                checked_range(offset64, length64 + 12, record_offset - 20, "ZIP64 end record")
                count, cd_size, cd_offset, boundary = count64, size64, start64, offset64
            if count > self.limits.entries:
                raise InspectionError("entry_limit", "IPA exceeds the entry-count limit")
            if cd_size > self.limits.central_directory_bytes:
                raise InspectionError("size_limit", "ZIP central directory exceeds its size limit")
            checked_range(cd_offset, cd_size, boundary, "ZIP central directory")
            if cd_offset + cd_size != boundary:
                raise InspectionError("invalid_archive", "ZIP central directory has an unexpected gap/overlap")
            # The EOCD's declared count can lie. Count bounded central records
            # before ZipFile allocates a ZipInfo for each actual member.
            cursor, actual_count = cd_offset, 0
            while cursor < boundary:
                checked_range(cursor, 46, boundary, "ZIP central record")
                stream.seek(cursor)
                header = stream.read(46)
                if len(header) != 46 or header[:4] != b"PK\x01\x02":
                    raise InspectionError("invalid_archive", "ZIP central record is malformed")
                name_size, extra_size, comment_size = struct.unpack_from("<HHH", header, 28)
                record_size = 46 + name_size + extra_size + comment_size
                checked_range(cursor, record_size, boundary, "ZIP central record")
                cursor += record_size
                actual_count += 1
                if actual_count > self.limits.entries:
                    raise InspectionError("entry_limit", "Actual ZIP directory count exceeds the entry limit")
            if actual_count != count:
                raise InspectionError("invalid_archive", "Declared and actual ZIP directory counts differ")
            return count, cd_offset


class HashingStream:
    """Read an image once, forwards only; skipped bytes also feed its SHA256."""
    def __init__(self, stream, size):
        self.stream, self.size, self.position = stream, size, 0
        self.hash = hashlib.sha256()

    def read(self, count):
        checked_range(self.position, count, self.size, "Read")
        chunks, left = [], count
        while left:
            part = self.stream.read(min(left, 1024 * 1024))
            if not part:
                raise InspectionError("truncated_file", "Input ended before its declared size")
            self.hash.update(part)
            self.position += len(part)
            chunks.append(part)
            left -= len(part)
        return b"".join(chunks)

    def skip_to(self, offset):
        if offset < self.position:
            raise InspectionError("invalid_layout", "Image regions overlap or are not forward-readable")
        checked_range(offset, 0, self.size, "Stream offset")
        while self.position < offset:
            self.read(min(offset - self.position, 1024 * 1024))

    def finish(self):
        self.skip_to(self.size)
        if self.stream.read(1):
            raise InspectionError("input_changed", "Input is larger than its declared size")
        return self.hash.hexdigest()


def version_string(value):
    return "%d.%d.%d" % (value >> 16, (value >> 8) & 255, value & 255)


def parse_slice(reader, offset, size, limits, initial_magic=None):
    checked_range(offset, size, reader.size, "Mach-O slice")
    if size < 28:
        raise InspectionError("truncated_header", "Mach-O slice is smaller than its header")
    magic = initial_magic if initial_magic is not None else reader.read(4)
    shape = MAGICS.get(magic)
    if shape is None or shape[0] != "thin":
        raise InspectionError("invalid_slice_magic", "Fat member is not a thin Mach-O image")
    _, endian, bits64 = shape
    header_size = 32 if bits64 else 28
    if size < header_size:
        raise InspectionError("truncated_header", "Mach-O header is truncated")
    values = struct.unpack(endian + ("7I" if bits64 else "6I"), reader.read(header_size - 4))
    cpu, subtype, file_type, ncmds, command_size, flags = values[:6]
    if ncmds > limits.load_commands or command_size > limits.load_command_bytes:
        raise InspectionError("command_limit", "Mach-O load-command limits exceeded")
    checked_range(header_size, command_size, size, "Load-command table")
    if ncmds > command_size // 8:
        raise InspectionError("invalid_commands", "Command count cannot fit the load-command table")
    commands = reader.read(command_size)
    image = {
        "offset": offset, "size": size, "bits": 64 if bits64 else 32,
        "endianness": "little" if endian == "<" else "big",
        "architecture": ARCHITECTURES.get(cpu, "unknown:0x%x" % cpu),
        "cpu_type": cpu, "cpu_subtype": subtype,
        "file_type": file_type, "uuid": None,
        "platform": None, "platform_id": None, "minimum_os": None,
        "encryption": [], "code_signature": "absent",
        "aslr_pie": bool(flags & 0x200000), "chained_fixups": False,
    }
    cursor, platform_records = 0, []
    for _ in range(ncmds):
        if cursor + 8 > len(commands):
            raise InspectionError("truncated_commands", "Mach-O load command is truncated")
        command, length = struct.unpack_from(endian + "II", commands, cursor)
        alignment = 8 if bits64 else 4
        if length < 8 or length % alignment or length > len(commands) - cursor:
            raise InspectionError("invalid_command_size", "Mach-O load command has invalid size/alignment")
        data = commands[cursor:cursor + length]

        def require(minimum):
            if length < minimum:
                raise InspectionError("truncated_command", "A recognized Mach-O load command is too short")

        if command in (0x21, 0x2C):
            require(24 if command == 0x2C else 20)
            cryptoff, cryptsize, cryptid = struct.unpack_from(endian + "III", data, 8)
            checked_range(cryptoff, cryptsize, size, "Encrypted range")
            image["encryption"].append({"command": "LC_ENCRYPTION_INFO_64" if command == 0x2C else "LC_ENCRYPTION_INFO", "cryptid": cryptid, "offset": cryptoff, "size": cryptsize})
        elif command == 0x1B:
            require(24)
            if image["uuid"] is not None:
                raise InspectionError("duplicate_uuid", "Image contains more than one UUID command")
            image["uuid"] = str(uuid.UUID(bytes=data[8:24]))
        elif command == 0x32:
            require(24)
            platform, minimum, sdk, tools = struct.unpack_from(endian + "IIII", data, 8)
            if tools > (length - 24) // 8:
                raise InspectionError("invalid_build_version", "Build-version tools exceed their command")
            platform_records.append((platform, minimum, sdk))
        elif command in LEGACY_PLATFORMS:
            require(16)
            minimum, sdk = struct.unpack_from(endian + "II", data, 8)
            # Legacy iPhoneOS minimum-version commands were also used by the
            # x86 simulator; never infer device status from this command alone.
            platform = LEGACY_PLATFORMS[command]
            if platform == 2 and cpu in (7, 0x01000007):
                platform = 7
            platform_records.append((platform, minimum, sdk))
        elif command in LINKEDIT_COMMANDS:
            require(16)
            dataoff, datasize = struct.unpack_from(endian + "II", data, 8)
            checked_range(dataoff, datasize, size, "Link-edit data")
            if command == 0x1D:
                image["code_signature"] = "present_unverified" if datasize else "empty_unverified"
            if command == 0x80000034:
                image["chained_fixups"] = True
        elif command in (1, 0x19):
            segment64 = command == 0x19
            base, section_length = (72, 80) if segment64 else (56, 68)
            require(base)
            fmt = endian + ("16sQQQQiiII" if segment64 else "16sIIIIiiII")
            segment = struct.unpack_from(fmt, data, 8)
            fileoff, filesize, nsects = segment[3], segment[4], segment[7]
            checked_range(fileoff, filesize, size, "Segment file range")
            if nsects > (length - base) // section_length:
                raise InspectionError("invalid_sections", "Section count exceeds its segment command")
            for index in range(nsects):
                section_offset = base + section_length * index
                if segment64:
                    _, _, _, section_size, file_offset, _, reloc_offset, nreloc, section_flags, _, _, _ = struct.unpack_from(endian + "16s16sQQIIIIIIII", data, section_offset)
                else:
                    _, _, _, section_size, file_offset, _, reloc_offset, nreloc, section_flags, _, _ = struct.unpack_from(endian + "16s16sIIIIIIIII", data, section_offset)
                if section_flags & 255 not in (1, 0xC, 0x12):
                    checked_range(file_offset, section_size, size, "Section file range")
                checked_range(reloc_offset, nreloc * 8, size, "Section relocation range")
        elif command == 2:
            require(24)
            symoff, nsyms, stroff, strsize = struct.unpack_from(endian + "IIII", data, 8)
            checked_range(symoff, nsyms * (16 if bits64 else 12), size, "Symbol table")
            checked_range(stroff, strsize, size, "String table")
        cursor += length
    if cursor != len(commands):
        raise InspectionError("unused_command_bytes", "Load commands do not exactly cover sizeofcmds")
    if platform_records:
        if len(set(platform_records)) != 1:
            raise InspectionError("conflicting_platforms", "Image has conflicting platform/version commands")
        platform, minimum, _ = platform_records[0]
        image["platform_id"] = platform
        image["platform"] = PLATFORMS.get(platform, "unknown:%d" % platform)
        image["minimum_os"] = version_string(minimum)
    return image


def parse_image(entry, limits):
    with entry.open() as stream:
        reader = HashingStream(stream, entry.size)
        magic = reader.read(4)
        shape = MAGICS.get(magic)
        if shape is None:
            raise InspectionError("invalid_magic", "Executable is not a recognized Mach-O image", entry.name)
        layout, endian, fat64 = shape
        slices = []
        if layout == "thin":
            slices.append(parse_slice(reader, 0, entry.size, limits, magic))
        else:
            count = struct.unpack(endian + "I", reader.read(4))[0]
            if count < 1 or count > limits.fat_slices:
                raise InspectionError("fat_slice_limit", "Fat Mach-O has invalid/excessive slice count")
            record_size = 32 if fat64 else 20
            checked_range(8, count * record_size, entry.size, "Fat architecture table")
            table = reader.read(count * record_size)
            members = []
            for index in range(count):
                values = struct.unpack_from(endian + ("IIQQII" if fat64 else "IIIII"), table, index * record_size)
                cpu, subtype, offset, size, align = values[:5]
                if fat64 and values[5] != 0:
                    raise InspectionError("invalid_fat_reserved", "Fat64 reserved field is nonzero")
                if align > 31 or offset % (1 << align):
                    raise InspectionError("invalid_fat_alignment", "Fat slice offset has invalid alignment")
                checked_range(offset, size, entry.size, "Fat member")
                members.append((offset, size, cpu, subtype))
            previous_end = 8 + len(table)
            for offset, size, cpu, subtype in sorted(members):
                if offset < previous_end:
                    raise InspectionError("overlapping_slices", "Fat slices overlap the table or each other")
                previous_end = offset + size
                reader.skip_to(offset)
                member = parse_slice(reader, offset, size, limits)
                if (member["cpu_type"], member["cpu_subtype"]) != (cpu, subtype):
                    raise InspectionError("fat_cpu_mismatch", "Fat table CPU fields do not match the member header")
                slices.append(member)
        return {"path": entry.name, "size": entry.size, "sha256": reader.finish(), "layout": layout, "slices": slices}


def base_report():
    return {
        "schema_version": 1, "purpose": "analysis-input-readiness",
        "readiness": "invalid", "playable_port": False,
        "game_adapter": "unimplemented", "input_kind": None,
        "bundle": None, "images": [], "metadata": [], "issues": [],
        "limitations": [
            "A candidate result only permits further analysis; it does not establish an installable or playable mod.",
            "Code signatures, provisioning, symbol bindings and game-hook coverage are not validated.",
            "Only inspected Mach-O headers/ranges and IL2CPP metadata headers are validated; asset integrity and metadata tables are not.",
            "No decryption, extraction, signing, installation or modification is performed.",
        ],
    }


def issue(report, code, message, path=None, severity="blocker"):
    value = {"severity": severity, "code": code, "message": message}
    if path:
        value["path"] = path
    report["issues"].append(value)


def inspect_path(path, limits=None):
    limits = limits or Limits()
    path = Path(path)
    report = base_report()
    if path.suffix.lower() not in (".app", ".ipa"):
        issue(report, "invalid_input", "Input must be an .app directory or .ipa file", severity="error")
        return report
    try:
        with Source(path, limits) as source:
            report["input_kind"] = source.kind
            plist_entry = source.entries.get("Info.plist")
            if plist_entry is None or plist_entry.size > limits.plist_bytes:
                raise InspectionError("invalid_plist", "Main Info.plist is missing or exceeds the size limit")
            with plist_entry.open() as stream:
                data = stream.read(limits.plist_bytes + 1)
            try:
                info = plistlib.loads(data)
            except Exception:
                raise InspectionError("invalid_plist", "Main Info.plist cannot be parsed")
            if not isinstance(info, dict):
                raise InspectionError("invalid_plist", "Main Info.plist must contain a dictionary")
            fields = {}
            for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "CFBundleExecutable"):
                value = info.get(key)
                if not isinstance(value, str) or not value or len(value) > 512 or any(ord(c) < 32 for c in value):
                    raise InspectionError("invalid_plist_field", "Required bundle identity/version/executable fields must be nonempty strings")
                fields[key] = value
            executable = fields["CFBundleExecutable"]
            if "/" in executable or "\\" in executable or executable in (".", ".."):
                raise InspectionError("unsafe_executable", "CFBundleExecutable must be a single filename")
            report["bundle"] = {"identifier": fields["CFBundleIdentifier"], "version": fields["CFBundleShortVersionString"], "build": fields["CFBundleVersion"], "executable": executable}
            main_entry = source.entries.get(executable)
            if main_entry is None:
                raise InspectionError("missing_executable", "Main bundle executable is missing")
            for name, entry in sorted(source.entries.items()):
                # Provisioning profiles may contain device identifiers; do not
                # read them, and never copy their content into a report.
                if name.lower().endswith((".mobileprovision", ".provisionprofile")):
                    continue
                prefix = entry.prefix(4)
                if prefix in MAGICS:
                    try:
                        report["images"].append(parse_image(entry, limits))
                    except InspectionError as exc:
                        issue(report, exc.code, exc.message, name, "error")
                elif name == executable:
                    issue(report, "invalid_main_image", "Main executable is not a recognized Mach-O image", name, "error")
                if name.split("/")[-1] == "global-metadata.dat":
                    if entry.size < 8:
                        issue(report, "truncated_metadata", "IL2CPP metadata header is shorter than 8 bytes", name, "error")
                        continue
                    with entry.open() as stream:
                        reader = HashingStream(stream, entry.size)
                        header = reader.read(8)
                        magic, version = struct.unpack("<II", header)
                        metadata = {"path": name, "size": entry.size, "sha256": reader.finish(), "recognized_header": magic == 0xFAB11BAF, "version": version if magic == 0xFAB11BAF else None, "table_validation": "not_performed"}
                        report["metadata"].append(metadata)
                    if not metadata["recognized_header"] or version == 0:
                        issue(report, "unrecognized_metadata", "Metadata does not have a recognized IL2CPP header/version", name)
            if not report["metadata"]:
                issue(report, "missing_metadata", "No readable global-metadata.dat was found")
            if not any("UnityFramework.framework/" in value["path"] for value in report["images"]):
                issue(report, "missing_unityframework", "No Mach-O image within UnityFramework.framework was found; older/custom Unity layouts require manual review")
            for image in report["images"]:
                if image["path"] == executable and any(s["file_type"] != 2 for s in image["slices"]):
                    issue(report, "invalid_main_type", "Main executable is not MH_EXECUTE in every slice", image["path"], "error")
                if not any(s["architecture"] == "arm64" and s["platform_id"] == 2 for s in image["slices"]):
                    issue(report, "missing_device_arm64", "Image lacks a verified arm64 iOS-device slice", image["path"])
                if any(s["platform_id"] != 2 for s in image["slices"]):
                    issue(report, "non_device_platform", "An image slice has an absent or non-iOS-device platform", image["path"])
                if any(s["file_type"] not in (2, 6, 8) for s in image["slices"]):
                    issue(report, "unsupported_image_type", "Image is not an executable, dynamic library or loadable bundle", image["path"])
                if any(e["cryptid"] != 0 for s in image["slices"] for e in s["encryption"]):
                    issue(report, "encrypted_image", "Image contains an encrypted slice and is unsuitable for static modification; no decryption is attempted", image["path"])
    except InspectionError as exc:
        issue(report, exc.code, exc.message, exc.path, "error")
    except (zipfile.BadZipFile, EOFError, RuntimeError, NotImplementedError, struct.error):
        issue(report, "invalid_archive_or_image", "Archive/image could not be read consistently", severity="error")
    except OSError as exc:
        issue(report, "io_error", "Input could not be read (%s)" % type(exc).__name__, severity="error")
    report["readiness"] = "invalid" if any(i["severity"] == "error" for i in report["issues"]) else ("blocked" if report["issues"] else "candidate")
    return report


def exit_code(report):
    if any(i["code"] == "io_error" for i in report["issues"]):
        return 4
    return {"candidate": 0, "blocked": 2, "invalid": 3}[report["readiness"]]


def text_report(report):
    lines = ["Analysis input readiness: " + report["readiness"], "Game adapter: unimplemented; playable port: false"]
    if report["bundle"]:
        bundle = report["bundle"]
        lines.append("Bundle: %s; version %s; build %s" % tuple(json.dumps(bundle[k], ensure_ascii=True) for k in ("identifier", "version", "build")))
    for image in report["images"]:
        lines.append("Image %s: SHA256 %s" % (json.dumps(image["path"], ensure_ascii=True), image["sha256"]))
        for value in image["slices"]:
            lines.append("  %s, %s, minimum OS %s; encryption IDs %s; signature %s" % (value["architecture"], value["platform"], value["minimum_os"], [e["cryptid"] for e in value["encryption"]], value["code_signature"]))
    for value in report["metadata"]:
        lines.append("Metadata %s: version %s; tables not validated" % (json.dumps(value["path"], ensure_ascii=True), value["version"]))
    for value in report["issues"]:
        path = " [" + json.dumps(value["path"], ensure_ascii=True) + "]" if "path" in value else ""
        lines.append("%s %s%s: %s" % (value["severity"].upper(), value["code"], path, value["message"]))
    lines.extend("Limit: " + value for value in report["limitations"])
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help=".app directory or .ipa file; input is never modified")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args(argv)
    report = inspect_path(args.input)
    print(json.dumps(report, indent=2, ensure_ascii=True) if args.format == "json" else text_report(report))
    return exit_code(report)


if __name__ == "__main__":
    sys.exit(main())
