# Build 65: settings progress and selectable lobby search

The build-64 phone test scrolled the impostor roles without exiting to the Home
Screen, after a short blocked interval. Returning to the main menu then froze
until restart, and Find Game remained empty. Build 65 addresses visible settings
work and menu lifetime, and separates ordinary search from the EHR-filtered pool.

## Changes

- Settings show **Loading settings…** and attempted-row progress. The native
  indicator reads only the managed builder's own bounded state, yields a frame
  before expensive UI work, passes touches through, and hides on completion,
  cancellation, inactive/error state, account cover or a presented panel.
- Builders yield after at most eight selected-tab row attempts, including hidden,
  header, missing-setting and error paths. Closing or deactivating settings
  invalidates their generation and retires the owned handle before stopping it.
  Incomplete cached tabs rebuild; headers and mode buttons reuse existing UI.
  See [the scheduling and lifetime contract](IOS_SETTINGS_LOADING.md).
- **EHR badge → All lobbies / EHR lobbies** controls the original Find Game
  request. All is the default; refresh Find Game after changing it. EHR retains
  the same-key ownership/full-sign-in predicate and its pinned request filter.
  The choice alone is saved in app preferences. Global registration, game
  version and authentication checks are unchanged. See [search pools](IOS_LOBBY_SEARCH.md).
- Numeric diagnostics include settings progress, main UI tick timestamps/counts
  and search selection/forwarding counters. They contain no room, player,
  response, token or key contents.

## Verification

- All 380 configured regression tests and 14 physical-destination unit tests
  passed. The extracted scheduling/reader/cancellation/cache fixture passed
  1,044 checks; exact reverse adaptation recovers the reviewed build-64 source.
- Actual production UIKit overlay and ownership cover passed 352 checks in a
  fresh disposable simulator, with three inspected screenshots. Portrait and
  landscape loading, spinner visibility, touch pass-through, filter actions,
  safe areas and five dragged badge positions passed. These checks use owned
  collaborators and perform no game, account, physical-device or network action.
- The 796 selected sources and 224 resource descriptors compiled with NativeAOT
  for iOS ARM64. Verified official 8.0.3 release identity remains intact. All 166
  native input pins stayed unchanged through the signed candidate build.
- Signed Mac startup using the current canonical test source passed: 5,049
  options, 292 active bindings, one source load, no unavailable targets and no
  dynamic-code flags. All four tested candidate binaries stayed unchanged.
- The loading export was bound, idle and repeatable. A real worker-thread read
  returned wrong-thread status without changing the subsequent main-thread read.
  The first test used synchronous dispatch, which could execute inline on main;
  its failed worker assertion was corrected to use a dedicated thread and rerun.
- Search started in All mode with schema 2, loaded preferences and zero request
  or selection-change counters. Its original constructor/List probe passed five
  checks at phase 8 with roots 6,846 before/after. The exception probe constructed
  and caught both expected native exception types, released both handles and
  preserved those roots. These probes make no real search or account request.
- The protected installer passed the current candidate's startup, signing,
  profile and proof checks, then found the paired phone unreachable. No build-65
  installation or launch was performed; build 64 remains the last confirmed
  version on the test iPhone.

## Remaining acceptance

The cause of the return-to-menu freeze is not proven. Cancellation and cache
repairs target concrete code defects; they do not establish a phone fix. The
new loading and close/reopen behavior require a player retest.

Live All/EHR results and joining remain unverified. The earlier build always
added an EHR filter; an empty filtered pool does not establish an empty ordinary
pool. Both still depend on server eligibility, compatible advertised rooms,
region and game filters. The separate website directory remains available.

This public update contains source, tests and documentation. It contains no
private signing material, API keys, device identifiers, game binaries/assets,
complete-game package or raw account/device reports. Release signing and
authorized game-content distribution remain the release team's responsibility.
