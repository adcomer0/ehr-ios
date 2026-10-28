> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# iOS analysis-input audit

This preparatory Python 3.9+ tool audits an `.app` directory or `.ipa` without
dependencies. It never changes input, extracts an IPA, decrypts code, signs an
app, installs anything, or executes code from the input.

```sh
python3 tools/inspect_ios.py /path/to/Among\ Us.app
python3 tools/inspect_ios.py /path/to/input.ipa --format json
python3 -m unittest discover -s tests -v
```

Reports go only to stdout. Return codes:

| Code | Meaning |
| --- | --- |
| 0 | Candidate for further analysis: structural device/Unity/metadata gates passed. |
| 2 | Structurally readable but blocked: e.g. encrypted image, simulator or missing Unity metadata. |
| 3 | Invalid, malformed, unsafe or unsupported input. |
| 4 | Operating-system input read failure. |

**A candidate is not a playable mod, a verified game build, a valid signature,
or a promise the app can be installed. The game adapter is unimplemented.**

The tool reports bundle ID/version/build, all detected Mach-O images, thin/fat
architectures, platform/minimum OS, UUID, encryption identifiers/ranges, an
unverified code-signature load-command indication, SHA-256, and IL2CPP metadata
header/version when present. It checks load-command table, inspected segment,
section, symbol, encryption and link-edit ranges. Unknown load-command payloads,
metadata tables and arbitrary assets are not comprehensively validated.

Mach-O parsing and hashing use one forward stream per image; skipped bytes are
hashed. ZIP entries are streamed, never extracted. Archive allocation is bounded
by an end-record preflight (including ZIP64). Limits cover entry counts, total
uncompressed sizes, individual files, archive size and load-command bytes.
Traversal, absolute paths, backslashes, control characters, case/Unicode-ambiguous
duplicates, overlapping ZIP members and malformed ranges fail closed. All input
symlinks are conservatively rejected, including links whose target might be safe.

The expected current Unity layout includes a native image inside
`UnityFramework.framework` and `global-metadata.dat`. Older/custom layouts are
blocked for manual review. No installed game is searched for or copied. No
provisioning profile is read; profile/device/certificate identifiers are not
included in reports. Bundle identifiers and relative code paths are reported as
requested. Inspect a stable local input; the result is not an atomic snapshot
of files changed concurrently by another process.

Do not clear encryption flags or provide protected game files as a way around
a failed audit. A required encrypted game image is unsuitable for this static
analysis/modification path; an authorized suitable build is needed.

Technical references:

- [Apple Mach-O load-command definitions](https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h)
- [Unity iOS Xcode structure](https://docs.unity3d.com/6000.0/Documentation/Manual/StructureOfXcodeProject.html)
- [Apple code-signing overview](https://developer.apple.com/library/archive/documentation/General/Conceptual/DevPedia-CocoaCore/AppSigning.html)

The inspected input must remain local and must not be committed with this tool.
