#!/usr/bin/env python3
"""Pinned, pre-sign ARM64 entry interception on a NEW unencrypted dylib copy.

No runtime memory is written. No original file is changed, decrypted, signed,
launched, or copied into a repository. Production CLI removes the signature on
a private new output copy before transforming it. Output requires fresh valid
signing before use. Extra entry points require explicit, exact signature
contracts and independently compiled handlers. This implements callback routing,
not a complete Among Us mod.

Sources for layouts/opcodes: Apple Mach-O loader.h and dyld rebase/bind opcodes;
Arm A64 instruction encoding. All writer code here is original Python.
https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h
https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/dyld.h
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import struct
import subprocess
import tempfile
import uuid

PAGE = 16384
INSERTION = 2 * PAGE
DYLD_INFO = (0x22, 0x80000022)
LOAD_DYLIBS = (0xC, 0x80000018, 0x8000001F, 0x80000023, 0x20)
LINKEDIT_DATA = (0x1D, 0x1E, 0x26, 0x29, 0x2B, 0x2E, 0x80000033)
# These commands have no absolute file offsets. String offsets are local to
# their own command, so insertion into the file never alters them.
NO_FILE_OFFSETS = (0xD, 0x1B, 0x32, 0x2A, 0x24, 0x25, 0x2F, 0x30,
                   0x8000001C, 0x12, 0x13, 0x14, 0x15, 0x2D)
SUPPORTED = set(LOAD_DYLIBS + LINKEDIT_DATA + NO_FILE_OFFSETS + DYLD_INFO + (0x19, 2, 0xB, 0x16, 0x21, 0x2C))
METHODS = {
    "PlayerControl.MurderPlayer": {"return": "System.Void", "parameters": ["PlayerControl", "MurderResultFlags"], "static": False, "symbol": "_ehr_native_murder_hook"},
    "Constants.GetBroadcastVersion": {"return": "System.Int32", "parameters": [], "static": True, "symbol": "_ehr_native_broadcast_version_hook"},
}


class PatchError(ValueError):
    pass


def bounds(offset, size, limit, name="range"):
    if offset < 0 or size < 0 or offset > limit or size > limit - offset:
        raise PatchError("Out-of-bounds " + name)


def read(data, fmt, offset):
    bounds(offset, struct.calcsize(fmt), len(data))
    return struct.unpack_from(fmt, data, offset)


def align(value, alignment):
    return (value + alignment - 1) & -alignment


def sha(data):
    return hashlib.sha256(data).hexdigest()


def uleb(value):
    if value < 0 or value >= 1 << 64:
        raise PatchError("ULEB value out of range")
    result = bytearray()
    while True:
        byte = value & 127
        value >>= 7
        result.append(byte | (128 if value else 0))
        if not value:
            return bytes(result)


def decode_leb(data, cursor, signed=False):
    value, shift = 0, 0
    for _ in range(10):
        if cursor >= len(data):
            raise PatchError("Truncated LEB operand")
        byte = data[cursor]
        cursor += 1
        value |= (byte & 127) << shift
        shift += 7
        if not byte & 128:
            if signed and byte & 64:
                value -= 1 << shift
            if (not signed and value >= 1 << 64) or (signed and not -(1 << 63) <= value < 1 << 63):
                raise PatchError("LEB operand overflow")
            return value, cursor
    raise PatchError("Oversized LEB operand")


def validate_program(data, kind, linkedit_index):
    """Return normal prefix before DONE; validate all lazy subprograms too."""
    cursor, first_done = 0, None
    while cursor < len(data):
        location = cursor
        byte = data[cursor]
        cursor += 1
        opcode, immediate = byte & 0xF0, byte & 15
        if opcode == 0:
            if byte != 0:
                raise PatchError("Invalid DONE opcode")
            if first_done is None:
                first_done = location
            if kind != "lazy":
                if any(data[cursor:]):
                    raise PatchError("Nonzero bytes after first DONE in " + kind + " program")
                return data[:location]
            continue
        if kind == "rebase":
            operands = {0x10: 0, 0x20: 1, 0x30: 1, 0x40: 0, 0x50: 0, 0x60: 1, 0x70: 1, 0x80: 2}
            if opcode not in operands:
                raise PatchError("Unknown rebase opcode")
            if opcode == 0x20 and immediate >= linkedit_index:
                raise PatchError("Original rebase addresses LINKEDIT/a following segment")
            for _ in range(operands[opcode]):
                _, cursor = decode_leb(data, cursor)
        else:
            if opcode == 0xD0:
                raise PatchError("Threaded bind programs are unsupported")
            if opcode == 0x40:
                end = data.find(b"\0", cursor)
                if end < 0:
                    raise PatchError("Unterminated bind symbol")
                cursor = end + 1
                continue
            operands = {0x10: 0, 0x20: 1, 0x30: 0, 0x50: 0, 0x60: 1, 0x70: 1, 0x80: 1, 0x90: 0, 0xA0: 1, 0xB0: 0, 0xC0: 2}
            if opcode not in operands:
                raise PatchError("Unknown bind opcode")
            if opcode == 0x70 and immediate >= linkedit_index:
                raise PatchError("Original bind addresses LINKEDIT/a following segment")
            for _ in range(operands[opcode]):
                _, cursor = decode_leb(data, cursor, signed=(opcode == 0x60))
    # dyld permits rebase processing to end at the bounded stream limit;
    # Apple's actual image does this after its final complete rebase opcode.
    # Normal binding must provide DONE so its exact pre-DONE prefix is known.
    if kind == "rebase" and first_done is None:
        return data
    if data and first_done is None:
        raise PatchError("Program has no terminating DONE: " + kind)
    return b"" if first_done is None else data[:first_done]


@dataclass
class Segment:
    command_index: int
    index: int
    name: str
    vmaddr: int
    vmsize: int
    fileoff: int
    filesize: int
    maxprot: int
    initprot: int
    nsects: int


class Image:
    def __init__(self, data, require_unsigned=True, allow_instrumented=False):
        self.data, self.commands, self.segments = data, [], []
        header = read(data, "<8I", 0)
        magic, cpu, _, kind, self.ncmds, self.sizeofcmds, _, _ = header
        if magic != 0xFEEDFACF or cpu != 0x0100000C or kind != 6:
            raise PatchError("Only thin little-endian arm64 MH_DYLIB images are supported")
        if self.ncmds > 16384 or self.sizeofcmds > 16 * 1024**2:
            raise PatchError("Load-command limit exceeded")
        bounds(32, self.sizeofcmds, len(data), "load commands")
        cursor, self.uuid, self.encryption = 32, None, []
        self.first_section = len(data)
        for index in range(self.ncmds):
            command, size = read(data, "<II", cursor)
            if size < 8 or size % 8:
                raise PatchError("Invalid load-command length/alignment")
            bounds(cursor, size, 32 + self.sizeofcmds, "load command")
            if command == 0x80000034:
                raise PatchError("Chained fixups are unsupported")
            if command not in SUPPORTED:
                raise PatchError("Unknown/unsupported offset-bearing command: 0x%x" % command)
            raw = bytearray(data[cursor:cursor + size])
            self.commands.append(raw)
            if command == 0x19:
                if size < 72:
                    raise PatchError("Short segment command")
                name, va, vs, off, fs, mp, ip, ns, _ = read(raw, "<16sQQQQiiII", 8)
                bounds(off, fs, len(data), "segment")
                if ns > (size - 72) // 80:
                    raise PatchError("Invalid section count")
                segment = Segment(index, len(self.segments), name.rstrip(b"\0").decode("ascii"), va, vs, off, fs, mp, ip, ns)
                self.segments.append(segment)
                for section in range(ns):
                    base = 72 + section * 80
                    section_size, section_off, _, reloc, nreloc, flags = read(raw, "<QIIIII", base + 40)
                    if flags & 255 not in (1, 0xC, 0x12) and section_size:
                        bounds(section_off, section_size, len(data), "section")
                        self.first_section = min(self.first_section, section_off)
                    if nreloc:
                        bounds(reloc, nreloc * 8, len(data), "section relocations")
            elif command == 0x1B:
                if size != 24 or self.uuid is not None:
                    raise PatchError("Invalid/duplicate UUID")
                self.uuid = str(uuid.UUID(bytes=bytes(raw[8:24])))
            elif command in (0x21, 0x2C):
                if size < (24 if command == 0x2C else 20):
                    raise PatchError("Short encryption command")
                cryptoff, cryptsize, cryptid = read(raw, "<III", 8)
                bounds(cryptoff, cryptsize, len(data), "encryption range")
                if cryptid:
                    raise PatchError("Encrypted image rejected; decryption is never attempted")
                self.encryption.append((cryptoff, cryptsize, cryptid))
            elif command == 0x1D:
                if size < 16:
                    raise PatchError("Short signature command")
                off, count = read(raw, "<II", 8)
                if require_unsigned and (off or count):
                    raise PatchError("Signature remains: remove it on the private copy before transformation")
            cursor += size
        if cursor != 32 + self.sizeofcmds or self.uuid is None:
            raise PatchError("Malformed command table/missing UUID")
        matches = [s for s in self.segments if s.name == "__LINKEDIT"]
        if len(matches) != 1:
            raise PatchError("Missing/ambiguous LINKEDIT")
        self.linkedit = matches[0]
        if self.linkedit.index != len(self.segments) - 1 or self.linkedit.nsects:
            raise PatchError("LINKEDIT must be the final segment and have no sections")
        if self.linkedit.fileoff % PAGE or self.linkedit.vmaddr % PAGE:
            raise PatchError("LINKEDIT is not 16KB aligned")
        if self.linkedit.fileoff + self.linkedit.filesize != len(data):
            raise PatchError("Unexpected bytes beyond the LINKEDIT file range")
        if not allow_instrumented and any(s.name in ("__EHR_TEXT", "__EHR_DATA") for s in self.segments):
            raise PatchError("Image is already instrumented")
        for s in self.segments[:-1]:
            if s.fileoff + s.filesize > self.linkedit.fileoff or s.vmaddr + s.vmsize > self.linkedit.vmaddr:
                raise PatchError("A preserved segment overlaps LINKEDIT/insertion space")
        texts = [s for s in self.segments if s.name == "__TEXT"]
        if len(texts) != 1 or texts[0].fileoff != 0:
            raise PatchError("Unsupported image base layout")
        self.preferred_base = texts[0].vmaddr

    def command(self, kind):
        found = [c for c in self.commands if read(c, "<I", 0)[0] in kind]
        if len(found) != 1:
            raise PatchError("Required unique command is absent/ambiguous")
        return found[0]

    def va_to_file(self, va, size=4):
        matches = [s for s in self.segments if s.vmaddr <= va and size <= s.filesize - (va - s.vmaddr)]
        if len(matches) != 1:
            raise PatchError("Address is not uniquely file-backed")
        segment = matches[0]
        return segment.fileoff + va - segment.vmaddr

    def code_address(self, va):
        return va % 4 == 0 and any(s.initprot & 4 and s.vmaddr <= va < s.vmaddr + s.filesize for s in self.segments)


def branch(source, destination):
    delta = destination - source
    if delta % 4 or not -(1 << 27) <= delta < 1 << 27:
        raise PatchError("ARM64 B target is out of range/alignment")
    return 0x14000000 | ((delta // 4) & 0x3FFFFFF)


def indirect_stub(stub, got):
    page_delta = ((got & ~4095) - (stub & ~4095)) // 4096
    if not -(1 << 20) <= page_delta < 1 << 20 or got % 8:
        raise PatchError("ARM64 GOT page is out of range/alignment")
    encoded = page_delta & 0x1FFFFF
    adrp = 0x90000010 | ((encoded & 3) << 29) | ((encoded >> 2) << 5)
    ldr = 0xF9400210 | (((got & 4095) // 8) << 10)
    return struct.pack("<4I", adrp, ldr, 0xD61F0200, 0xD503201F)


def validate_relocated_instruction(word):
    # PC-INDEPENDENT copies only. ADR/ADRP must use the address-aware relocator;
    # recognizing their opcodes is never permission to copy their immediates.
    if not isinstance(word, int) or not 0 <= word < 1 << 32:
        raise PatchError("Instruction must be an unsigned 32-bit word")
    if word & 0xFF8003FF == 0xD10003FF:
        amount = ((word >> 10) & 4095) << (12 if word & (1 << 22) else 0)
        if amount and amount % 16 == 0:
            return "SUB SP, SP, aligned immediate"
    if word & 0x7F800000 == 0x52800000:
        if word & (1 << 31) or ((word >> 21) & 3) < 2:
            return "MOVZ immediate"
    # 64-bit integer STP, pre-index, base SP. Preserve the exact register pair
    # and writeback, accepting only a negative, 16-byte-aligned stack frame.
    if word & 0xFFC003E0 == 0xA98003E0:
        immediate = (word >> 15) & 127
        if immediate & 64:
            immediate -= 128
        amount = immediate * 8
        if amount < 0 and amount % 16 == 0:
            return "STP X registers, [SP, negative aligned immediate]!"
    # 64-bit floating-point D pair, pre-index SP. Q/S widths and other
    # addressing modes remain excluded. This preserves the callee-saved low
    # 64-bit lanes and exact aligned frame writeback without consulting PC.
    if word & 0xFFC003E0 == 0x6D8003E0:
        immediate = (word >> 15) & 127
        if immediate & 64:
            immediate -= 128
        if immediate < 0 and (immediate * 8) % 16 == 0:
            return "STP D registers, [SP, negative aligned immediate]!"
    # Integer loads with unsigned scaled immediate, no writeback, no PC or SP
    # base. Preserve the exact load width/zero extension, operands and faults.
    # Halfword, signed, SIMD, register-offset, unscaled and literal forms stay
    # unsupported until separately exercised by original-source fixtures.
    family = word & 0xFFC00000
    if ((word >> 5) & 31) != 31:
        if family in (0x39400000, 0xB9400000, 0xF9400000):
            return {0x39400000: "LDRB W register, [X base, unsigned immediate]",
                    0xB9400000: "LDR W register, [X base, unsigned scaled immediate]",
                    0xF9400000: "LDR X register, [X base, unsigned scaled immediate]"}[family]
        # Only 32-bit integer pairs, signed-offset mode without writeback.
        # Equal destinations have constrained-unpredictable load semantics.
        if family == 0x29400000 and (word & 31) != ((word >> 10) & 31):
            return "LDP W registers, [X base, signed scaled immediate]"
    raise PatchError("Unsupported first instruction; no guessed relocation of PC-relative/control-flow/PAC instructions")


def signed(value, width):
    return value - (1 << width) if value & (1 << (width - 1)) else value


def pc_address(value):
    if not isinstance(value, int) or not 0 <= value < 1 << 64:
        raise PatchError("ARM64 address is outside the unsigned 64-bit range")
    return value


def encode_pc_relative(page, register, source, target):
    """Encode ADR or ADRP from its actual source PC to an exact target."""
    pc_address(source)
    pc_address(target)
    if source % 4 or not 0 <= register < 31:
        raise PatchError("PC-relative source/register is unsupported")
    if page:
        if target % 4096:
            raise PatchError("ADRP target must be a page address")
        delta = (target - (source & ~4095)) // 4096
    else:
        delta = target - source
    if not -(1 << 20) <= delta < 1 << 20:
        raise PatchError("ARM64 %s target is out of range" % ("ADRP" if page else "ADR"))
    encoded = delta & 0x1FFFFF
    return (0x90000000 if page else 0x10000000) | ((encoded & 3) << 29) | ((encoded >> 2) << 5) | register


def relocate_first_instruction(word, source, destination, capacity=48):
    """Return (trampoline bytes including B-back, auditable relocation details).

    A slot is 64 bytes: 16 bytes of indirect entry stub and at most 48 bytes of
    trampoline. No temporary register or flags are clobbered. Source and target
    retain the same image slide; ADRP therefore requires normal page-aligned
    Mach-O ASLR. All original instructions after the first remain in place.
    """
    if not isinstance(word, int) or not 0 <= word < 1 << 32:
        raise PatchError("Instruction must be an unsigned 32-bit word")
    pc_address(source)
    pc_address(destination)
    if source % 4 or destination % 4 or not 8 <= capacity <= 48 or capacity % 4:
        raise PatchError("Invalid trampoline source/destination/capacity")
    details = {}
    family = word & 0x9F000000
    if family in (0x10000000, 0x90000000):
        register = word & 31
        if register == 31:
            # ADR/ADRP Rd=31 discards its result, whereas ADD immediate Rd=31
            # writes SP. Reject it instead of introducing that substitution.
            raise PatchError("PC-relative destination register 31 is unsupported")
        immediate = signed((((word >> 5) & 0x7FFFF) << 2) | ((word >> 29) & 3), 21)
        if family == 0x90000000:
            target = pc_address((source & ~4095) + immediate * 4096)
            body = struct.pack("<I", encode_pc_relative(True, register, destination, target))
            kind, strategy = "ADRP exact original page", "ADRP"
        else:
            target = pc_address(source + immediate)
            delta = target - destination
            if -(1 << 20) <= delta < 1 << 20:
                body = struct.pack("<I", encode_pc_relative(False, register, destination, target))
                strategy = "ADR"
            else:
                adrp = encode_pc_relative(True, register, destination, target & ~4095)
                add = 0x91000000 | ((target & 4095) << 10) | (register << 5) | register
                body = struct.pack("<II", adrp, add)
                strategy = "ADRP+ADD"
            kind = "ADR exact original address"
        details.update({"strategy": strategy, "destination_register": register,
                        "original_target_preferred_va": hex(target)})
    else:
        kind = validate_relocated_instruction(word)
        body = struct.pack("<I", word)
        details["strategy"] = "PC-independent exact copy"
    resume = pc_address(source + 4)
    return_pc = pc_address(destination + len(body))
    result = body + struct.pack("<I", branch(return_pc, resume))
    if len(result) > capacity:
        raise PatchError("Relocated instruction and branch-back exceed trampoline slot")
    details.update({"kind": kind, "instruction_bytes": len(body),
                    "trampoline_bytes": len(result), "resume_preferred_va": hex(resume)})
    return result, details


def segment_command(name, vmaddr, fileoff, protection, size=PAGE):
    # LLVM's BindRebaseSegInfo constructs its segment table from sections,
    # rather than all LC_SEGMENT_64 commands. Give BOTH inserted segments one
    # real section so its segment indexes agree with dyld's command indexes.
    # These are appended after every original section, preserving all existing
    # nlist n_sect values and section-based references. The GOT section is
    # S_REGULAR because its pointers are described by classic bind opcodes;
    # it is not an indirect-symbol-table section.
    text = bool(protection & 4)
    section_name = b"__ehr_code" if text else b"__ehr_got"
    section = struct.pack("<16s16sQQIIIIIIII", section_name, name.encode(),
                          vmaddr, size, fileoff, 2 if text else 3, 0, 0,
                          0x80000400 if text else 0, 0, 0, 0)
    return bytearray(struct.pack("<II16sQQQQiiII", 0x19, 72 + 80, name.encode(), vmaddr, size, fileoff, size, protection, protection, 1, 0) + section)


def dylib_command(path):
    if not path.startswith("@executable_path/Frameworks/") or ".." in path.split("/") or "\0" in path or not path.isascii():
        raise PatchError("Library path must name an embedded framework/library under @executable_path/Frameworks")
    encoded = path.encode() + b"\0"
    size = align(24 + len(encoded), 8)
    return bytearray(struct.pack("<6I", 0xC, size, 24, 0, 0x10000, 0x10000) + encoded + b"\0" * (size - 24 - len(encoded)))


def validated_contracts(extra):
    contracts = dict(METHODS)
    if extra is None:
        return contracts
    if not isinstance(extra, dict) or len(extra) > 1024:
        raise PatchError("Extra contracts must be a bounded method dictionary")
    for key, contract in extra.items():
        if key in contracts or not isinstance(key, str) or not 1 <= len(key) <= 1024 or any(c in key for c in "\x00\r\n="):
            raise PatchError("Invalid/duplicate/protected hook contract key")
        if not isinstance(contract, dict) or not isinstance(contract.get("static"), bool):
            raise PatchError("Hook contract must declare static/instance shape")
        for field in ("return", "symbol", "declaring_type", "name"):
            value = contract.get(field)
            if not isinstance(value, str) or not 1 <= len(value) <= 4096 or any(c in value for c in "\x00\r\n"):
                raise PatchError("Hook contract must declare an exact " + field)
        params = contract.get("parameters")
        if not isinstance(params, list) or len(params) > 128 or any(not isinstance(p, str) or not 1 <= len(p) <= 4096 or any(c in p for c in "\x00\r\n") for p in params):
            raise PatchError("Invalid exact hook parameter contract")
        if not re.fullmatch(r"_[A-Za-z][A-Za-z0-9_]*", contract["symbol"]):
            raise PatchError("Handler must be an ordinary leading-underscore Mach-O C symbol")
        contracts[key] = dict(contract)
    return contracts


def select_hooks(report, specifications, extra_contracts=None):
    contracts = validated_contracts(extra_contracts)
    if len(specifications) > 1024:
        raise PatchError("Hook limit exceeded")
    selected, seen = [], set()
    for specification in specifications:
        method_name, separator, symbol = specification.partition("=")
        if method_name not in contracts or method_name in seen:
            raise PatchError("Unsupported/duplicate hook method: " + method_name)
        seen.add(method_name)
        contract = contracts[method_name]
        symbol = symbol if separator else contract["symbol"]
        if not re.fullmatch(r"_[A-Za-z][A-Za-z0-9_]*", symbol):
            raise PatchError("Handler must be an ordinary leading-underscore Mach-O C symbol")
        declaring, name = (contract["declaring_type"], contract["name"]) if "declaring_type" in contract else method_name.rsplit(".", 1)
        named_methods = [m for m in report["methods"] if m["declaring_type"] == declaring and m["name"] == name]
        matches = [m for m in named_methods if m["return_type"] == contract["return"] and
                   [p["type"] for p in m["parameters"]] == contract["parameters"] and m["static"] == contract["static"]]
        if len(matches) != 1:
            raise PatchError("Method map has absent/ambiguous target")
        method = matches[0]
        if method["return_type"] != contract["return"] or [p["type"] for p in method["parameters"]] != contract["parameters"] or method["static"] != contract["static"]:
            raise PatchError("Pinned method contract does not match expected metadata signature")
        if method["mapping"] != "codegen_module_token_rid" or method["native_rva"] is None:
            raise PatchError("Target has no validated native module mapping")
        selected.append({"method": method_name, "symbol": symbol, "rva": int(method["native_rva"], 16), "token": method["token"], "signature": {"return": contract["return"], "parameters": contract["parameters"], "static": contract["static"]}})
    if not selected:
        raise PatchError("At least one hook is required")
    return selected


def unchanged_ranges(old, new, start, end, exclusions):
    cursor = start
    hasher = hashlib.sha256()
    for lower, upper in sorted(exclusions):
        lower, upper = max(start, lower), min(end, upper)
        if lower >= upper or upper <= cursor:
            continue
        if lower > cursor:
            if old[cursor:lower] != new[cursor:lower]:
                raise PatchError("Unexpected change outside declared hook/header ranges")
            hasher.update(old[cursor:lower])
        cursor = max(cursor, upper)
    if cursor < end:
        if old[cursor:end] != new[cursor:end]:
            raise PatchError("Unexpected change outside declared hook/header ranges")
        hasher.update(old[cursor:end])
    return hasher.hexdigest()


def select_private_entries(unsigned, image, report, plan):
    """Explicit native functions: never synthesize a managed MethodInfo/token."""
    if plan.get("schema") != "ehr.static-class-private-hooks.v1" or plan.get("native_entry_kind") != "private_runtime_function_not_managed_method":
        raise PatchError("Unsupported private native entry schema/kind")
    for key, expected in (("framework_uuid", report.get("framework_uuid")),
                          ("source_framework_sha256", report.get("input_pins", {}).get("framework", {}).get("sha256")),
                          ("metadata_sha256", report.get("input_pins", {}).get("metadata", {}).get("sha256"))):
        if not expected or plan.get(key) != expected:
            raise PatchError("Private native entry input pin mismatch: " + key)
    rows=plan.get("hooks")
    if not isinstance(rows,list) or not 1<=len(rows)<=16:
        raise PatchError("Private native entry count limit")
    selected=[];names=set();symbols=set();addresses=set()
    for row in rows:
        name,symbol,abi=row.get("target"),row.get("symbol"),row.get("abi")
        if (not isinstance(name,str) or not 1<=len(name)<=256 or any(c in name for c in "\x00\r\n=") or
            not isinstance(symbol,str) or not re.fullmatch(r"_[A-Za-z][A-Za-z0-9_]*",symbol) or
            not isinstance(abi,str) or not 1<=len(abi)<=512 or any(ord(c)<32 or ord(c)>126 for c in abi) or
            row.get("hidden_MethodInfo_argument") is not False):
            raise PatchError("Invalid explicit private native entry ABI")
        try:rva=int(row["rva"],16)
        except (KeyError,TypeError,ValueError):raise PatchError("Invalid private entry RVA")
        if rva<=0 or rva%4 or name in names or symbol in symbols or rva in addresses:
            raise PatchError("Duplicate/unaligned private native entry")
        expected=row.get("prologue_sha256")
        if not isinstance(expected,str) or not re.fullmatch(r"[0-9a-f]{64}",expected):
            raise PatchError("Private native entry requires an exact128-byte prologue SHA256")
        offset=image.va_to_file(image.preferred_base+rva)
        bounds(offset,128,len(unsigned),"private entry prologue")
        if sha(unsigned[offset:offset+128])!=expected:
            raise PatchError("Private native entry prologue hash mismatch")
        names.add(name);symbols.add(symbol);addresses.add(rva)
        selected.append({"method":name,"symbol":symbol,"rva":rva,"token":None,
                         "signature":{"native_entry_kind":"private_runtime_function_not_managed_method",
                                      "native_abi":abi,"hidden_MethodInfo_argument":False,"prologue_sha256":expected}})
    return selected


def transform(unsigned, report, specifications, library, extra_contracts=None, private_entries=None):
    image = Image(unsigned)
    if image.uuid != report["framework_uuid"]:
        raise PatchError("UUID does not match pinned symbol map")
    hooks = select_hooks(report, specifications, extra_contracts)
    if private_entries is not None:
        hooks.extend(select_private_entries(unsigned,image,report,private_entries))
    if len(hooks)>1024 or len({h["method"] for h in hooks})!=len(hooks) or len({h["symbol"] for h in hooks})!=len(hooks):
        raise PatchError("Duplicate or excessive combined native hooks")
    linkedit, info = image.linkedit, image.command(DYLD_INFO)
    if len(info) != 48:
        raise PatchError("Unsupported DYLD_INFO size")
    dyld = list(read(info, "<10I", 8))
    prefixes, original_programs = {}, {}
    for index, kind in enumerate(("rebase", "normal", "weak", "lazy")):
        offset, size = dyld[index * 2:index * 2 + 2]
        if not offset and not size:
            program = b""
        else:
            bounds(offset - linkedit.fileoff, size, linkedit.filesize, kind + " program")
            program = bytes(unsigned[offset:offset + size])
        prefixes[kind] = validate_program(program, kind, linkedit.index)
        original_programs[kind] = program
    loads = [c for c in image.commands if read(c, "<I", 0)[0] in LOAD_DYLIBS]
    for c in loads:
        name_offset = read(c, "<I", 8)[0]
        if not 24 <= name_offset < len(c):
            raise PatchError("Invalid dependent-library name offset")
        end = c.find(0, name_offset)
        if end < 0:
            raise PatchError("Unterminated dependent-library name")
        if bytes(c[name_offset:end]).decode("ascii", errors="strict") == library:
            raise PatchError("Hook library already loaded")
    ordinal = len(loads) + 1
    text_size, data_size = align(len(hooks) * 64, PAGE), align(len(hooks) * 8, PAGE)
    insertion = text_size + data_size
    text_va, data_va = linkedit.vmaddr, linkedit.vmaddr + text_size
    text_off, data_off = linkedit.fileoff, linkedit.fileoff + text_size
    new_data_index = linkedit.index + 1
    if new_data_index > 15:
        raise PatchError("New segment index cannot fit bind opcode")
    text, data, manifests = bytearray(text_size), bytearray(data_size), []
    entry_offsets = set()
    for index, hook in enumerate(hooks):
        entry = image.preferred_base + hook["rva"]
        if not image.code_address(entry):
            raise PatchError("Target entry is not existing executable arm64 code")
        entry_off = image.va_to_file(entry)
        if entry_off in entry_offsets:
            raise PatchError("Distinct hook targets share a native entry; explicit combined dispatch is required")
        entry_offsets.add(entry_off)
        if entry_off < image.first_section:
            raise PatchError("Target entry overlaps Mach-O header/padding")
        first = read(unsigned, "<I", entry_off)[0]
        slot, got_offset = index * 64, index * 8
        stub, trampoline, got = text_va + slot, text_va + slot + 16, data_va + got_offset
        text[slot:slot + 16] = indirect_stub(stub, got)
        relocated, relocation = relocate_first_instruction(first, entry, trampoline)
        text[slot + 16:slot + 16 + len(relocated)] = relocated
        hook.update({"entry_va": entry, "entry_fileoff": entry_off, "stub_va": stub, "trampoline_va": trampoline, "got_va": got, "got_offset": got_offset, "branch_word": branch(entry, stub)})
        manifests.append({"method": hook["method"], "metadata_token": hook["token"], "signature": hook["signature"], "symbol": hook["symbol"], "handler_symbol": hook["symbol"], "original_rva": hex(hook["rva"]), "original_preferred_va": hex(entry), "method_rva": hex(hook["rva"]), "method_preferred_va": hex(entry), "method_file_offset": hex(entry_off), "stub_preferred_va": hex(stub), "stub_rva": hex(stub - image.preferred_base), "trampoline_preferred_va": hex(trampoline), "trampoline_rva": hex(trampoline - image.preferred_base), "got_preferred_va": hex(got), "first_instruction": hex(first), "relocation_whitelist": relocation["kind"], "relocation": relocation, "entry_branch": hex(hook["branch_word"])})
    extension = bytearray(prefixes["normal"])
    for hook in hooks:
        extension.extend(b"\x20" + uleb(ordinal))
        extension.extend(b"\x40" + hook["symbol"].encode() + b"\0")
        extension.extend(b"\x51\x60\x00")  # pointer type, addend SLEB zero
        extension.append(0x70 | new_data_index)
        extension.extend(uleb(hook["got_offset"]))
        extension.append(0x90)
    extension.append(0)
    result = bytearray(unsigned[:linkedit.fileoff]) + text + data + unsigned[linkedit.fileoff:]
    result.extend(b"\0" * ((-len(result)) % 8))
    new_bind_off = len(result)
    result.extend(extension)

    def relocate_offset(raw, field, size, label):
        offset = read(raw, "<I", field)[0]
        if not offset and not size:
            return
        bounds(offset - linkedit.fileoff, size, linkedit.filesize, label)
        if offset + insertion > 0xFFFFFFFF:
            raise PatchError("32-bit file-offset overflow")
        struct.pack_into("<I", raw, field, offset + insertion)

    updated, relocation_count = [], 0
    for index, raw in enumerate(image.commands):
        command = read(raw, "<I", 0)[0]
        if command == 0x19:
            segment = next(s for s in image.segments if s.command_index == index)
            if segment.name == "__LINKEDIT":
                updated.extend((segment_command("__EHR_TEXT", text_va, text_off, 5, text_size), segment_command("__EHR_DATA", data_va, data_off, 3, data_size)))
                struct.pack_into("<4Q", raw, 24, linkedit.vmaddr + insertion, align(len(result) - (linkedit.fileoff + insertion), PAGE), linkedit.fileoff + insertion, len(result) - (linkedit.fileoff + insertion))
            else:
                for section in range(segment.nsects):
                    base = 72 + 80 * section
                    relocation, count = read(raw, "<II", base + 56)
                    if relocation or count:
                        relocate_offset(raw, base + 56, count * 8, "section relocation")
                        relocation_count += 1
        elif command in DYLD_INFO:
            if len(raw) != 48:
                raise PatchError("Unsupported DYLD_INFO size")
            for pair in range(5):
                _, size = read(raw, "<II", 8 + pair * 8)
                relocate_offset(raw, 8 + pair * 8, size, "DYLD_INFO data")
                relocation_count += 1
            struct.pack_into("<II", raw, 16, new_bind_off, len(extension))
        elif command == 2:
            if len(raw) != 24:
                raise PatchError("Unsupported SYMTAB size")
            _, count, _, strings = read(raw, "<4I", 8)
            relocate_offset(raw, 8, count * 16, "symbol table")
            relocate_offset(raw, 16, strings, "string table")
            relocation_count += 2
        elif command == 0xB:
            if len(raw) != 80:
                raise PatchError("Unsupported DYSYMTAB size")
            for field, stride in ((6, 8), (8, 56), (10, 4), (12, 4), (14, 8), (16, 8)):
                _, count = read(raw, "<II", 8 + field * 4)
                relocate_offset(raw, 8 + field * 4, count * stride, "dynamic symbol table")
                relocation_count += 1
        elif command in LINKEDIT_DATA:
            if len(raw) != 16:
                raise PatchError("Unsupported link-edit data command size")
            _, count = read(raw, "<II", 8)
            relocate_offset(raw, 8, count, "link-edit data")
            relocation_count += 1
        elif command == 0x16:
            if len(raw) != 16:
                raise PatchError("Unsupported two-level hints size")
            _, count = read(raw, "<II", 8)
            relocate_offset(raw, 8, count * 4, "two-level hints")
            relocation_count += 1
        elif command in (0x21, 0x2C):
            off, size, _ = read(raw, "<III", 8)
            if size and off + size > linkedit.fileoff:
                raise PatchError("Encryption bookkeeping range overlaps relocated LINKEDIT")
        elif command not in NO_FILE_OFFSETS and command not in LOAD_DYLIBS:
            raise PatchError("Unhandled load command")
        updated.append(raw)
    updated.append(dylib_command(library))
    new_commands = b"".join(updated)
    old_header_end, new_header_end = 32 + image.sizeofcmds, 32 + len(new_commands)
    if new_header_end > image.first_section or any(unsigned[old_header_end:new_header_end]):
        raise PatchError("Insufficient zero-filled header padding")
    struct.pack_into("<II", result, 16, len(updated), len(new_commands))
    result[32:new_header_end] = new_commands
    for hook in hooks:
        struct.pack_into("<I", result, hook["entry_fileoff"], hook["branch_word"])
    checked = Image(result, allow_instrumented=True)
    if checked.uuid != image.uuid or checked.encryption != image.encryption:
        raise PatchError("UUID/encryption commands changed unexpectedly")
    for old in image.segments[:-1]:
        new = next((s for s in checked.segments if s.name == old.name), None)
        if new is None or (old.vmaddr, old.vmsize, old.fileoff, old.filesize) != (new.vmaddr, new.vmsize, new.fileoff, new.filesize):
            raise PatchError("Original non-LINKEDIT segment mapping changed")
    exclusions = [(0, new_header_end)] + [(h["entry_fileoff"], h["entry_fileoff"] + 4) for h in hooks]
    proofs = [{"segment": s.name, "preserved_bytes_sha256": unchanged_ranges(unsigned, result, s.fileoff, s.fileoff + s.filesize, exclusions)} for s in image.segments[:-1]]
    if unsigned[linkedit.fileoff:] != result[linkedit.fileoff + insertion:len(unsigned) + insertion]:
        raise PatchError("Original unsigned LINKEDIT content changed")
    new_dyld = read(checked.command(DYLD_INFO), "<10I", 8)
    for index, kind in enumerate(("rebase", "normal", "weak", "lazy")):
        off, size = new_dyld[index * 2:index * 2 + 2]
        program = bytes(result[off:off + size]) if size else b""
        if kind == "normal":
            validate_program(program, "normal", checked.linkedit.index)
            if not program.startswith(prefixes["normal"]):
                raise PatchError("Original normal-bind prefix was changed")
        elif program != original_programs[kind]:
            raise PatchError("An original rebase/weak/lazy program changed")
    return bytes(result), {
        "schema_version": 1, "purpose": "pre-sign static native callback routing", "signed": False, "launched": False,
        "runtime_executable_memory_writes": False, "original_input_modified": False,
        "source_uuid": image.uuid, "original_uuid": image.uuid, "framework_uuid": image.uuid, "output_uuid": checked.uuid,
        "unsigned_input_sha256": sha(unsigned), "output_sha256": sha(result),
        "library": library, "library_ordinal": ordinal, "hooks": manifests,
        "layout": {"inserted_bytes": insertion, "text_bytes": text_size, "data_bytes": data_size, "new_text_va": hex(text_va), "new_data_va": hex(data_va), "old_linkedit_fileoff": hex(linkedit.fileoff), "new_linkedit_fileoff": hex(checked.linkedit.fileoff), "old_linkedit_vmaddr": hex(linkedit.vmaddr), "new_linkedit_vmaddr": hex(checked.linkedit.vmaddr), "bind_fileoff": hex(new_bind_off), "bind_size": len(extension), "header_padding_consumed": new_header_end - old_header_end, "relocated_file_offset_fields": relocation_count},
        "invariants": {"all_original_non_linkedit_segment_mappings_preserved": True, "original_non_linkedit_bytes_unchanged_except_headers_and_entry_words": True, "original_unsigned_linkedit_content_preserved": True, "original_rebase_weak_lazy_programs_preserved": True, "original_normal_bind_prefix_preserved": True, "encryption_commands_unchanged": True, "uuid_unchanged": True, "preserved_segments": proofs},
        "limitations": ["Requires correct fresh signing and an embedded compatible handler library before use.", "Metadata contracts identify parameters; the handler must correctly preserve the IL2CPP native calling convention including its hidden context argument.", "These files have not been launched and do not establish full role compatibility.", "Original executable code was changed at only the declared entry words; no runtime page-protection changes are used."],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--map", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--hook", action="append", help="Repeat TYPE.METHOD[=_mach_o_C_symbol]; defaults to PlayerControl.MurderPlayer")
    parser.add_argument("--library", default="@executable_path/Frameworks/EHRNativeHooks.dylib")
    parser.add_argument("--contracts", type=Path, help="Explicit extra signatures/handler symbols; ehr.native-hook-contracts.v1 JSON")
    parser.add_argument("--private-hooks", type=Path, help="Explicit hash-pinned private runtime functions, separate from managed metadata")
    args = parser.parse_args(argv)
    manifest_path = args.manifest or args.output.with_name(args.output.name + ".manifest.json")
    temporary = None
    try:
        inputs = {args.input.resolve(), args.map.resolve()}
        extra_contracts = None
        private_entries = None
        if args.private_hooks:
            inputs.add(args.private_hooks.resolve())
            if args.private_hooks.stat().st_size>128*1024:
                raise PatchError("Private native entry plan size limit")
            private_entries=json.loads(args.private_hooks.read_text(encoding="utf-8"))
        if args.contracts:
            inputs.add(args.contracts.resolve())
            if args.contracts.stat().st_size > 2 * 1024**2:
                raise PatchError("Hook contract file limit exceeded")
            contract_report = json.loads(args.contracts.read_text(encoding="utf-8"))
            if contract_report.get("schema") != "ehr.native-hook-contracts.v1":
                raise PatchError("Unsupported hook contract schema")
            extra_contracts = contract_report.get("methods")
            if extra_contracts is None:
                raise PatchError("Missing method contracts")
            validated_contracts(extra_contracts)
        if args.output.resolve() in inputs or manifest_path.resolve() in inputs or args.output.resolve() == manifest_path.resolve():
            raise PatchError("Output/manifest must be distinct from inputs and each other")
        if args.output.exists() or args.output.is_symlink() or manifest_path.exists() or manifest_path.is_symlink():
            raise PatchError("Refusing to replace an existing output or evidence manifest")
        if args.input.is_symlink() or not args.input.is_file() or args.input.stat().st_size > 1024**3:
            raise PatchError("Input must be an ordinary bounded file, not a symlink")
        report = json.loads(args.map.read_text(encoding="utf-8"))
        original = args.input.read_bytes()
        source_hash = sha(original)
        if source_hash != report["input_pins"]["framework"]["sha256"]:
            raise PatchError("Source hash does not match pinned method map")
        source_image = Image(original, require_unsigned=False)
        if source_image.uuid != report["framework_uuid"]:
            raise PatchError("Source UUID does not match pinned method map")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        descriptor, name = tempfile.mkstemp(prefix=".ehr-patch-", dir=args.output.parent)
        temporary = Path(name)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(original)
        os.chmod(temporary, stat.S_IMODE(args.input.stat().st_mode))
        if sha(temporary.read_bytes()) != source_hash:
            raise PatchError("Private copy is not byte-identical before signature removal")
        removal = subprocess.run(["/usr/bin/codesign", "--remove-signature", str(temporary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        if removal.returncode:
            raise PatchError("codesign --remove-signature failed on private copy; no transformation performed")
        unsigned = temporary.read_bytes()
        result, manifest = transform(unsigned, report, args.hook or ["PlayerControl.MurderPlayer"], args.library, extra_contracts,private_entries)
        if args.private_hooks:manifest["private_entry_plan_sha256"]=sha(args.private_hooks.read_bytes())
        if sha(args.input.read_bytes()) != source_hash:
            raise PatchError("Original input changed during operation")
        manifest["source_sha256"] = source_hash
        manifest["source_filename"] = args.input.name
        manifest["output_filename"] = args.output.name
        manifest["signature_removed_from_private_copy_before_transformation"] = True
        with temporary.open("wb") as stream:
            stream.write(result)
        # Atomic, exclusive publication; never replace an existing candidate.
        os.link(temporary, args.output)
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        with manifest_path.open("x", encoding="utf-8") as stream:
            json.dump(manifest, stream, indent=2)
            stream.write("\n")
        print("Wrote %d pre-sign hook(s); unsigned/unlaunched output: %s" % (len(manifest["hooks"]), args.output))
        print("Manifest: %s" % manifest_path)
        return 0
    except (PatchError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as exc:
        parser.exit(2, "%s: %s\n" % (type(exc).__name__, str(exc)))
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())
