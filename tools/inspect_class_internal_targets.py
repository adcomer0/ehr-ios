#!/usr/bin/env python3
"""Read pinned clear Mach-O wrappers; emit OFFLINE candidates, never run code.

Private disassembly and JSON must be outside a Git checkout. No instruction
bytes or words are emitted by the JSON manifest. LLDB output stays private.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import uuid

SOURCE_HASH = '42e47c2e676fd5389385d12ddefc45bdcb88a9c3db54285381521abb762ba84f'
SOURCE_UUID = 'a287ea19-e914-3fe9-b2a1-2415ce6e73e9'
METADATA_HASH = '22dd824b108490c49962b7e31c30eae0055ce0b72e39aac3fa159324d6dd529c'


def signed(value, width):
    return value - (1 << width) if value & (1 << (width - 1)) else value


class MachO:
    def __init__(self, data):
        self.data = data
        if len(data) < 32 or struct.unpack_from('<I', data)[0] != 0xfeedfacf:
            raise ValueError('Expected thin 64-bit Mach-O')
        if struct.unpack_from('<I', data, 4)[0] != 0x100000c:
            raise ValueError('Expected ARM64 image')
        commands, size = struct.unpack_from('<II', data, 16)
        if commands > 16384 or size > len(data) - 32:
            raise ValueError('Invalid command bounds')
        self.segments, self.symbols, self.uuid = [], {}, None
        cursor, symtab = 32, None
        for _ in range(commands):
            command, count = struct.unpack_from('<II', data, cursor)
            if count < 8 or count % 8 or cursor + count > 32 + size:
                raise ValueError('Invalid command')
            if command == 0x19:
                va, vs, fo, fs = struct.unpack_from('<QQQQ', data, cursor + 24)
                if fs > vs or fo > len(data) or fs > len(data) - fo:
                    raise ValueError('Invalid segment')
                self.segments.append((va, fs, fo))
            elif command == 2:
                symtab = struct.unpack_from('<IIII', data, cursor + 8)
            elif command == 0x1b:
                self.uuid = str(uuid.UUID(bytes=data[cursor + 8:cursor + 24]))
            cursor += count
        if cursor != 32 + size or not symtab:
            raise ValueError('Missing symbol table or malformed commands')
        offset, count, strings, string_size = symtab
        if offset + count * 16 > len(data) or strings + string_size > len(data):
            raise ValueError('Invalid symbol bounds')
        for i in range(count):
            name, kind, section, _, value = struct.unpack_from('<IBBHQ', data, offset + 16 * i)
            if not name or name >= string_size or not section or kind & 0xe0:
                continue
            end = data.find(b'\0', strings + name, strings + string_size)
            if end < 0:
                raise ValueError('Unterminated symbol')
            text = data[strings + name:end].decode('utf8', 'strict')
            if text.startswith('_il2cpp_'):
                if text in self.symbols and self.symbols[text] != value:
                    raise ValueError('Ambiguous export ' + text)
                self.symbols[text] = value

    def read(self, address, count):
        matches = [(va, fs, fo) for va, fs, fo in self.segments if va <= address and count <= fs and address - va <= fs - count]
        if len(matches) != 1:
            raise ValueError('Not in one file-backed segment: ' + hex(address))
        va, _, fo = matches[0]
        return self.data[fo + address - va:fo + address - va + count]

    def word(self, address):
        if address % 4:
            raise ValueError('Unaligned instruction')
        return struct.unpack('<I', self.read(address, 4))[0]

    def branch(self, address, link=False):
        word = self.word(address)
        if word & 0xfc000000 != (0x94000000 if link else 0x14000000):
            raise ValueError('Expected direct ' + ('BL' if link else 'B') + ' at ' + hex(address))
        return address + 4 * signed(word & 0x3ffffff, 26)

    def tails(self, address, limit=8):
        result = [address]
        for _ in range(limit):
            if self.word(address) & 0xfc000000 != 0x14000000:
                return result
            address = self.branch(address)
            if address in result:
                raise ValueError('Tail branch cycle')
            result.append(address)
        raise ValueError('Tail branch depth exceeded')


def add_immediate(word):
    if word & 0xff000000 != 0x91000000:
        raise ValueError('Expected ADD X immediate')
    return word & 31, (word >> 5) & 31, ((word >> 10) & 0xfff) << (12 if word & (1 << 22) else 0)


def pc_relative(address, word, page):
    if word & 0x9f000000 != (0x90000000 if page else 0x10000000):
        raise ValueError('Expected ADRP/ADR')
    immediate = signed(((word >> 5) & 0x7ffff) << 2 | ((word >> 29) & 3), 21)
    return word & 31, ((address & ~4095) + (immediate << 12)) if page else address + immediate


def discover(image):
    export = lambda name: image.symbols['_il2cpp_' + name]
    type_entries = []
    for name in ['class_from_type', 'class_from_il2cpp_type']:
        start = export(name)
        if image.word(start) != 0x52800021:  # MOV W1,#1 wrapper ABI fact.
            raise ValueError('Expected public throwOnError=true wrapper')
        type_entries.append((name, start, image.branch(start + 4)))
    if type_entries[0][2] != type_entries[1][2]:
        raise ValueError('FromType wrappers disagree')
    from_type = type_entries[0][2]
    from_name = image.tails(export('class_from_name'))
    image_class = image.tails(export('image_get_class'))
    image_body = image_class[-1]
    definition_handle_helper = image.tails(image.branch(image_body + 8, link=True))
    definition_to_class = image.tails(image.branch(image_body + 16))
    definition_body = definition_to_class[-1]
    index_body = image.branch(definition_body + 44)
    # Independent signed-index cache body and allocation-base corroboration.
    guard = image.word(index_body + 32)
    if guard & 0xffc003ff != 0x3100001f or (guard >> 10) & 0xfff != 1:
        raise ValueError('Index body lacks observed W0==-1 guard')
    rd, rn, allocation_base = add_immediate(image.word(index_body + 152))
    if (rd, rn, allocation_base) != (1, 8, 312):
        raise ValueError('Class allocation base differs from 312 hypothesis')
    # Recover the CLASS/VALUETYPE switch targets; do not guess by call order.
    register, table_page = pc_relative(from_type + 72, image.word(from_type + 72), True)
    rd, rn, table_offset = add_immediate(image.word(from_type + 76))
    target_register, switch_base = pc_relative(from_type + 80, image.word(from_type + 80), False)
    if (register, rd, rn, target_register) != (9, 9, 9, 10):
        raise ValueError('Unexpected FromType jump-table register flow')
    table = table_page + table_offset
    cases = {kind: switch_base + image.read(table + kind - 15, 1)[0] * 4 for kind in [17, 18]}
    if cases[17] != cases[18]:
        raise ValueError('CLASS/VALUETYPE diverge')
    case_tail = image.branch(cases[17] + 16)
    class_case = image.tails(case_tail)
    nullable = class_case[-1]
    # This helper checks null then loads the Type->definition handle before
    # deriving its index. No private helper is ever invoked by this tool.
    data_to_definition = image.tails(image.branch(nullable + 4))
    converged = image.branch(data_to_definition[-1] + 48)
    if converged != index_body:
        raise ValueError('Independent CLASS path does not converge on index body')
    return {
        'fromType': {'rva': hex(from_type), 'publicWrappers': [{'name': name, 'rva': hex(start), 'targetRVA': hex(target)} for name, start, target in type_entries],
                     'inferredABI': 'Il2CppClass* (const Il2CppType*, bool throwOnError)', 'runtimeABIProven': False},
        'fromName': {'rva': hex(from_name[-1]), 'tailChain': list(map(hex, from_name)),
                     'inferredABI': 'Il2CppClass* (const Il2CppImage*, const char* namespaceName, const char* name)', 'runtimeABIProven': False},
        'getTypeInfoFromDefinitionIndex': {'rva': hex(index_body), 'inferredABI': 'Il2CppClass* (int32_t definitionIndex)', 'runtimeABIProven': False,
            'publicImageGetClassChain': list(map(hex, image_class)), 'definitionHandleHelperChain': list(map(hex, definition_handle_helper)),
            'definitionToClassChain': list(map(hex, definition_to_class)), 'classValueTypeCaseRVA': hex(cases[17]),
            'classCaseTailChain': list(map(hex, class_case)), 'typeDataToDefinitionChain': list(map(hex, data_to_definition)),
            'independentPathsConverge': True, 'signedMinusOneGuard': True, 'classAllocationBaseBytesObserved': allocation_base,
            'classAllocationDoesNotProveEveryFieldOffset': True},
    }


def known_definition_indices(data):
    """Read only declaration names/indices from ordinary pinned metadata31."""
    def table(ordinal, stride):
        offset, size = struct.unpack_from('<II', data, 8 + ordinal * 8)
        if size % stride or offset > len(data) or size > len(data) - offset:
            raise ValueError('Invalid declaration table')
        return offset, size // stride
    strings, string_size = struct.unpack_from('<II', data, 8 + 2 * 8)
    if strings + string_size > len(data):
        raise ValueError('Invalid metadata string bounds')
    def text(index):
        if index >= string_size:
            raise ValueError('Invalid string index')
        end = data.find(b'\0', strings + index, min(strings + string_size, strings + index + 4096))
        if end < 0:
            raise ValueError('Unterminated declaration name')
        return data[strings + index:end].decode('utf8', 'strict')
    start, count = table(19, 88)
    types = [struct.unpack_from('<16I8H2I', data, start + 88 * i) for i in range(count)]
    nested_start, nested_count = table(15, 4)
    parents = {}
    for owner, row in enumerate(types):
        first, length = row[12], row[20]
        if first > nested_count or length > nested_count - first:
            if length:
                raise ValueError('Invalid nested declaration range')
        for position in range(first, first + length):
            child = struct.unpack_from('<I', data, nested_start + position * 4)[0]
            if child >= count or child in parents or child == owner:
                raise ValueError('Invalid nested parent')
            parents[child] = owner
    def name(index, seen=()):
        if index in seen or len(seen) >= 32:
            raise ValueError('Nested declaration cycle')
        row = types[index]
        return name(parents[index], seen + (index,)) + '+' + text(row[0]) if index in parents else '.'.join(filter(None, [text(row[1]), text(row[0])]))
    start, count = table(20, 40)
    images = []
    for i in range(count):
        row = struct.unpack_from('<10I', data, start + 40 * i)
        if row[2] > len(types) or row[3] > len(types) - row[2]:
            raise ValueError('Invalid image declaration range')
        images.append((text(row[0]), row[2], row[3]))
    wanted = {'System.Object', 'System.String', 'System.Int32', 'System.Collections.ArrayList',
              'System.Collections.ArrayList+ArrayListEnumeratorSimple', 'UnityEngine.Object', 'UnityEngine.MonoBehaviour'}
    rows = []
    for index, row in enumerate(types):
        full = name(index)
        if full not in wanted:
            continue
        image = [image for image, first, count in images if first <= index < first + count]
        if len(image) != 1:
            raise ValueError('Ambiguous class image')
        rows.append({'name': full, 'image': image[0], 'definitionIndex': index, 'token': hex(row[25])})
    if len(rows) != len(wanted):
        raise ValueError('Known declaration coverage incomplete')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--framework', type=Path, required=True)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--private-output-dir', type=Path, required=True)
    parser.add_argument('--skip-lldb', action='store_true')
    args = parser.parse_args()
    framework, metadata, output = args.framework.resolve(), args.metadata.resolve(), args.private_output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if subprocess.run(['git', '-C', str(output), 'rev-parse', '--show-toplevel'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        raise ValueError('Private output must not be inside Git')
    data, metadata_data = framework.read_bytes(), metadata.read_bytes()
    if hashlib.sha256(data).hexdigest() != SOURCE_HASH or hashlib.sha256(metadata_data).hexdigest() != METADATA_HASH:
        raise ValueError('Source hash allowlist rejected input')
    if struct.unpack_from('<II', metadata_data) != (0xfab11baf, 31):
        raise ValueError('Expected pinned metadata31')
    image = MachO(data)
    if image.uuid != SOURCE_UUID:
        raise ValueError('Source UUID allowlist rejected input')
    result = discover(image)
    disassembly = output / 'internal-targets-disassembly.local.txt'
    if not args.skip_lldb:
        if '"' in str(framework):
            raise ValueError('Quoted input path unsupported for LLDB command')
        command = ['xcrun', 'lldb', '--batch', '-o', 'target create "' + str(framework) + '"']
        addresses = [(int(result['fromType']['rva'], 16), 80), (int(result['fromName']['rva'], 16), 64),
                     (int(result['getTypeInfoFromDefinitionIndex']['rva'], 16), 80)]
        for address, count in addresses:
            command.extend(['-o', f'disassemble --start-address {hex(address)} --count {count}'])
        completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20)
        disassembly.write_text(completed.stdout)
        if completed.returncode:
            raise RuntimeError('Bounded offline LLDB failed')
    manifest = {'schema': 'ehr.arm64-class-internal-candidates.v1', 'status': 'offline_candidates_only_no_private_call_or_hook',
        'frameworkSourceSHA256': SOURCE_HASH, 'frameworkUUID': SOURCE_UUID, 'metadataSHA256': METADATA_HASH, 'metadataVersion': 31,
        'targets': result, 'knownTypeDefinitionIndices': known_definition_indices(metadata_data), 'gameExecuted': False, 'privateFunctionsInvoked': False, 'nativeHooksInstalled': False,
        'rawInstructionDataEmittedInJSON': False, 'privateDisassemblyPath': None if args.skip_lldb else str(disassembly)}
    path = output / 'internal-target-candidates.local.json'
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    print(path)


if __name__ == '__main__':
    main()
