# Metadata-only candidate for the disabled retry guard

Use a fresh local candidate with the reviewed full source image and existing
full native/iterator/class/EOS input maps. No new managed source or AOT publish
is needed for this native-only addition. Keep every game binary, generated map,
signing profile, device pin and runtime result outside Git.

Generate the two-selector report using the exact source inputs already accepted
by the normal mapper. The paths below are local variables, not committed inputs:

```sh
python3 tools/auth_retry_hook_inputs.py --selectors-output "$AUTH_SELECTORS"
python3 tools/map_harmony_native_targets.py \
  --framework "$SOURCE_FRAMEWORK" --metadata "$SOURCE_METADATA" \
  --selectors "$AUTH_SELECTORS" --pins "$SOURCE_PINS" \
  --output "$AUTH_RETRY_MAP"
```

Add `--auth-retry-guard-map "$AUTH_RETRY_MAP"` and the existing
`--eos-login-map "$EOS_MAP"` to the full builder command. Supply your own explicit
`--team-id`, `--bundle-id`, `--profile`, `--identity`, exact private
`--destination-id-file`, new output directory and build number. Keep the normal
source catalog, typed thunks, source hash/UUID pins and target IDs unchanged.
**Omit `--full-source-autoload` for this metadata-only candidate.**

Only one separate retry entry is installed. The failure-method candidate is
validated, not hooked. Strict relocation, binding-table inspection, profile and
signature checks still run. The final patch manifest produces
`EHRAuthRetryBinding.generated.h`; the build manifest pins this header and map.
The compiled guard and Info.plist both start disabled. Startup calls neither
Prepare nor SetEnabled, and status publication reads only its fixed own counters.

Run the standalone metadata-only XCTest source through the normal Mac runner:

```sh
python3 tests/runtime/run_native_runtime_test.py \
  --source-root "$SOURCE_CHECKOUT" --candidate-app "$CANDIDATE_APP" \
  --test-source tests/runtime/AuthRetryMetadataRuntimeTests.mm \
  --output-root "$NEW_PRIVATE_TEST_OUTPUT" \
  --team-id "$TEAM_ID" --bundle-id "$APP_BUNDLE_ID" \
  --sign-identity "$SIGN_IDENTITY"
```

The runner copies the own proof include and preserves its usual signing,
profile, exact destination and four-binary checks. No device destination is
requested. The test waits for actual IL2CPP readiness, rejects worker Prepare,
then calls Prepare twice on the main thread. It does not bind/load Main, activate
the guard, fetch a singleton, inspect an account or call native auth targets.
The proof labels its zero request/account counts as operations initiated by the
test, rather than claiming to observe every action of the base application.

Require XCTest success, unchanged candidate binaries, and
`Attachments/EHRAuthRetryMetadataProof.json` with both passes true, status 0,
`enabled=false`, zero failure-handler entries/completions, worker status
WRONG_THREAD, and `guardActivationAttempted=false`. A missing export, unresolved
closed field type, unsupported initializer or failed association is a failed
gate. Leave the guard disabled and preserve that failure evidence.

No phone installation, activation, Apple sign-in or account action belongs to
this procedure. An actual metadata pass still requires independent review and
a separately authorized failure-UI test before enabling. It does not establish
EOS acceptance of the app's Apple client.


## Controlled development opt-in after review

The default remains OFF. After the metadata gate and independent review, an
explicit development build may add `--enable-auth-retry-guard` alongside the
exact guard map. Missing guard/EOS/full-profile inputs are rejected before
source inspection. The builder writes
`EHRAuthRetryGuardActivationRequested=true` and
`auth_retry_guard_activation_requested=true`. The older `Enabled`/`enabled`
Info/manifest fields remain false to describe the initial compiled native state;
they do not claim runtime activation.

The main-thread binder calls `EHRAuthRetryGuardStart(requested)` after native
initialization and EOS observer preparation. A true request first calls Prepare,
and only its success permits SetEnabled(1). A false request does neither.
Preparation failure leaves the initial guard disabled and is recorded without
starting login or altering unrelated source binding. `CopyStatus` reports the
request, preparation status, enable status and actual enabled state separately.

Use the full startup Mac proof for an opted-in build. It must report
`authRetryGuard.startupRequested=true`, `preparedStatus=0`,
`startupPrepareStatus=0`, `startupEnableStatus=0`, actual `enabled=true`, and
zero failure-handler entries/completions before any user interaction. The
protected installer refuses a requested guard unless this actual matching Mac
startup evidence is present and ready. Its normal signing, exact-device,
four-binary, version and upgrade-only gates still apply.

Only the user's later authorized sign-in attempt can validate the actual failure
UI and preserved native TempAccount path. The test/binder itself sends no auth
request. The retry guard still does not fix or bypass EOS 7000.
