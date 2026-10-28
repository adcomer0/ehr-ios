> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Public value layout observation

This tool creates a private XCTest overlay from an explicitly selected current
test source. It preserves that source's existing tests. Preparation reads an
unmodified framework and metadata using the existing version-31 parser, records
their hashes and framework UUID, and requires unique metadata registrations.
Output must be a new directory outside a Git checkout.

Run with the canonical tools directory on `PYTHONPATH`:

```sh
python3 tools/generate_public_value_abi_overlay.py \
  --base-test /absolute/current/NativeRuntimeTests.mm \
  --framework /absolute/UnityFramework \
  --metadata /absolute/global-metadata.dat \
  --output /absolute/private/new-output
```

The observation requests Guid, Color, Discord Activity, InnerNet PlayerId, and
Discord PartySize. It recursively observes the value fields and enums through
public IL2CPP exports. Image, exact outer/nested identity, class flags, and field
declarations are checked against the read-only metadata. Reference fields are
reported as references; no marshaled struct layout is substituted for them.

The report includes public value size, alignment, instance size, layout flags,
blittability, references, enum underlying type, field types and offsets. Unboxed
value offsets are derived from public `field_get_offset` minus public
`object_header_size`, then checked to fit the reported public value size. This
only computes numbers; the observer reads no object payload.

The overlay contains no target invocation, object allocation, value boxing,
payload read/copy, field mutation, lobby, account or network operation. It runs
only on the main thread and requires exactly one loaded UnityFramework matching
the recorded UUID. The parent runner must separately establish the candidate's
file hash and metadata provenance. A successful report is layout evidence, not a
claim that a native thunk or reference-bearing value ABI is supported.

The output schema `ehr.native-abi-layout-facts.v1` can feed the native thunk plan
generator. Activity's reference-bearing managed fields must retain their actual
managed ownership; its native marshaling annotations alone do not permit copying
its payload or declaring an opaque C++ ABI equivalent.

Own synthetic tests exercise recursive declarations, reference exclusion,
scalar self-fields, ambiguous types, unresolved types and safe insertion into an
existing XCTest source. They do not embed game metadata or game code.
