> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

This is a narrow System.Text.Json source-generation adaptation for pinned EHR
v8.0.3 (ce23f0d050f617a59507e5bb0fbfff751d4b5134). It does not run Main.Load,
network requests, account actions, save writes or gameplay. It changes no
canonical/upstream files. No game assembly or game bytes are included.

tools/prepare_json_overlay.py consumes a current joined full-source .csproj,
validates the upstream Git pin and19 exact existing IL2CPP serializer calls in9
compiled source files, and emits a fresh project plus narrow changed sources.
It keeps all previous source adaptations and compiler inputs. Add the generated
source item paths to the parent's own reproducible full-source join rather than
replacing its project wholesale. Fresh output is required; changed/ambiguous
callsite anchors fail explicitly. The output report records every input/output
source hash. Main/Options/bootstrap adaptations are retained from the input.

EHRPortableJsonContext contains14 explicit root contracts: role colors, string
colors, option save data, UserData, numeric achievement set, achievement upload,
language JsonElements, nested combo dictionaries, developer tags, all four preset
request/response roots and mod news. The generator includes their transitive
property contracts. The existing separate Bard context remains unchanged.

All four original WriteIndented calls use the same source-generated context with
WriteIndented=true. Other calls use default options. No string-enum converter,
property naming policy, case folding, IncludeFields, null suppression or relaxed
JSON parsing was added. Dictionary numeric keys and enum role-color keys preserve
the original serializer contract. Achievement enum values remain numeric. Only
the IL2CPP achievement request's anonymous object is replaced with the exact
named DTO properties userId and achievements, in the same declaration order.
The Mono/Newtonsoft branch is retained verbatim by the targeted transformation.

The independent export ehr_source_json_self_test_v1(uint32_t *output,size_t count)
requires count10. See managed/EHRPortableJsonSelfTest.h for output meanings. It
tests all14 generated contracts without accessing Main, game objects, filesystem,
accounts or network. Return0 means output0..8 passed; require output9==1 separately
to confirm System.Text.Json reflection is disabled under NativeAOT. Exceptions
are contained and return6. This is a pure source JSON gate, not a full plugin or
gameplay availability signal.

Validation: the actual joined replacement-source EHR project compiles with no
errors and publishes an ios-arm64 NativeAOT dylib (58MB), with the self-test export
present. The publish log contains zero JsonSerializer IL2026/IL3050 warnings.
Other dependency/source trimming warnings remain and are not claimed fixed.
The own osx-arm64 NativeAOT executable passes36 exact-source enum/property contract
checks with JSON reflection disabled. A separate JIT reference run passes50
checks, including byte-for-byte parity with original default/indented serializer
behavior and the original anonymous request. It uses extracted enum/property
declarations from actual pinned upstream source; no original game code is copied.
No actual iOS execution or full-source startup result is claimed by this stage.

Evidence:

- Release/json-overlay.json: exact19 callsites and source hashes.
- full-json-release-publish.log: actual full-source ios-arm64 AOT publish.
- reference-release.log: original serializer parity fixture.
- fixture-release-run.log: reflection-disabled NativeAOT fixture.
- FixtureRelease/contracts.json: pinned original enum/property source inputs.

Regenerate the fixture with tests/prepare_json_fixture.py --upstream-root
/path/to/EndlessHostRoles --output /fresh/fixture. Its source-declaration extraction
requires the exact expected property counts, so dropping array properties or
silently changing a DTO shape fails. Generated EHR-derived declarations remain
subject to the upstream source license; no external publication was performed.
