> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Actual runtime binding audit

`tools/generate_runtime_binding_audit.py` produces a private standalone XCTest
overlay from an exact, pinned native selector map. The generic audit source and
synthetic fixtures belong in this repository. The generated target facts,
overlay, and runtime attachments belong outside Git.

The audit resolves each declaring class through the gateway, obtains exact
runtime parameter and return spellings with `class_type_name`, and finds the
method with its complete signature and static flag. Nested lookup uses the
metadata-derived outer namespace and nested class chain; it never guesses a
signature by replacing separators. Closed generics use actual managed type
construction, SZ arrays use `vector_class`, and byrefs append the explicit
IL2CPP byref suffix to the resolved base name.

Because `find_method` may search base classes, the audit independently checks
the real reflection `DeclaringType`. It then calls the version-pinned native
association validator with the candidate RVA. Temporary reflection/type roots
are released and release statuses are recorded. Metadata discovery, the
reflection declaring-type getter, and closed-type construction run; none of
the audited target methods run. Unbound coroutine selectors remain excluded.

## Generate and run

Start with a map from `tools/map_harmony_native_targets.py` and the exact original
framework and metadata that match the map's SHA-256, size, and UUID pins. The
candidate used for execution must contain the matching gateway and its own
generated signed-framework association pins. A new map is required when the
original inputs change.

```sh
ehr_source=/path/to/ehr-ios
ehr_reports=/path/to/local-reports
ehr_original='/Applications/Among Us.app/Wrapper/AmongUs.app'

python3 "$ehr_source/tools/generate_runtime_binding_audit.py" \
  --source-root "$ehr_source" \
  --base-test "$ehr_source/tests/runtime/NativeRuntimeTests.mm" \
  --map "$ehr_reports/harmony-native-targets-expanded-relocation.local.json" \
  --framework "$ehr_original/Frameworks/UnityFramework.framework/UnityFramework" \
  --metadata "$ehr_original/Data/Managed/Metadata/global-metadata.dat" \
  --output "$ehr_reports/runtime-binding-audit-new-overlay"
```

The output directory must be new and outside all Git checkouts and input trees.
Generation opens framework and metadata read-only, validates their pins, checks
input file identity/size/modification time again before writing, and refuses
to replace earlier evidence. It produces:

- `binding-audit-facts.local.json`: dependency-ordered type shapes and exact candidates.
- `NativeRuntimeBindingAudit.local.mm`: the current own test source plus the audit.
- `generation-manifest.local.json`: input/source hashes, counts, and overlay hash.

Run the existing normal signed iOS-on-Mac XCTest runner with the generated
overlay. Supply the already built candidate and the installed development
identity through these task-specific variables:

```sh
python3 "$ehr_source/tests/runtime/run_native_runtime_test.py" \
  --source-root "$ehr_source" \
  --candidate-app "$ehr_candidate_app" \
  --test-source "$ehr_reports/runtime-binding-audit-new-overlay/NativeRuntimeBindingAudit.local.mm" \
  --output-root /path/to/local-builds/RuntimeBindingAuditNew \
  --team-id YOURTEAMID \
  --sign-identity "$ehr_sign_identity"
```

The runner creates a separate host copy. Inspect `runtime-test-summary.json`
and `Attachments/EHRNativeXCTestProof.json`. The proof's
`allHarmonyRuntimeBindings` entry must report success, matching expected and
observed counts, no failures, successful temporary-root releases, and zero
audited target invocations. This gate proves metadata ownership and native
entry association for those pinned inputs. Hook execution, replacement ABI,
coroutine state-machine association, and multiplayer behavior require their
own tests.

## Recorded execution

On 2026-10-28, normal signed Candidate16 XCTest passed with 296/296 ordinary
native candidates and 204/204 type shapes resolved, including six closed
generic requests, three vector classes, and three explicit byref markers.
All 296 reflection owner checks passed; there were no failures and all
temporary roots were released. Both unbound coroutine selectors were excluded.
The source candidate remained unchanged and no audited target was invoked.

Private evidence:

```text
/path/to/local-reports/runtime-binding-audit16-overlay/generation-manifest.local.json
/path/to/local-builds/RuntimeBindingAudit16/runtime-test-summary.json
/path/to/local-builds/RuntimeBindingAudit16/Attachments/EHRNativeXCTestProof.json
```

The executed overlay SHA-256 was
`0e147022a1d3c6e9f1f0e73e4a85fbfcbfc2f2eb4ed22501cf48949540fef0cf`.

## Synthetic checks

```sh
python3 -m unittest discover -s tests -p test_runtime_binding_audit.py -v
```

Six tests use original synthetic metadata and Mach-O fixtures. They cover
nested/generic/vector dependencies, exact arity and byref handling, ordinary
candidate selection and coroutine exclusion, owner/pin/alignment/schema
rejection, read-only generation, exclusive outputs, and the Git output guard.
