#!/usr/bin/env python3
"""Read-only, narrowly scoped metadata-v31 / arm64 Mach-O symbol mapper.

Reads an owner's unencrypted UnityFramework and metadata in place. Writes only
selected declarations, native RVAs and hash/UUID pins, never game bytes/code.
No nm, native execution, decryption, patching, signing or game launch is used.

Layout references (consulted 2026-10-28; original parser implementation):
https://github.com/Perfare/Il2CppDumper/blob/master/Il2CppDumper/Il2Cpp/MetadataClass.cs
https://github.com/Perfare/Il2CppDumper/blob/master/Il2CppDumper/Il2Cpp/Il2CppClass.cs
https://github.com/Perfare/Il2CppDumper/blob/master/Il2CppDumper/Il2Cpp/Il2Cpp.cs
https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h
"""
from __future__ import annotations

import argparse
import hashlib
import json
import mmap
from pathlib import Path
import re
import struct
import uuid


class ParseError(ValueError):
    pass


def bounds(offset, size, length):
    if offset < 0 or size < 0 or offset > length or size > length - offset:
        raise ParseError("Out-of-bounds input range")


def unpack(data, fmt, offset):
    bounds(offset, struct.calcsize(fmt), len(data))
    return struct.unpack_from(fmt, data, offset)


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for part in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(part)
    return hasher.hexdigest()


class Metadata:
    TABLES = ("string_literals", "literal_data", "strings", "events", "properties", "methods",
              "parameter_defaults", "field_defaults", "default_data", "marshaled_sizes", "parameters",
              "fields", "generic_parameters", "generic_constraints", "generic_containers", "nested_types",
              "interfaces", "vtable", "interface_offsets", "types", "images", "assemblies", "field_refs",
              "referenced_assemblies", "attribute_data", "attribute_ranges", "unresolved_types",
              "unresolved_ranges", "windows_names", "windows_strings", "exported_types")

    def __init__(self, data):
        self.data = data
        magic, self.version = unpack(data, "<II", 0)
        if magic != 0xFAB11BAF or self.version != 31:
            raise ParseError("Only ordinary IL2CPP metadata version 31 is supported")
        self.tables = {}
        for index, name in enumerate(self.TABLES):
            offset, size = unpack(data, "<II", 8 + index * 8)
            bounds(offset, size, len(data))
            self.tables[name] = offset, size
        for name, stride in (("types", 88), ("methods", 36), ("parameters", 12), ("images", 40), ("fields", 12)):
            if self.tables[name][1] % stride:
                raise ParseError("Unsupported metadata table record alignment: " + name)
        self.types = [self.record("types", 88, i, "<16I8H2I") for i in range(self.count("types", 88))]
        self.images = []
        for i in range(self.count("images", 40)):
            row = self.record("images", 40, i, "<10I")
            bounds(row[2], row[3], len(self.types))
            self.images.append({"name": self.string(row[0]), "type_start": row[2], "type_count": row[3]})

    def count(self, table, stride):
        return self.tables[table][1] // stride

    def record(self, table, stride, index, fmt):
        offset, size = self.tables[table]
        bounds(index * stride, stride, size)
        return unpack(self.data, fmt, offset + index * stride)

    def string(self, index):
        offset, size = self.tables["strings"]
        bounds(index, 1, size)
        end = self.data.find(b"\0", offset + index, min(offset + size, offset + index + 4096))
        if end < 0:
            raise ParseError("Missing/oversized metadata string terminator")
        return self.data[offset + index:end].decode("utf-8", errors="strict")

    def type_name(self, index):
        bounds(index, 1, len(self.types))
        row = self.types[index]
        return ".".join(part for part in (self.string(row[1]), self.string(row[0])) if part)

    def image_for_type(self, index):
        matches = [im for im in self.images if im["type_start"] <= index < im["type_start"] + im["type_count"]]
        if len(matches) != 1:
            raise ParseError("Type has ambiguous/missing owning image")
        return matches[0]

    def methods_for_type(self, index):
        row = self.types[index]
        start, count = row[9], row[16]
        if count == 0:
            return
        bounds(start, count, self.count("methods", 36))
        for method_index in range(start, start + count):
            method = self.record("methods", 36, method_index, "<IiiiiiI4H")
            if method[1] != index or method[6] >> 24 != 6:
                raise ParseError("Method ownership/token does not agree with its type")
            yield method_index, method

    def image_method_count(self, image):
        highest = 0
        for index in range(image["type_start"], image["type_start"] + image["type_count"]):
            for _, method in self.methods_for_type(index):
                highest = max(highest, method[6] & 0xFFFFFF)
        return highest


class MachO:
    def __init__(self, data):
        self.data, self.segments, self.uuid, self.symbol_table = data, [], None, None
        magic, cpu, _, kind, ncmds, sizeofcmds, _, _ = unpack(data, "<8I", 0)
        if magic != 0xFEEDFACF or cpu != 0x0100000C or kind != 6:
            raise ParseError("Input must be a thin, little-endian arm64 Mach-O dylib")
        if ncmds > 16384 or sizeofcmds > 16 * 1024**2:
            raise ParseError("Mach-O load-command limits exceeded")
        bounds(32, sizeofcmds, len(data))
        cursor = 32
        for _ in range(ncmds):
            command, size = unpack(data, "<II", cursor)
            if size < 8 or size % 8:
                raise ParseError("Malformed load command")
            bounds(cursor, size, 32 + sizeofcmds)
            if command == 0x19:
                if size < 72:
                    raise ParseError("Truncated segment command")
                name, va, vsize, fileoff, filesize, _, protection, _, _ = unpack(data, "<16sQQQQiiII", cursor + 8)
                bounds(fileoff, filesize, len(data))
                self.segments.append({"name": name.rstrip(b"\0").decode("ascii"), "va": va, "vsize": vsize, "fileoff": fileoff, "filesize": filesize, "protection": protection})
            elif command == 0x1B:
                if size != 24 or self.uuid is not None:
                    raise ParseError("Invalid/duplicate UUID command")
                self.uuid = str(uuid.UUID(bytes=bytes(data[cursor + 8:cursor + 24])))
            elif command == 2:
                if size < 24:
                    raise ParseError("Truncated symbol command")
                self.symbol_table = unpack(data, "<IIII", cursor + 8)
            elif command in (0x21, 0x2C):
                if size < (24 if command == 0x2C else 20):
                    raise ParseError("Truncated encryption command")
                offset, length, cryptid = unpack(data, "<III", cursor + 8)
                bounds(offset, length, len(data))
                if cryptid:
                    raise ParseError("Encrypted framework rejected; this tool never decrypts")
            elif command == 0x80000034:
                raise ParseError("Chained-fixup images need a dedicated pointer decoder; refusing raw-pointer inference")
            cursor += size
        if cursor != 32 + sizeofcmds or self.uuid is None:
            raise ParseError("Malformed command table or missing UUID")
        text = [s for s in self.segments if s["name"] == "__TEXT"]
        if len(text) != 1:
            raise ParseError("Missing/ambiguous text segment")
        self.preferred_base = text[0]["va"]

    def va_to_offset(self, va, size=1):
        found = [s for s in self.segments if s["va"] <= va and va - s["va"] <= s["filesize"] and size <= s["filesize"] - (va - s["va"])]
        if len(found) != 1:
            raise ParseError("Virtual address is not uniquely file-backed")
        s = found[0]
        return s["fileoff"] + va - s["va"]

    def offset_to_va(self, offset):
        found = [s for s in self.segments if s["fileoff"] <= offset < s["fileoff"] + s["filesize"]]
        if len(found) != 1:
            raise ParseError("File offset is not uniquely mapped")
        s = found[0]
        return s["va"] + offset - s["fileoff"]

    def words(self, va, count):
        offset = self.va_to_offset(va, count * 8)
        return unpack(self.data, "<" + "Q" * count, offset)

    def cstring(self, va):
        offset = self.va_to_offset(va)
        end = self.data.find(b"\0", offset, min(len(self.data), offset + 512))
        if end < 0:
            raise ParseError("Unterminated native string")
        return self.data[offset:end].decode("utf-8", errors="strict")

    def is_code(self, va):
        return va % 4 == 0 and any(s["protection"] & 4 and s["va"] <= va < s["va"] + s["filesize"] for s in self.segments)

    def references(self, value):
        needle, results = struct.pack("<Q", value), []
        for s in self.segments:
            if s["name"] not in ("__DATA", "__DATA_CONST"):
                continue
            cursor, end = s["fileoff"], s["fileoff"] + s["filesize"]
            while True:
                cursor = self.data.find(needle, cursor, end)
                if cursor < 0:
                    break
                if cursor % 8 == 0:
                    results.append(self.offset_to_va(cursor))
                cursor += 1
                if len(results) > 100000:
                    raise ParseError("Excessive pointer candidates")
        return results

    def symbols(self):
        if self.symbol_table is None:
            return []
        symoff, count, stroff, strsize = self.symbol_table
        if count > 2000000 or strsize > 64 * 1024**2:
            raise ParseError("Symbol table limit exceeded")
        bounds(symoff, count * 16, len(self.data))
        bounds(stroff, strsize, len(self.data))
        result = []
        for i in range(count):
            nameoff, kind, section, _, va = unpack(self.data, "<IBBHQ", symoff + i * 16)
            bounds(nameoff, 1, strsize)
            end = self.data.find(b"\0", stroff + nameoff, min(stroff + strsize, stroff + nameoff + 4096))
            if end < 0:
                raise ParseError("Invalid native symbol name")
            name = self.data[stroff + nameoff:end].decode("utf-8", errors="replace")
            result.append({"name": name, "va": va, "external": bool(kind & 1), "defined": bool(kind & 0xE), "private_external": bool(kind & 0x10), "section": section})
        return result


def find_module(native, metadata, image_name):
    image = next((v for v in metadata.images if v["name"] == image_name), None)
    if image is None:
        raise ParseError("Requested managed image is absent")
    expected = metadata.image_method_count(image)
    needle, cursor, matches = image_name.encode() + b"\0", 0, []
    while True:
        offset = native.data.find(needle, cursor)
        if offset < 0:
            break
        cursor = offset + 1
        string_va = native.offset_to_va(offset)
        for module_va in native.references(string_va):
            try:
                name, count, pointers = native.words(module_va, 3)
                if name != string_va or count != expected or count > 1000000:
                    continue
                values = native.words(pointers, count)
                if not all(v == 0 or native.is_code(v) for v in values):
                    continue
                matches.append({"va": module_va, "count": count, "pointers": pointers, "image": image})
            except ParseError:
                continue
    if len(matches) != 1:
        raise ParseError("Codegen module is not uniquely structurally validated")
    return matches[0]


def find_registrations(native, metadata, module):
    type_count, meta_candidates = len(metadata.types), []
    for location in native.references(type_count):
        candidate = location - 80
        try:
            row = native.words(candidate, 16)
            if row[10] != type_count or row[12] != type_count or not (1 <= row[6] <= 2000000):
                continue
            for c, p, stride in ((row[0], row[1], 8), (row[2], row[3], 8), (row[4], row[5], 8), (row[6], row[7], 8), (row[8], row[9], 12), (row[10], row[11], 8), (row[12], row[13], 8)):
                if c > 2000000:
                    raise ParseError("Registration count exceeds limit")
                native.va_to_offset(p, c * stride)
            meta_candidates.append({"va": candidate, "types_count": row[6], "types": row[7]})
        except ParseError:
            continue
    code_candidates, module_arrays = [], []
    image_names = {im["name"] for im in metadata.images}

    def module_name_at(pointer):
        try:
            value = native.cstring(native.words(pointer, 1)[0])
            return value if value in image_names else None
        except (ParseError, UnicodeError):
            return None

    for ref in native.references(module["va"]):
        start = ref
        for _ in range(len(image_names)):
            try:
                if module_name_at(native.words(start - 8, 1)[0]) is None:
                    break
                start -= 8
            except ParseError:
                break
        names, cursor = [], start
        for _ in range(len(metadata.images) + 1):
            try:
                name = module_name_at(native.words(cursor, 1)[0])
            except ParseError:
                break
            if name is None:
                break
            names.append(name)
            cursor += 8
        if len(names) != len(metadata.images) or set(names) != image_names:
            continue
        module_arrays.append(start)
        for array_ref in native.references(start):
            # Version 31 with post-2022.3.33 code-registration additions has
            # codeGenModulesCount and codeGenModules at word indices 15/16.
            candidate = array_ref - 16 * 8
            try:
                row = native.words(candidate, 17)
                if row[15] != len(names) or row[16] != start:
                    continue
                for c, p in ((row[0], row[1]), (row[2], row[3]), (row[5], row[6]), (row[7], row[8])):
                    if c > 2000000:
                        raise ParseError("Registration count exceeds limit")
                    native.va_to_offset(p, c * 8)
                code_candidates.append({"va": candidate, "modules_count": len(names), "modules": start, "layout": "v31_with_post_29_1_pointers"})
            except ParseError:
                continue
    return meta_candidates, code_candidates, sorted(set(module_arrays))


PRIMITIVES = {1: "System.Void", 2: "System.Boolean", 3: "System.Char", 4: "System.SByte", 5: "System.Byte", 6: "System.Int16", 7: "System.UInt16", 8: "System.Int32", 9: "System.UInt32", 10: "System.Int64", 11: "System.UInt64", 12: "System.Single", 13: "System.Double", 14: "System.String", 22: "System.TypedReference", 24: "System.IntPtr", 25: "System.UIntPtr", 28: "System.Object"}


class TypeNames:
    def __init__(self, native, metadata, registration):
        self.native, self.metadata, self.registration = native, metadata, registration

    def at_index(self, index):
        if self.registration is None:
            return "unresolved_type_index:%d" % index
        bounds(index, 1, self.registration["types_count"])
        return self.at_pointer(self.native.words(self.registration["types"] + index * 8, 1)[0])

    def at_pointer(self, pointer, depth=0):
        if depth > 10:
            raise ParseError("Type recursion limit exceeded")
        offset = self.native.va_to_offset(pointer, 12)
        value, bits = unpack(self.native.data, "<QI", offset)
        kind = (bits >> 16) & 255
        if kind in PRIMITIVES:
            name = PRIMITIVES[kind]
        elif kind in (17, 18):
            name = self.metadata.type_name(value)
        elif kind in (15, 29):
            name = self.at_pointer(value, depth + 1) + ("*" if kind == 15 else "[]")
        elif kind == 21:
            base, inst = self.native.words(value, 2)
            argc, argv = self.native.words(inst, 2)
            if argc > 32:
                raise ParseError("Excessive generic type argument count")
            args = [self.at_pointer(v, depth + 1) for v in self.native.words(argv, argc)]
            name = re.sub(r"`\d+$", "", self.at_pointer(base, depth + 1)) + "<" + ", ".join(args) + ">"
        elif kind in (19, 30):
            row = self.metadata.record("generic_parameters", 16, value, "<IIhhHH")
            name = self.metadata.string(row[1])
        else:
            name = "unresolved_il2cpp_kind:%d" % kind
        return name + ("&" if bits & (1 << 29) else "")


SELECTED = {
    "Constants": {"GetBroadcastVersion", "IsVersionModded"},
    "PlayerControl": {"CheckMurder", "CmdCheckMurder", "MurderPlayer", "RpcMurderPlayer", "HandleRpc", "CoSetRole", "RpcSetRole", "Exiled", "Die", "Revive", "CheckProtect", "ProtectPlayer", "Start", "OnDestroy"},
    "AmongUsClient": {"Awake", "StartGame", "CoStartGameHost", "CoStartGameClient", "CoStartGame", "CoEndGame", "OnGameJoined", "OnPlayerJoined", "OnPlayerLeft", "OnDisconnected", "ExitGame"},
    "RoleManager": None,
    "GameManager": {"get_Instance", "StartGame", "EndGame", "OnPlayerDeath", "RpcEndGame", "HandleRpc", "CheckEndGameViaTasks"},
    "NormalGameManager": None,
    "InnerNet.InnerNetClient": {"get_AmHost", "get_AmClient", "get_GameState", "HostGame", "JoinGame", "Disconnect", "HandleMessage", "HandleGameData", "HandleRpc"},
}


def build_report(native, metadata):
    module = find_module(native, metadata, "Assembly-CSharp.dll")
    meta_candidates, code_candidates, arrays = find_registrations(native, metadata, module)
    registration = meta_candidates[0] if len(meta_candidates) == 1 else None
    types = TypeNames(native, metadata, registration)
    methods, selected_types = [], []
    for index in range(len(metadata.types)):
        full_name = metadata.type_name(index)
        if full_name not in SELECTED:
            continue
        row = metadata.types[index]
        image = metadata.image_for_type(index)
        selected_types.append({"namespace": metadata.string(row[1]), "name": metadata.string(row[0]), "metadata_type_index": index, "type_token": hex(row[25]), "owning_image": image["name"]})
        allowed = SELECTED[full_name]
        for method_index, method in metadata.methods_for_type(index):
            name = metadata.string(method[0])
            if allowed is not None and name not in allowed:
                continue
            count, rid = method[10], method[6] & 0xFFFFFF
            params = []
            for parameter_index in range(method[4], method[4] + count):
                parameter = metadata.record("parameters", 12, parameter_index, "<IIi")
                params.append({"name": metadata.string(parameter[0]), "type_index": parameter[2], "type": types.at_index(parameter[2])})
            pointer = 0
            if image["name"] == module["image"]["name"] and 1 <= rid <= module["count"]:
                pointer = native.words(module["pointers"] + (rid - 1) * 8, 1)[0]
            methods.append({"declaring_type": full_name, "name": name, "metadata_method_index": method_index, "token": hex(method[6]), "token_rid": rid, "return_type_index": method[2], "return_type": types.at_index(method[2]), "parameters": params, "static": bool(method[7] & 0x10), "virtual": bool(method[7] & 0x40), "abstract": bool(method[7] & 0x400), "flags": hex(method[7]), "slot": method[9], "native_preferred_va": hex(pointer) if pointer else None, "native_rva": hex(pointer - native.preferred_base) if pointer else None, "native_file_offset": hex(native.va_to_offset(pointer, 4)) if pointer else None, "mapping": "codegen_module_token_rid" if pointer else "no_native_pointer_resolved"})
    symbols = native.symbols()
    keys = ("PlayerControl", "MurderPlayer", "HandleRpc", "CheckMurder", "AmongUsClient", "AssignRole", "SelectRole", "RoleManager", "CodeRegistration", "MetadataRegistration")
    retained = [s for s in symbols if any(k.casefold() in s["name"].casefold() for k in keys)]
    apis = {"_il2cpp_domain_get", "_il2cpp_domain_get_assemblies", "_il2cpp_assembly_get_image", "_il2cpp_class_from_name", "_il2cpp_class_get_method_from_name", "_il2cpp_runtime_invoke", "_il2cpp_field_get_value", "_il2cpp_field_static_get_value", "_il2cpp_object_unbox", "_il2cpp_thread_attach", "_il2cpp_thread_current"}
    return {
        "schema_version": 1,
        "purpose": "read-only native callback binding research",
        "runtime_execution_performed": False,
        "native_hooks_installed": False,
        "metadata_version": metadata.version,
        "framework_uuid": native.uuid,
        "preferred_image_base": hex(native.preferred_base),
        "runtime_address_rule": "After verifying SHA256 and UUID, add native_rva to the loaded UnityFramework __TEXT base. No runtime address is reported or verified here.",
        "symtab": {"total_symbols": len(symbols), "relevant_method_or_registration_symbols_retained": len(retained), "relevant_symbols": [{"name": s["name"], "preferred_va": hex(s["va"])} for s in retained], "public_il2cpp_api_symbols": [{"name": s["name"], "preferred_va": hex(s["va"])} for s in symbols if s["name"] in apis and s["external"] and s["defined"] and not s["private_external"]]},
        "codegen_module": {"managed_image": module["image"]["name"], "preferred_va": hex(module["va"]), "method_pointer_count": module["count"], "method_pointers_preferred_va": hex(module["pointers"]), "validation": "unique name reference, metadata token-count match, and all nonnull method pointers executable/aligned"},
        "registration_inference": {"status": "structural_candidates_not_retained_symbols", "metadata": [{"preferred_va": hex(v["va"]), "types_count": v["types_count"], "types_preferred_va": hex(v["types"])} for v in meta_candidates], "code": [{"preferred_va": hex(v["va"]), "module_count": v["modules_count"], "module_array_preferred_va": hex(v["modules"]), "layout": v["layout"]} for v in code_candidates], "validated_module_arrays": [hex(v) for v in arrays]},
        "selected_types": selected_types,
        "methods": methods,
        "limits": ["RVAs identify existing AOT methods; they do not implement event interception or establish an allowed instrumentation mechanism.", "No copied machine instructions or proprietary asset bytes are included.", "Method metadata is insufficient to invent a C callback ABI; IL2CPP hidden context parameters and calling conventions still require validation.", "Registration candidates are inferred from structure and cross-references, not retained symbol names.", "Addresses must never be reused across a different hash/UUID or modified framework."],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--framework", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    paths = [args.framework.resolve(), args.metadata.resolve()]
    if args.output.resolve() in paths:
        parser.error("Output must not overwrite either input")
    try:
        before = [p.stat() for p in paths]
        if before[0].st_size > 1024**3 or before[1].st_size > 256 * 1024**2:
            raise ParseError("Input size limits exceeded")
        framework_hash, metadata_hash = digest(paths[0]), digest(paths[1])
        with paths[0].open("rb") as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as image:
            with paths[1].open("rb") as m, mmap.mmap(m.fileno(), 0, access=mmap.ACCESS_READ) as meta:
                report = build_report(MachO(image), Metadata(meta))
        after = [p.stat() for p in paths]
        if any((a.st_size, a.st_mtime_ns, a.st_ino) != (b.st_size, b.st_mtime_ns, b.st_ino) for a, b in zip(before, after)):
            raise ParseError("An input changed during inspection")
        report["input_pins"] = {"framework": {"filename": paths[0].name, "size": before[0].st_size, "sha256": framework_hash}, "metadata": {"filename": paths[1].name, "size": before[1].st_size, "sha256": metadata_hash}}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        # Exclusive creation prevents accidental replacement of prior evidence.
        with args.output.open("x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2, ensure_ascii=True)
            stream.write("\n")
        print("Mapped %d selected methods; no runtime hooks installed. Report: %s" % (len(report["methods"]), args.output))
        return 0
    except (ParseError, OSError, UnicodeError) as exc:
        parser.exit(2, "%s: %s\n" % (type(exc).__name__, str(exc)))


if __name__ == "__main__":
    raise SystemExit(main())
