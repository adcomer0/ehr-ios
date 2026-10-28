"""Own ARM64 immediate encodings only; never game instructions/bytes."""
import importlib.util
from pathlib import Path
import struct
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'tools/inspect_class_internal_targets.py'
spec = importlib.util.spec_from_file_location('own_internal_decoder', SOURCE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DecoderTests(unittest.TestCase):
    def image(self, words):
        image = object.__new__(module.MachO)
        image.data = struct.pack('<' + 'I' * len(words), *words)
        image.segments = [(0x1000, len(image.data), 0)]
        return image

    def test_forward_and_backward_branches(self):
        image = self.image([0x14000002, 0x17ffffff, 0xd65f03c0])
        self.assertEqual(image.branch(0x1000), 0x1008)
        self.assertEqual(image.branch(0x1004), 0x1000)
        self.assertEqual(image.tails(0x1000), [0x1000, 0x1008])

    def test_call_distinct_from_tail(self):
        image = self.image([0x94000001, 0xd65f03c0])
        self.assertEqual(image.branch(0x1000, link=True), 0x1004)
        with self.assertRaises(ValueError):
            image.branch(0x1000)

    def test_tail_cycle_rejected(self):
        with self.assertRaises(ValueError):
            self.image([0x14000000]).tails(0x1000)

    def test_alignment_and_bounds_rejected(self):
        image = self.image([0xd65f03c0])
        with self.assertRaises(ValueError):
            image.word(0x1001)
        with self.assertRaises(ValueError):
            image.read(0x1004, 1)

    def test_own_add_and_pc_relative_encodings(self):
        # Own ADD X1,X8,#312 and ADR X0,PC, not copied input instructions.
        self.assertEqual(module.add_immediate(0x91000000 | 312 << 10 | 8 << 5 | 1), (1, 8, 312))
        self.assertEqual(module.pc_relative(0x1234, 0x10000000, False), (0, 0x1234))
        self.assertEqual(module.pc_relative(0x1234, 0x90000000, True), (0, 0x1000))
        with self.assertRaises(ValueError):
            module.add_immediate(0xd65f03c0)


if __name__ == '__main__':
    unittest.main()
