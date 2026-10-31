# Reproducible EHR release identity

EHR's mod handshake is stricter than the displayed version. The selected
`RPC.RpcVersionCheck` sends three strings: `8.0.3`, the Git commit/branch tag,
and fork `EHR`. The unchanged lobby comparator requires all three to match.
It starts a five-second client disconnect when a known modded host differs.
`System.Version("8.0.3")` also differs from `System.Version("8.0.3.0")`, but
both inspected builds send the three-component version; their four-component
assembly version is not sent by this RPC.

The [official v8.0.3 release](https://github.com/Gurge44/EndlessHostRoles/releases/tag/v8.0.3)
has this metadata identity, read without loading or executing its mod assembly:

| Field | Official release value |
| --- | --- |
| Plugin version / fork | `8.0.3` / `EHR` |
| Commit | `ce23f0d` |
| Full source SHA | `ce23f0d050f617a59507e5bb0fbfff751d4b5134` |
| Branch | `main` |
| Wire tag | `ce23f0d(main)` |
| Official `EHR.dll` SHA256 | `612cf1b4a17a985da49dbb72c0e14c5e98f16c3e5361bbdd850add20737dc103` |

The release DLL's digest matches GitHub's published asset digest. Its full
source SHA matches this port's pinned upstream. No release DLL or game binary
is included in this repository.

The source builder formerly used the correct upstream Git root but inherited
`HEAD` as its branch from a detached checkout. Build 60 therefore advertised
`ce23f0d(HEAD)`. That is enough to reject the official `ce23f0d(main)` build
while both display 8.0.3. The mismatch is in build metadata, not a demonstrated
three-string RPC layout difference.

The builder now uses the supported GitInfo 3.3.4 MSBuild property
`-p:GitBranch=main` for this exact reviewed release. Its
[checksum-pinned policy](../tools/upstream_release_identity.json) records the
source/release URLs and artifact digest. There is no caller-supplied
compatibility-tag option. Unknown commits, modified upstream checkouts, changed
policy bytes or mismatched compiled identity constants fail the build. Commit
and full SHA remain derived from the upstream checkout. The source snapshot,
fork/version comparisons, native game version and host compatibility checks
are unchanged. Other release/fork identities still fail those checks.

After NativeAOT publication, the owned `assembly_identity_reader` reads only
ECMA-335 metadata from the actual intermediate `EHR.dll`. It never loads the
assembly or resolves game dependencies. `build-proof.json.releaseIdentity`
records the checked constants, assembly hash and policy provenance. This is
the upstream compatibility identity; port source/artifact hashes continue to
identify the modified iOS build separately. Normal build commands need no new
parameters.

An owned detached-repository fixture compiles real GitInfo twice using the same
cache: first `HEAD`, then the supported `main` override. Metadata reads verify
the changed branch, unchanged real commit/SHA, and unchanged detached checkout.
Negative fixtures reject wrong/missing version, fork, branch, commit and SHA.

```sh
EHR_DOTNET=/path/to/dotnet python3 -m unittest discover -s tests -p 'test_release_identity.py' -v
```

Matching the verified official release identity does not establish successful
gameplay with every EHR host, map or role. A newly signed build still needs its
normal runtime gates and a human peer-join test. No private lobby data or host
identity is needed for this build-metadata proof.
