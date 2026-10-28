> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Optional update lookup and iOS matchmaking

`prepare_ios_update_lookup.py` runs after the signed-updater source adaptation.
It checks the selected source hash and changes only two assignments inside the
reviewed GitHub release-check coroutine: network failure and response failure
set `IsBroken` only when `OperatingSystem.IsIOS()` is false. Both errors remain
logged, and release/version comparison remains unchanged. New iOS processes
start with the original static `IsBroken` default of false.

In pinned EHR8.0.3, every `ModUpdater.IsBroken = true` producer belongs to the
remote update lookup. The original third producer rejects a missing desktop DLL
asset; the earlier signed-updater adaptation already removes it. This field is
not a native binding, game-version, authentication, account or source-startup
readiness result. The unrelated BedWars `IsBroken` field is not adapted.

The added `IsIOS()` reads EHR's cached readonly platform Boolean. The selected
`ModUpdater.Start_Prefix` already calls the same class's `IsAndroid()` before
starting its private release-check coroutine, initializing all cached platform
fields on that main callback. This is the coroutine's sole callsite. Separately,
`Main.Load` calls `IsAndroid()` before returning, and source startup finishes
`plugin.Load` before `BindRequested` activates callbacks. The failure guard adds
no background-thread Unity platform access and does not introduce a different
platform detector.

The two active consequences are hiding `FindGameButton` in
`MMOnlineManager.Start` and forcing a host's public lobby private in the
`PlayerControl` update loop. The source's commented-out `MakePublic` patch and
the commented GameStartManager UI block are inactive. All consumers are retained
byte-for-byte. Forced-update and `AllowPublicRoom` flags, diagnostics, existing
critical `IsBroken` state, account-policy exclusions, native checks, version
compatibility, required host-only +25 registration and source readiness gates
are preserved. Desktop and Android error behavior stays unchanged.

Use `--project CURRENT.csproj --expected-updater-sha256 SELECTED_SHA --output
FRESH_OUTSIDE_GIT`. The helper rewrites exactly one ModUpdater Compile item and
preserves all other selected source and resource entries. Its current reviewed
input hash is `36bbe71b2eef1d82fe5791d3ee278d2cfcecf4bcb972cb3c51c329b8da204c94`.

This fixes a concrete full-source coupling between optional release availability
and matchmaking UI. It does not diagnose the older Bait-only preview24.1 empty
finder. No authenticated server discovery, vanilla join, physical finder or
account preservation result follows from compilation or own fixture tests.

The six unit checks include compiled failure branches and the actual source
ordering audit. Set `EHR_SIGNED_UPDATER_TEST_INPUT` to the reviewed signed updater
and `EHR_PLATFORM_TEST_INPUT` to the selected OperatingSystem.cs for the two
actual-source checks. Those checks skip without explicit generated inputs.
