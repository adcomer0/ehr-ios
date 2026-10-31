"""Package an owner's opaque PNG icon without replacing other bundle assets.

Apple documents CFBundlePrimaryIcon/CFBundleIconFiles as accepting files in the
bundle. These namespaced files avoid overwriting a copied Assets.car that may
contain unrelated native UI assets. No game image or asset is read by this tool.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import stat
import struct
import subprocess
import tempfile
import zlib

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MAX_ICON_BYTES = 32 * 1024 * 1024
BRAND_FILE = "EHRBrandIcon.png"
# Logical sizes with explicit scale suffixes; iPad Pro uses 83.5 points @2x.
VARIANTS = {
    "EHRAppIcon20.png": 20, "EHRAppIcon20@2x.png": 40, "EHRAppIcon20@3x.png": 60,
    "EHRAppIcon29.png": 29, "EHRAppIcon29@2x.png": 58, "EHRAppIcon29@3x.png": 87,
    "EHRAppIcon40.png": 40, "EHRAppIcon40@2x.png": 80, "EHRAppIcon40@3x.png": 120,
    "EHRAppIcon60@2x.png": 120, "EHRAppIcon60@3x.png": 180,
    "EHRAppIcon76.png": 76, "EHRAppIcon76@2x.png": 152,
    "EHRAppIcon83_5@2x.png": 167, BRAND_FILE: 1024,
}
IPHONE_NAMES = ["EHRAppIcon20", "EHRAppIcon29", "EHRAppIcon40", "EHRAppIcon60"]
IPAD_NAMES = ["EHRAppIcon20", "EHRAppIcon29", "EHRAppIcon40", "EHRAppIcon76", "EHRAppIcon83_5"]


def png_dimensions(data: bytes) -> tuple[int, int, int]:
    """Validate bounded static PNG framing/CRCs before Apple's pixel decoder."""
    if len(data) > MAX_ICON_BYTES or not data.startswith(PNG_SIGNATURE):
        raise ValueError("App icon must be a PNG of at most 32 MiB")
    position, seen_header, seen_data, ended = 8, False, False, False
    dimensions = None
    while position < len(data):
        if len(data) - position < 12:
            raise ValueError("App icon has a truncated PNG chunk")
        size, kind = struct.unpack_from(">I4s", data, position)
        if size > len(data) - position - 12:
            raise ValueError("App icon has an invalid PNG chunk size")
        payload = data[position + 8:position + 8 + size]
        crc = struct.unpack_from(">I", data, position + 8 + size)[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != crc:
            raise ValueError("App icon PNG checksum is invalid")
        if not seen_header:
            if kind != b"IHDR" or size != 13:
                raise ValueError("App icon must start with one PNG header")
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            if depth != 8 or color not in (2, 6) or compression or filtering or interlace not in (0, 1):
                raise ValueError("App icon must be an 8-bit RGB or RGBA PNG")
            dimensions, seen_header = (width, height, color), True
        elif kind == b"IHDR":
            raise ValueError("App icon has duplicate PNG headers")
        if kind in (b"acTL", b"fcTL", b"fdAT"):
            raise ValueError("Animated app icons are unsupported")
        if kind == b"IDAT":
            seen_data = True
        if kind == b"IEND":
            if size or not seen_data or position + 12 != len(data):
                raise ValueError("App icon has an invalid PNG end")
            ended = True
            break
        position += size + 12
    if not ended or dimensions is None:
        raise ValueError("App icon is an incomplete PNG")
    return dimensions


def _snapshot(source: Path) -> bytes:
    source = Path(source)
    path_stat = source.lstat()
    if stat.S_ISLNK(path_stat.st_mode):
        raise ValueError("App icon must be a regular file, not a symlink")
    if not stat.S_ISREG(path_stat.st_mode) or path_stat.st_size > MAX_ICON_BYTES:
        raise ValueError("App icon must be a regular PNG of at most 32 MiB")
    descriptor = os.open(source, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_ICON_BYTES:
            raise ValueError("App icon must be a regular PNG of at most 32 MiB")
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            data = stream.read(MAX_ICON_BYTES + 1)
        after = os.fstat(descriptor)
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise ValueError("App icon changed during inspection")
        if len(data) != before.st_size:
            raise ValueError("App icon read did not match its bounded size")
        return data
    finally:
        os.close(descriptor)


@dataclass(frozen=True)
class PreparedAppIcon:
    source_sha256: str
    files: dict[str, bytes]

    def manifest(self):
        return {"source_sha256": self.source_sha256, "source_pixels": [1024, 1024],
                "brand_file": BRAND_FILE, "source_metadata_copied": False,
                "assets_car_preserved": True,
                "files": {name: {"pixels": [VARIANTS[name], VARIANTS[name]],
                                 "sha256": hashlib.sha256(data).hexdigest()}
                          for name, data in self.files.items()}}


def prepare_app_icon(source: Path) -> PreparedAppIcon:
    """Read once, reject transparency, and prepare RGB variants before copying."""
    data = _snapshot(source)
    if png_dimensions(data)[:2] != (1024, 1024):
        raise ValueError("App icon must be exactly 1024 by 1024 pixels")
    with tempfile.TemporaryDirectory(prefix="ehr-own-icon-") as temporary:
        directory = Path(temporary)
        original = directory / "source.png"
        original.write_bytes(data)
        plan = directory / "variants.json"
        plan.write_text(json.dumps(VARIANTS))
        result = subprocess.run(["xcrun", "swift", str(Path(__file__).with_name("prepare_app_icon.swift")),
                                 str(original), str(directory), str(plan)],
                                capture_output=True, timeout=90)
        if result.returncode:
            # Never forward decoder diagnostics or source metadata into logs.
            raise ValueError("App icon pixel validation failed; use an opaque static 1024-pixel PNG")
        files = {}
        for name, size in VARIANTS.items():
            rendered = _snapshot(directory / name)
            if png_dimensions(rendered) != (size, size, 2):
                raise ValueError("App icon renderer did not produce opaque RGB PNG variants")
            files[name] = rendered
    return PreparedAppIcon(hashlib.sha256(data).hexdigest(), files)


def apply_app_icon(app: Path, info: dict, icon: PreparedAppIcon) -> dict:
    """Write only own icon names; remove inherited primary/alternate references."""
    if app.is_symlink() or not app.is_dir() or set(icon.files) != set(VARIANTS):
        raise ValueError("App icon destination or variant set is invalid")
    if any((app / name).is_symlink() for name in icon.files):
        raise ValueError("App icon output must not follow a bundle symlink")
    for name, data in icon.files.items():
        descriptor = os.open(app / name, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0), 0o644)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
    for name in list(info):
        if name.startswith(("CFBundleIcon", "CFBundlePrimaryIcon", "CFBundleAlternateIcons")) or name == "UIPrerenderedIcon":
            info.pop(name)
    def primary(names):
        return {"CFBundlePrimaryIcon": {"CFBundleIconFiles": names, "UIPrerenderedIcon": True}}
    info["CFBundleIcons"] = primary(IPHONE_NAMES.copy())
    info["CFBundleIcons~ipad"] = primary(IPAD_NAMES.copy())
    info["CFBundleIconFiles"] = list(dict.fromkeys(IPHONE_NAMES + IPAD_NAMES))
    return icon.manifest()
