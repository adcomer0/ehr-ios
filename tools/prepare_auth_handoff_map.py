#!/usr/bin/env python3
"""Read-only exact-source auth handoff mapper; emits declarations and pins only."""
import argparse
import json
import mmap
from pathlib import Path

from auth_handoff_hook_inputs import selectors, validate_report, SOURCE_SHA, METADATA_SHA, UUID
from map_harmony_native_targets import build_report, NestedMetadata
from map_native_methods import MachO, digest


def prepare(framework, metadata_path, pins):
    paths = (framework, metadata_path)
    before = [(p.stat().st_size, p.stat().st_mtime_ns, p.stat().st_ino) for p in paths]
    for key, path, sha in (("framework", framework, SOURCE_SHA), ("metadata", metadata_path, METADATA_SHA)):
        pin = pins.get("input_pins", {}).get(key, {})
        if pin.get("sha256") != sha or pin.get("size") != path.stat().st_size or digest(path) != sha:
            raise ValueError("Auth handoff reviewed source size/hash differs")
    with framework.open("rb") as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as image:
        with metadata_path.open("rb") as m, mmap.mmap(m.fileno(), 0, access=mmap.ACCESS_READ) as meta:
            native = MachO(image)
            if native.uuid != UUID:
                raise ValueError("Auth handoff reviewed source UUID differs")
            report = build_report(native, NestedMetadata(meta), selectors())
    report["input_pins"] = {key: dict(pins["input_pins"][key]) for key in ("framework", "metadata")}
    validate_report(pins, report)
    after = [(p.stat().st_size, p.stat().st_mtime_ns, p.stat().st_ino) for p in paths]
    if before != after:
        raise ValueError("Auth handoff source changed during inspection")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("framework", "metadata", "pins", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args(); output = args.output.resolve()
    if any((p / ".git").exists() for p in output.parents):
        parser.error("Generated auth handoff map must remain outside Git")
    if args.pins.stat().st_size > 16 * 1024 * 1024:
        parser.error("Auth handoff pins exceed bound")
    report = prepare(args.framework.resolve(), args.metadata.resolve(), json.loads(args.pins.read_text()))
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x") as stream: json.dump(report, stream, indent=2); stream.write("\n")
    output.chmod(0o600)


if __name__ == "__main__": main()
