"""Original synthetic metadata/Mach-O fixtures; no game source or bytes."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from map_harmony_native_targets import (ExactTypeNames, MachO, NestedMetadata,
    ParseError, TypeCatalog, TypeResolutionError, build_report, find_module,
    registered_modules, module_pointer_array)


def own_metadata():
    images = ['Assembly-CSharp.dll', 'mscorlib.dll', 'Unity.TextMeshPro.dll']
    declarations = [('Harness', 'Fixture'), ('Outer', 'Fixture'), ('Inner', ''),
        ('<Run>d__1', ''), ('Box`1', 'Fixture'), ('Void', 'System'),
        ('Int32', 'System'), ('Boolean', 'System'), ('String', 'System'),
        ('StringChild', ''), ('IEnumerator', 'System.Collections'), ('Widget', 'Fixture')]
    specs = [('Pick', 0, 0, [1], False), ('Pick', 0, 0, [3], False),
        ('ByRef', 0, 2, [6], True), ('Nested', 0, 0, [4], False),
        ('Generic', 0, 0, [9], False), ('Run', 0, 10, [], False),
        ('Shared', 0, 0, [], False), ('Unsupported', 0, 0, [], False),
        ('Abstract', 0, 0, [], False), ('Pick', 2, 2, [], False),
        ('MoveNext', 3, 2, [], False), ('Ping', 11, 0, [], True)]
    strings = sorted(set(['', 'T', 'value'] + images + [n for n, _ in declarations] +
                         [ns for _, ns in declarations] + [m[0] for m in specs]))
    pool, indices = bytearray(), {}
    for text in strings:
        indices[text] = len(pool)
        pool.extend(text.encode() + b'\0')
    data, pairs = bytearray(256), [(256, 0)] * 31

    def table(index, content):
        pairs[index] = len(data), len(content)
        data.extend(content)

    table(2, pool)
    rows = []
    byval = [11, 12, 4, 17, 7, 0, 1, 2, 3, 13, 10, 18]
    for i, (name, namespace) in enumerate(declarations):
        row = [0] * 26
        row[0], row[1], row[2] = indices[name], indices[namespace], byval[i]
        row[3], row[6], row[9], row[12] = 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff
        row[25] = 0x02000001 + i
        methods = [j for j, spec in enumerate(specs) if spec[1] == i]
        if methods:
            row[9], row[16] = methods[0], len(methods)
        if i in (0, 1, 8):
            row[12], row[20] = {0: 0, 1: 1, 8: 2}[i], 1
        if i in (2, 3, 9):
            row[3] = {2: 12, 3: 11, 9: 3}[i]
        if i == 4:
            row[6] = 0
        rows.append(struct.pack('<16I8H2I', *row))
    table(19, b''.join(rows))
    table(15, struct.pack('<3i', 3, 2, 9))
    table(14, struct.pack('<4i', 4, 1, 0, 0))
    table(12, struct.pack('<IIhhHH', 0, indices['T'], 0, 0, 0, 0))
    methods, params, position = bytearray(), bytearray(), 0
    for j, (name, owner, returns, args, static) in enumerate(specs):
        rid = j + 1 if owner != 11 else 1
        methods.extend(struct.pack('<IiiiiiI4H', indices[name], owner, returns, 0,
            position, -1, 0x06000000 | rid, 0x86 | (0x10 if static else 0), 0, 65535, len(args)))
        for argument in args:
            params.extend(struct.pack('<IIi', indices['value'], 0x08000001 + position, argument))
            position += 1
    table(5, methods)
    table(10, params)
    table(20, b''.join(struct.pack('<10I', indices[name], i, start, count, 0, 0,
        0xffffffff, 0x20000001 + i, 0, 0) for i, (name, start, count) in
        enumerate(zip(images, [0, 5, 11], [5, 6, 1]))))
    struct.pack_into('<II', data, 0, 0xFAB11BAF, 31)
    for i, pair in enumerate(pairs):
        struct.pack_into('<II', data, 8 + i * 8, *pair)
    return bytes(data)


def own_native():
    data = bytearray(0x14000)
    commands = []
    for name, va, vsize, offset, size, protection in [
        (b'__TEXT', 0, 0x4000, 0, 0x4000, 5),
        (b'__DATA_CONST', 0x4000, 0x4000, 0x4000, 0x4000, 3),
        (b'__DATA', 0x8000, 0x8000, 0x8000, 0x8000, 3),
        (b'__LINKEDIT', 0x10000, 0x4000, 0x10000, 0x4000, 1)]:
        commands.append(struct.pack('<II16sQQQQiiII', 0x19, 72, name, va, vsize, offset, size, 7, protection, 0, 0))
    commands.append(struct.pack('<II16s', 0x1b, 24, bytes(range(16))))
    blob = b''.join(commands)
    struct.pack_into('<8I', data, 0, 0xfeedfacf, 0x100000c, 0, 6, len(commands), len(blob), 0, 0)
    data[32:32 + len(blob)] = blob
    for string, address in [('Assembly-CSharp.dll', 0x2000), ('mscorlib.dll', 0x2040), ('Unity.TextMeshPro.dll', 0x2080)]:
        data[address:address + len(string) + 1] = string.encode() + b'\0'
    for module, name, count, pointers in [(0x5000, 0x2000, 11, 0x8400), (0x5100, 0x2040, 0, 0), (0x5200, 0x2080, 1, 0x8500)]:
        struct.pack_into('<3Q', data, module, name, count, pointers)
    addresses = [0x1000 + i * 0x40 for i in range(11)]
    addresses[8] = 0  # original abstract/no-AOT declaration
    struct.pack_into('<11Q', data, 0x8400, *addresses)
    struct.pack_into('<Q', data, 0x8500, addresses[6])  # deliberate cross-image sharing
    for address in addresses:
        if address:
            struct.pack_into('<I', data, address, 0xd10043ff)  # own SUB SP,SP,#16
    struct.pack_into('<I', data, addresses[7], 0xd503201f)  # own unsupported NOP
    struct.pack_into('<3Q', data, 0x8600, 0x5000, 0x5100, 0x5200)
    code = [0] * 17
    code[15], code[16] = 3, 0x8600
    struct.pack_into('<17Q', data, 0x8800, *code)
    registration = [0] * 16
    registration[6], registration[7] = 19, 0x8c00
    registration[10], registration[11] = 12, 0x8e00
    registration[12], registration[13] = 12, 0x8f00
    struct.pack_into('<16Q', data, 0x8a00, *registration)
    pointers = [0x9000 + i * 16 for i in range(19)]
    struct.pack_into('<19Q', data, 0x8c00, *pointers)
    descriptors = [(0, 1, False), (0, 8, False), (0, 2, False), (8, 14, False),
        (2, 18, False), (pointers[4], 29, False), (0, 8, True), (4, 18, False),
        (0xa000, 21, False), (pointers[8], 29, False), (10, 18, False),
        (0, 18, False), (1, 18, False), (9, 17, False), (0xa080, 20, False),
        (pointers[1], 15, False), (0, 19, False), (3, 18, False), (11, 18, False)]
    for pointer, (value, kind, byref) in zip(pointers, descriptors):
        struct.pack_into('<QI', data, pointer, value, (kind << 16) | ((1 << 29) if byref else 0))
    struct.pack_into('<2Q', data, 0xa000, pointers[7], 0xa040)
    struct.pack_into('<2Q', data, 0xa040, 1, 0xa060)
    struct.pack_into('<Q', data, 0xa060, pointers[4])
    struct.pack_into('<QBBB5xQQ', data, 0xa080, pointers[1], 2, 0, 0, 0, 0)
    return bytes(data)


def selector(identity='pick-int', owner='Fixture.Harness', name='Pick', params=None, returns='System.Void', static=False, image='Assembly-CSharp', kind='Normal'):
    return {'selectorId': identity, 'image': image, 'declaringType': owner,
        'methodName': name, 'parameterTypes': ['System.Int32'] if params is None else params,
        'returnType': returns, 'isStatic': static, 'methodKind': kind}


def document(*selectors):
    return {'schema': 'ehr.native-target-selectors.v1', 'selectors': list(selectors)}


def report(*selectors, native=None, metadata=None):
    return build_report(MachO(own_native() if native is None else native),
        NestedMetadata(own_metadata() if metadata is None else metadata), document(*selectors))


class ExactHarmonyMapTests(unittest.TestCase):
    def test_owning_image_exact_overload_and_no_fallback(self):
        result = report(selector(), selector('wrong', params=['System.Boolean']),
            selector('wrong-return', returns='System.Boolean'), selector('wrong-static', static=True),
            selector('other-image', owner='Fixture.Widget', name='Ping', params=[], static=True, image='Unity.TextMeshPro'))
        rows = result['selectors']
        self.assertEqual(rows[0]['candidate']['native_rva'], '0x1000')
        self.assertEqual([row['status'] for row in rows[1:4]], ['exact_signature_not_found'] * 3)
        self.assertEqual(rows[4]['candidate']['owning_image'], 'Unity.TextMeshPro.dll')
        self.assertEqual(rows[4]['candidate']['native_rva'], '0x1180')

    def test_nested_identity_graph_and_generic_array_byref_normalization(self):
        result = report(selector('nested', name='Nested', params=['Fixture.Outer/Inner']),
            selector('generic', name='Generic', params=['Fixture.Box< Fixture.Outer+Inner >[]']),
            selector('ref', name='ByRef', params=['System.Int32&'], returns='System.Boolean', static=True),
            selector('inner', owner='Fixture.Outer+Inner', name='Pick', params=[], returns='System.Boolean'))
        self.assertTrue(all(row['status'] == 'exact_metadata_native_candidate' for row in result['selectors']))
        self.assertEqual(result['selectors'][1]['candidate']['parameter_types'], ['Fixture.Box<Fixture.Outer+Inner>[]'])
        self.assertEqual(result['registration_validation']['nested_type_parent_relations_validated'], 3)
        metadata = NestedMetadata(own_metadata())
        self.assertEqual(metadata.type_name(2), 'Fixture.Outer+Inner')
        self.assertEqual(metadata.type_name(9), 'System.String+StringChild')
        with self.assertRaises(TypeResolutionError):
            TypeCatalog(metadata).selector('Fixture.Outer.Inner')  # no dot-to-nested guessing

    def test_generic_arity_aliases_rectangular_arrays_and_unsupported_types(self):
        metadata, native = NestedMetadata(own_metadata()), MachO(own_native())
        reg, *_ = registered_modules(native, metadata, find_module(native, metadata, 'Assembly-CSharp.dll'))
        catalog = TypeCatalog(metadata)
        names = ExactTypeNames(native, metadata, reg, catalog)
        self.assertEqual(names.at_index(14), 'System.Int32[,]')
        self.assertEqual(names.at_index(15), 'System.Int32*')
        self.assertEqual(catalog.selector('Fixture.Box`1<System.Int32>'), 'Fixture.Box<System.Int32>')
        for text in ['int', 'Fixture.Box<System.Int32,System.Int32>', 'Fixture.Box`2<System.Int32>', 'System.Int32&[]', 'System.Int32[0:3]']:
            with self.assertRaises(TypeResolutionError, msg=text):
                catalog.selector(text)
        with self.assertRaises(TypeResolutionError):
            names.at_index(16)  # open generic parameter never becomes a concrete type

    def test_duplicate_exact_overloads_are_ambiguous_and_byref_is_exact(self):
        data = bytearray(own_metadata())
        metadata = NestedMetadata(bytes(data))
        # Change the second Pick(String) into Pick(Int32), keeping separate RID.
        struct.pack_into('<i', data, metadata.tables['parameters'][0] + 12 + 8, 1)
        row = report(selector(), metadata=bytes(data))['selectors'][0]
        self.assertEqual(row['status'], 'ambiguous_exact_signature')
        self.assertIsNone(row['native_rva'])
        row = report(selector('missing-ref', name='ByRef', params=['System.Int32'],
            returns='System.Boolean', static=True))['selectors'][0]
        self.assertEqual(row['status'], 'exact_signature_not_found')

    def test_invalid_selector_documents_fail_before_mapping(self):
        native, metadata = MachO(own_native()), NestedMetadata(own_metadata())
        for selectors in [[None], [selector(), selector()], [dict(selector(), isStatic=1)]]:
            with self.assertRaises(ParseError):
                build_report(native, metadata, {'schema': 'ehr.native-target-selectors.v1', 'selectors': selectors})

    def test_coroutine_factory_never_supplies_movenext_target(self):
        row = report(selector('iterator', name='Run', params=[], returns='System.Collections.IEnumerator', kind='CoroutineMoveNext'))['selectors'][0]
        self.assertEqual(row['status'], 'coroutine_MoveNext_unbound')
        self.assertIsNone(row['native_rva'])
        self.assertEqual(row['factory_candidate_only']['native_rva'], '0x1140')
        self.assertEqual(row['body_candidates_unbound'][0]['native_rva'], '0x1280')
        self.assertFalse(row['body_candidates_unbound'][0]['runtime_association_verified'])
        self.assertNotEqual(row['body_candidates_unbound'][0]['native_rva'], row['factory_candidate_only']['native_rva'])

    def test_shared_entry_and_strict_instruction_relocation(self):
        rows = report(selector('shared', name='Shared', params=[]), selector('bad', name='Unsupported', params=[]),
            selector('empty', name='Abstract', params=[]))['selectors']
        self.assertTrue(rows[0]['candidate']['shared_entry'])
        self.assertEqual(rows[0]['candidate']['registered_module_entry_count'], 2)
        self.assertEqual(rows[1]['candidate']['first_instruction_relocation']['status'], 'unsupported')
        self.assertEqual(rows[2]['status'], 'exact_metadata_no_native_entry')
        self.assertIsNone(rows[2]['native_rva'])

    def test_nested_corruption_and_registration_corruption_fail_closed(self):
        original = own_metadata()
        metadata = NestedMetadata(original)
        offset = metadata.tables['nested_types'][0]
        for value in [1, -1, 100000]:
            data = bytearray(original)
            struct.pack_into('<i', data, offset + 4, value)  # self, invalid or out of bounds
            with self.assertRaises(ParseError):
                report(selector(), metadata=bytes(data))
        data = bytearray(original)
        row_offset = metadata.tables['types'][0] + 2 * 88
        struct.pack_into('<I', data, row_offset + 3 * 4, 11)  # Inner wrongly declares Harness
        with self.assertRaises(ParseError):
            report(selector(), metadata=bytes(data))
        data = bytearray(own_native())
        struct.pack_into('<Q', data, 0x8400, 0x8500)  # writable, non-executable target
        with self.assertRaises(ParseError):
            report(selector(), native=bytes(data))

    def test_zero_fill_initial_tables_are_explicit_and_not_inferred_runtime_values(self):
        data = bytearray(own_native())
        # Make DATA's VM size larger than file size, with LINKEDIT VA moved.
        struct.pack_into('<Q', data, 32 + 2 * 72 + 32, 0x14000)
        struct.pack_into('<Q', data, 32 + 3 * 72 + 24, 0x1c000)
        native = MachO(bytes(data))
        values, storage = module_pointer_array(native, 0x19000, 6)
        self.assertEqual(values, (0,) * 6)
        self.assertEqual(storage, 'zero_filled_initial_image_only')
        with self.assertRaises(ParseError):
            module_pointer_array(native, 0x1ffff, 6)

    def test_cli_pin_mismatch_read_only_and_exclusive_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            framework, metadata, selectors, pins, output = [root / name for name in ['Framework', 'metadata.dat', 'selectors.json', 'pins.json', 'report.json']]
            framework.write_bytes(own_native()); metadata.write_bytes(own_metadata())
            selectors.write_text(json.dumps(document(selector())))
            evidence = {'framework_uuid': MachO(framework.read_bytes()).uuid, 'input_pins': {
                key: {'size': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                for key, path in [('framework', framework), ('metadata', metadata)]}}
            pins.write_text(json.dumps(evidence))
            originals = [path.read_bytes() for path in [framework, metadata, selectors, pins]]
            command = [sys.executable, str(Path(__file__).resolve().parents[1] / 'tools/map_harmony_native_targets.py')]
            for key, path in [('framework', framework), ('metadata', metadata), ('selectors', selectors), ('pins', pins), ('output', output)]:
                command += ['--' + key, str(path)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            text = output.read_text()
            for forbidden in ['first_instruction"', 'instruction_word', 'entry_branch', 'trampoline_hex']:
                self.assertNotIn(forbidden, text)
            self.assertEqual([path.read_bytes() for path in [framework, metadata, selectors, pins]], originals)
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 2)
            self.assertEqual(output.read_text(), text)
            other = root / 'mismatch.json'
            command[-1] = str(other)
            evidence['framework_uuid'] = '00000000-0000-0000-0000-000000000000'
            pins.write_text(json.dumps(evidence))
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 2)
            self.assertFalse(other.exists())
            evidence['framework_uuid'] = MachO(framework.read_bytes()).uuid
            evidence['input_pins']['metadata']['sha256'] = '0' * 64
            pins.write_text(json.dumps(evidence))
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 2)
            self.assertFalse(other.exists())


if __name__ == '__main__':
    unittest.main()
