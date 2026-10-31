"""Original synthetic PNG tests. No game assets, signing or device operations."""
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import app_icon


def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)


def fixture_png(size=1024, *, alpha=False, transparent=False, metadata=False):
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            row.extend((220 if x < size // 2 else 15, 35 if y < size // 2 else 210, 17))
            if alpha:
                row.append(0 if transparent and x == size // 2 and y == size // 2 else 255)
        rows.append(row)
    header = chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6 if alpha else 2, 0, 0, 0))
    text = chunk(b"tEXt", b"Comment\0OWN_FIXTURE_META") if metadata else b""
    return app_icon.PNG_SIGNATURE + header + text + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")


def rgb_pixels(data):
    width, height, color = app_icon.png_dimensions(data)
    if color != 2:
        raise AssertionError("Expected actual RGB output")
    parts, position = [], 8
    while position < len(data):
        length, kind = struct.unpack_from(">I4s", data, position)
        if kind == b"IDAT":
            parts.append(data[position + 8:position + 8 + length])
        position += length + 12
    raw, stride, result, previous = zlib.decompress(b"".join(parts)), width * 3, [], bytearray(width * 3)
    if len(raw) != height * (stride + 1):
        raise AssertionError("Unexpected PNG pixel payload")
    for y in range(height):
        start = y * (stride + 1); filtering = raw[start]; row = bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            left = row[i - 3] if i >= 3 else 0; above = previous[i]; diagonal = previous[i - 3] if i >= 3 else 0
            if filtering == 1: prediction = left
            elif filtering == 2: prediction = above
            elif filtering == 3: prediction = (left + above) // 2
            elif filtering == 4:
                p = left + above - diagonal; a, b, c = abs(p - left), abs(p - above), abs(p - diagonal)
                prediction = left if a <= b and a <= c else above if b <= c else diagonal
            elif filtering == 0: prediction = 0
            else: raise AssertionError("Unknown PNG filter")
            row[i] = (row[i] + prediction) & 255
        result.append(row); previous = row
    return result


class AppIconInputs(unittest.TestCase):
    def test_invalid_sources_rejected_before_pixel_decoder(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            source = base / "own.png"
            link = base / "own-link.png"; link.symlink_to(source)
            source.write_bytes(fixture_png(8))
            with patch.object(app_icon.subprocess, "run") as external:
                for path in (base, link, source):
                    with self.subTest(path=path.name), self.assertRaises(ValueError): app_icon.prepare_app_icon(path)
                os.mkfifo(base / "own-fifo")
                with self.assertRaises(ValueError): app_icon.prepare_app_icon(base / "own-fifo")
                for bad in (b"not an image", fixture_png(8)[:-1], fixture_png(8) + b"trailing"):
                    source.write_bytes(bad)
                    with self.assertRaises(ValueError): app_icon.prepare_app_icon(source)
                source.write_bytes(fixture_png(8)); damaged = bytearray(source.read_bytes()); damaged[20] ^= 1; source.write_bytes(damaged)
                with self.assertRaises(ValueError): app_icon.prepare_app_icon(source)
                with source.open("wb") as stream: stream.truncate(app_icon.MAX_ICON_BYTES + 1)
                with self.assertRaises(ValueError): app_icon.prepare_app_icon(source)
                external.assert_not_called()

    def test_animation_is_rejected_before_decoder(self):
        source = fixture_png(8)
        animated = source[:33] + chunk(b"acTL", struct.pack(">II", 2, 0)) + source[33:]
        with self.assertRaisesRegex(ValueError, "Animated"): app_icon.png_dimensions(animated)

    @unittest.skipUnless(sys.platform == "darwin", "Apple ImageIO packaging requires macOS")
    def test_actual_opaque_variants_preserve_art_and_replace_only_icon_references(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); source = base / "own.png"; source.write_bytes(fixture_png(alpha=True, metadata=True))
            before = hashlib.sha256(source.read_bytes()).hexdigest()
            icon = app_icon.prepare_app_icon(source)
            self.assertEqual(icon.source_sha256, before)
            self.assertEqual(set(icon.files), set(app_icon.VARIANTS))
            for name, data in icon.files.items():
                size = app_icon.VARIANTS[name]
                with self.subTest(name=name):
                    self.assertEqual(app_icon.png_dimensions(data), (size, size, 2))
                    self.assertNotIn(b"OWN_FIXTURE_META", data)
                    pixels = rgb_pixels(data)
                    self.assertEqual(tuple(pixels[size // 4][size // 4 * 3:size // 4 * 3 + 3]), (220, 35, 17))
                    self.assertEqual(tuple(pixels[size * 3 // 4][size * 3 // 4 * 3:size * 3 // 4 * 3 + 3]), (15, 210, 17))
            app = base / "Own.app"; app.mkdir(); unrelated = app / "Assets.car"; unrelated.write_bytes(b"OWN_UNRELATED_ASSET_CATALOG")
            info = {"CFBundleIdentifier": "org.example.own", "CFBundleShortVersionString": "1.2.3",
                    "CFBundleIcons": {"CFBundleAlternateIcons": {"Old": {"CFBundleIconFiles": ["Old"]}}},
                    "CFBundleIcons~ipad": {"CFBundlePrimaryIcon": {"CFBundleIconName": "Old"}},
                    "CFBundleIconName": "Old", "CFBundleIconFiles~ipad": ["Old"], "CFBundleIconFile": "Old.icns"}
            manifest = app_icon.apply_app_icon(app, info, icon)
            self.assertEqual(unrelated.read_bytes(), b"OWN_UNRELATED_ASSET_CATALOG")
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), before)
            self.assertEqual(info["CFBundleIdentifier"], "org.example.own")
            self.assertEqual(info["CFBundleShortVersionString"], "1.2.3")
            self.assertNotIn("Old", json.dumps(info))
            self.assertNotIn("CFBundleIconName", info)
            self.assertEqual(info["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconFiles"], app_icon.IPHONE_NAMES)
            self.assertEqual(info["CFBundleIcons~ipad"]["CFBundlePrimaryIcon"]["CFBundleIconFiles"], app_icon.IPAD_NAMES)
            self.assertEqual((app / app_icon.BRAND_FILE).read_bytes(), icon.files[app_icon.BRAND_FILE])
            self.assertEqual(manifest["files"][app_icon.BRAND_FILE]["sha256"], hashlib.sha256(icon.files[app_icon.BRAND_FILE]).hexdigest())
            self.assertTrue(manifest["assets_car_preserved"])

    @unittest.skipUnless(sys.platform == "darwin", "Apple ImageIO packaging requires macOS")
    def test_one_transparent_pixel_is_rejected_without_modifying_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "own.png"; data = fixture_png(alpha=True, transparent=True); source.write_bytes(data)
            with self.assertRaisesRegex(ValueError, "opaque"): app_icon.prepare_app_icon(source)
            self.assertEqual(source.read_bytes(), data)

    def test_destination_symlink_cannot_write_outside_bundle(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); app = base / "Own.app"; app.mkdir(); outside = base / "outside"; outside.write_bytes(b"OWN_UNCHANGED")
            (app / app_icon.BRAND_FILE).symlink_to(outside)
            icon = app_icon.PreparedAppIcon("0" * 64, {name: b"own" for name in app_icon.VARIANTS})
            info = {"CFBundleIconName": "Unchanged"}
            with self.assertRaisesRegex(ValueError, "symlink"): app_icon.apply_app_icon(app, info, icon)
            self.assertEqual(outside.read_bytes(), b"OWN_UNCHANGED")
            self.assertEqual(info, {"CFBundleIconName": "Unchanged"})


if __name__ == "__main__": unittest.main()
