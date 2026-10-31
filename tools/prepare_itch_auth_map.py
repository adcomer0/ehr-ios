#!/usr/bin/env python3
"""Read-only, reviewed-source itch provider mapper; emits no game body bytes."""
import argparse
import json
import mmap
import os
from pathlib import Path

from itch_auth_hook_inputs import (selectors, validate_report, read_json, private_output,
                                   SOURCE_SHA, METADATA_SHA, UUID)
from map_harmony_native_targets import build_report, NestedMetadata
from map_native_methods import MachO, digest


def prepare(framework, metadata_path, pins):
    if not isinstance(pins, dict) or not isinstance(pins.get("input_pins"), dict):
        raise ValueError("Invalid itch auth source pins")
    paths = (framework, metadata_path)
    before = [(path.stat().st_size, path.stat().st_mtime_ns, path.stat().st_ino) for path in paths]
    for key, path, sha in (("framework", framework, SOURCE_SHA), ("metadata", metadata_path, METADATA_SHA)):
        pin = pins.get("input_pins", {}).get(key)
        if (not isinstance(pin, dict) or pin.get("sha256") != sha or type(pin.get("size")) is not int or
                pin["size"] != path.stat().st_size or digest(path) != sha):
            raise ValueError("Itch auth reviewed source size/hash differs: " + key)
    with framework.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as image:
        with metadata_path.open("rb") as meta_stream, mmap.mmap(meta_stream.fileno(), 0, access=mmap.ACCESS_READ) as meta:
            native = MachO(image)
            if native.uuid != UUID:
                raise ValueError("Itch auth reviewed source UUID differs")
            report = build_report(native, NestedMetadata(meta), selectors())
    report["input_pins"] = {key: dict(pins["input_pins"][key]) for key in ("framework", "metadata")}
    validate_report(pins, report)
    after = [(path.stat().st_size, path.stat().st_mtime_ns, path.stat().st_ino) for path in paths]
    if before != after:
        raise ValueError("Itch auth source changed during inspection")
    # A second digest also catches equal-size changes with a restored timestamp.
    if digest(framework) != SOURCE_SHA or digest(metadata_path) != METADATA_SHA:
        raise ValueError("Itch auth source contents changed during inspection")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("framework", "metadata", "pins", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    output = private_output(args.output)
    report = prepare(args.framework.resolve(), args.metadata.resolve(), read_json(args.pins))
    output.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream: json.dump(report, stream, indent=2); stream.write("\n")


if __name__ == "__main__": main()
