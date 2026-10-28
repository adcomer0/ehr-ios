#!/usr/bin/env python3
"""Adapt only EHR's two desktop reflection wrappers to actual native fields."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

PIN = "ce23f0d050f617a59507e5bb0fbfff751d4b5134"
EDITS = {
    "Patches/ExilePatch.cs": (b"new StateMachineWrapper<AirshipExileController>(__instance)",
        b"new global::EHR.Generated.NativeStateMachineView<AirshipExileController>(__instance)"),
    "Patches/IntroPatch.cs": (b"new StateMachineWrapper<IntroCutscene>(__instance)",
        b"new global::EHR.Generated.NativeStateMachineView<IntroCutscene>(__instance)"),
}


def transform(data, before, after):
    if data.count(before) != 1:
        raise ValueError("Pinned state-machine wrapper call is absent or ambiguous")
    return data.replace(before, after)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo, output = args.upstream.resolve(), args.output.resolve()
    if output.exists() or any((parent / ".git").exists() for parent in (output, *output.parents)):
        parser.error("Choose a new output outside Git")
    revision = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    if revision != PIN:
        parser.error("Source commit differs from the inspected EHR version")
    subprocess.run(["git", "-C", str(repo), "diff", "--exit-code", PIN, "--", *EDITS], check=True)
    prepared = []
    for name, (before, after) in EDITS.items():
        data = (repo / name).read_bytes()
        prepared.append((name, data, transform(data, before, after)))
    output.mkdir(parents=True)
    rows = []
    for name, original, adapted in prepared:
        target = output / name; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(adapted)
        rows.append(dict(file=name, originalSha256=hashlib.sha256(original).hexdigest(),
            adaptedSha256=hashlib.sha256(adapted).hexdigest(), exactCallSitesChanged=1))
    (output / "state-machine-adaptation.json").write_text(json.dumps(dict(
        schema="ehr.source-state-machine-adaptation.v1", upstreamCommit=PIN, files=rows,
        callbackBodiesOtherwiseUnchanged=True, actualRuntimeTestedByTool=False,
        scope="Uses opaque native field APIs for two actual nested iterator receivers; no CLR reflection over proxy classes"), indent=2) + "\n")
    print(json.dumps({"source_files": len(rows), "changed_call_sites": len(rows)}))


if __name__ == "__main__": main()
