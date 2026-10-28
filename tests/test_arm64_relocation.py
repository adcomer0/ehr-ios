"""Original instruction generation and independent decode/semantic properties."""
import random
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from patch_native_entries import PatchError, relocate_first_instruction, validate_relocated_instruction


def pc_word(page, register, immediate):
    bits = immediate % (1 << 21)
    return (0x90000000 if page else 0x10000000) | (bits % 4) * (1 << 29) | (bits // 4) * 32 | register


def address_result(words, pc):
    """Tiny independent semantic decoder for emitted address materialization."""
    registers = {}
    for word in words:
        if word & 0x9F000000 in (0x10000000, 0x90000000):
            immediate = ((word >> 29) & 3) + (((word >> 5) & 0x7FFFF) << 2)
            if immediate >= 0x100000:
                immediate -= 0x200000
            registers[word & 31] = ((pc // 4096) * 4096 + immediate * 4096
                                     if word >> 31 else pc + immediate)
        elif word & 0xFFC00000 == 0x91000000:
            registers[word & 31] = registers[(word >> 5) & 31] + ((word >> 10) & 4095)
        else:
            raise AssertionError("Unexpected address-materialization instruction")
        pc += 4
    return registers


def branch_target(word, pc):
    if word >> 26 != 5:
        raise AssertionError("Not an unconditional B")
    displacement = word & 0x3FFFFFF
    if displacement >= 0x2000000:
        displacement -= 0x4000000
    return pc + displacement * 4


class RelocationTests(unittest.TestCase):
    def assert_address_semantics(self, word, source, destination):
        code, details = relocate_first_instruction(word, source, destination)
        words = list(struct.unpack("<" + "I" * (len(code) // 4), code))
        for slide in (0, 0x4000, 0x123450000):
            expected = address_result([word], source + slide)
            actual = address_result(words[:-1], destination + slide)
            self.assertEqual(actual, expected)
            self.assertEqual(branch_target(words[-1], destination + slide + len(code) - 4), source + slide + 4)
        self.assertLessEqual(len(code), 48)
        self.assertEqual(details["trampoline_bytes"], len(code))
        self.assertEqual(details["instruction_bytes"], len(code) - 4)
        return details

    def test_adr_immediate_boundaries_registers_and_random_targets_under_aslr(self):
        rng = random.Random(0xE641)
        offsets = [-(1 << 20), -1, 0, 1, (1 << 20) - 1]
        offsets += [rng.randrange(-(1 << 20), 1 << 20) for _ in range(1000)]
        strategies = set()
        for index, immediate in enumerate(offsets):
            source = 0x800001FFC + (index % 17) * 4
            destination = source + (0x2000 if index % 2 else 0x4000000)
            details = self.assert_address_semantics(pc_word(False, index % 31, immediate), source, destination)
            strategies.add(details["strategy"])
        self.assertEqual(strategies, {"ADR", "ADRP+ADD"})

    def test_adrp_page_boundaries_sign_extension_and_range_fail_closed(self):
        rng = random.Random(0xE642)
        offsets = [-(1 << 20), -1, 0, 1, (1 << 20) - 1]
        offsets += [rng.randrange(-(1 << 20), 1 << 20) for _ in range(1000)]
        for index, immediate in enumerate(offsets):
            source = 0x800003FFC + (index % 5) * 4
            destination = source + (0x2000000 if index % 2 else -0x2000000)
            word = pc_word(True, index % 31, immediate)
            target = (source // 4096 + immediate) * 4096
            new_delta = target // 4096 - destination // 4096
            if not -(1 << 20) <= new_delta < 1 << 20:
                with self.assertRaisesRegex(PatchError, "ADRP target is out of range"):
                    relocate_first_instruction(word, source, destination)
            else:
                self.assertEqual(self.assert_address_semantics(word, source, destination)["strategy"], "ADRP")

    def test_stp_sp_preindex_negative_aligned_frames_preserve_pair_and_writeback(self):
        for frame in range(16, 513, 16):
            for first, second in ((29, 30), (0, 1), (31, 15), (8, 8)):
                immediate = (-frame // 8) % 128
                word = 0xA98003E0 | immediate << 15 | second << 10 | first
                code, details = relocate_first_instruction(word, 0x1000, 0x8000)
                copied, back = struct.unpack("<II", code)
                self.assertEqual(copied, word)
                # Independently decode the effective SP and register operands.
                signed_offset = ((copied >> 15) & 127)
                signed_offset -= 128 if signed_offset >= 64 else 0
                self.assertEqual(0x100000 + signed_offset * 8, 0x100000 - frame)
                self.assertEqual((copied & 31, (copied >> 10) & 31, (copied >> 5) & 31), (first, second, 31))
                self.assertEqual(branch_target(back, 0x8004), 0x1004)
                self.assertIn("STP", details["kind"])

    def test_stp_other_modes_widths_bases_and_unaligned_or_positive_frames_rejected(self):
        for word in (0xA9807BFD, 0xA9817BFD, 0xA9BFFBFD, 0xA9007BFD,
                     0xA8BF7BFD, 0x29BF7BFD, 0xADBF7BFD, 0xA9BF781D):
            with self.assertRaises(PatchError):
                relocate_first_instruction(word, 0x1000, 0x8000)

    def test_stp_d_preindex_frames_copy_exact_lanes_and_writeback(self):
        for frame in range(16, 513, 16):
            for first, second in ((8, 10), (0, 17), (31, 4), (8, 8)):
                word = 0x6D8003E0 | ((-frame // 8) % 128) << 15 | second << 10 | first
                copied, back = struct.unpack("<II", relocate_first_instruction(word, 0x1400, 0x9000)[0])
                self.assertEqual(copied, word)
                immediate = (copied >> 15) & 127
                immediate -= 128 if immediate >= 64 else 0
                self.assertEqual(immediate * 8, -frame)
                self.assertEqual((copied & 31, (copied >> 10) & 31, (copied >> 5) & 31), (first, second, 31))
                self.assertEqual(branch_target(back, 0x9004), 0x1404)
                self.assertIn("STP D", validate_relocated_instruction(copied))

    def test_unsigned_integer_load_width_offsets_registers_and_slide_independence(self):
        for family, width in ((0x39400000, 1), (0xB9400000, 4), (0xF9400000, 8)):
            for immediate in (0, 1, 4095):
                for base in (0, 9, 30):
                    for destination in (0, 11, 31):
                        word = family | immediate << 10 | base << 5 | destination
                        for slide in (0, 0x4000, 0x123450000):
                            code, details = relocate_first_instruction(word, 0x1400 + slide, 0x9000 + slide)
                            copied, back = struct.unpack("<II", code)
                            self.assertEqual(copied, word)
                            # Independent width/offset decode: load addresses
                            # derive from the base register, never the new PC.
                            size = 1 << ((copied >> 30) & 3)
                            address = 0x600000 + ((copied >> 10) & 4095) * size
                            self.assertEqual(size, width)
                            self.assertEqual(address, 0x600000 + immediate * width)
                            self.assertEqual(branch_target(back, 0x9004 + slide), 0x1404 + slide)
                            self.assertTrue(details["kind"].startswith("LDR"))

    def test_ldp_w_signed_offset_without_writeback_and_other_load_forms_rejected(self):
        for immediate in (-64, -1, 0, 1, 63):
            for first, second, base in ((10, 11, 0), (0, 31, 9), (30, 0, 30)):
                word = 0x29400000 | (immediate % 128) << 15 | second << 10 | base << 5 | first
                copied, back = struct.unpack("<II", relocate_first_instruction(word, 0x1400, 0x9000)[0])
                self.assertEqual(copied, word)
                signed = (copied >> 15) & 127
                signed -= 128 if signed >= 64 else 0
                self.assertEqual(signed * 4, immediate * 4)
                self.assertEqual((copied & 31, (copied >> 10) & 31, (copied >> 5) & 31), (first, second, base))
                self.assertEqual(branch_target(back, 0x9004), 0x1404)
        invalid = [0x6D8003E0, 0x6D8103E0, 0x6DBF83E0, 0x2DBE27E8, 0xADBE27E8,
                   0x6CBE27E8, 0x6D3E27E8, 0x6DBE2408,  # S/Q/post/offset/non-SP
                   0x79400000, 0x39800000, 0xB9800000, 0xBD400000,  # H/signed/SIMD
                   0xF8400000, 0xF8606800, 0xF94003E0,  # unscaled/register/SP
                   0xA9400400, 0x2D400400, 0x28C00400,  # X/SIMD/post pair
                   0x29400000, 0x294007E0]  # equal destinations/SP base
        for word in invalid:
            with self.assertRaises(PatchError, msg=hex(word)):
                relocate_first_instruction(word, 0x1400, 0x9000)

    def test_pc_relative_words_cannot_be_approved_for_blind_copy(self):
        for word in (pc_word(False, 0, 0), pc_word(True, 30, 1)):
            with self.assertRaises(PatchError):
                validate_relocated_instruction(word)

    def test_adr_expansion_capacity_and_unsupported_register_31(self):
        word = pc_word(False, 9, 73)
        self.assertEqual(self.assert_address_semantics(word, 0x1000, 0x400000)["instruction_bytes"], 8)
        with self.assertRaisesRegex(PatchError, "exceed trampoline slot"):
            relocate_first_instruction(word, 0x1000, 0x400000, capacity=8)
        for page in (False, True):
            with self.assertRaisesRegex(PatchError, "register 31"):
                relocate_first_instruction(pc_word(page, 31, 0), 0x1000, 0x8000)

    def test_control_flow_pac_literal_loads_and_invalid_address_ranges_rejected(self):
        for word in (0x14000000, 0x94000000, 0x54000000, 0x34000000, 0x36000000,
                     0xD61F0000, 0xD65F03C0, 0xD503233F, 0xD503237F,
                     0x58000000, 0x18000000, 0x98000000, 0xD8000000):
            with self.assertRaises(PatchError):
                relocate_first_instruction(word, 0x1000, 0x8000)
        for source, destination in ((3, 0x8000), (-4, 0x8000), ((1 << 64) - 4, 0x8000), (0x1000, 1 << 64)):
            with self.assertRaises(PatchError):
                relocate_first_instruction(0x528000E0, source, destination)
        with self.assertRaises(PatchError):
            relocate_first_instruction(pc_word(True, 0, -1), 0, 0x8000)
        with self.assertRaisesRegex(PatchError, "ADRP target is out of range"):
            relocate_first_instruction(pc_word(False, 0, 0), 0x100000000, 0x800000000)


if __name__ == "__main__":
    unittest.main()
