#!/usr/bin/env python3
"""Resolve the public C# snapshot and pinned upstream resource catalog locally.

No game binaries, accounts, credentials, or signing operations are accessed.
The generated absolute-path manifest belongs outside this repository.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path, PurePosixPath
import subprocess
from build_source_application import COMMIT, verify


def local_file(root: Path, relative: str) -> Path:
    value = PurePosixPath(relative)
    if value.is_absolute() or not value.parts or any(p in ('.', '..') for p in value.parts) or '\\' in relative:
        raise ValueError('A contained relative file path is required')
    result = root.joinpath(*value.parts)
    if any(p.is_symlink() for p in (result, *result.parents)):
        raise ValueError('Symlink inputs are not accepted')
    if not result.resolve().is_relative_to(root) or not result.is_file():
        raise ValueError('Missing or escaped snapshot input')
    return result


def materialize(snapshot: Path, upstream: Path, output: Path) -> dict:
    snapshot, upstream, output = snapshot.resolve(), upstream.resolve(), output.resolve()
    root = snapshot.parent
    if output.is_relative_to(root.parent) or any((p / '.git').exists() for p in output.parents):
        raise ValueError('Generated local manifest must be outside a Git checkout')
    observed = subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', 'HEAD'], text=True).strip()
    if observed != COMMIT:
        raise ValueError('Upstream commit pin mismatch')
    source = json.loads(snapshot.read_text())
    if source.get('schema') != 'ehr.portable-source-snapshot.v1':
        raise ValueError('Unexpected portable snapshot schema')
    tracked = set(subprocess.check_output(['git', '-C', str(upstream), 'ls-files', '-z', '--', 'Resources'], text=True).split('\0'))
    manifest = {k: v for k, v in source.items() if k not in ('sources', 'resources')}
    manifest.update(schema='ehr.full-source-inputs.v1', upstreamRoot=str(upstream), sources=[], resources=[])
    for item in source['sources']:
        path = local_file(root, item['path'])
        manifest['sources'].append({'path': str(path), 'sha256': item['sha256']})
    for item in source['resources']:
        relative = item['upstreamPath']
        if not relative.startswith('Resources/') or relative not in tracked:
            raise ValueError('Resource must be tracked in pinned upstream Resources')
        path = local_file(upstream, relative)
        manifest['resources'].append({'path': str(path), 'sha256': item['sha256'], 'logicalName': item['logicalName']})
    verify(manifest)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x') as stream:
        json.dump(manifest, stream, indent=2)
        stream.write('\n')
    return {'sourceCount': len(manifest['sources']), 'resourceCount': len(manifest['resources']),
            'allHashesVerified': True, 'gameInputsUsed': False, 'accountOperations': False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, default=Path(__file__).resolve().parents[1] / 'source-app/manifest.json')
    parser.add_argument('--upstream-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(materialize(args.snapshot, args.upstream_root, args.output)))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(2, str(error) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
