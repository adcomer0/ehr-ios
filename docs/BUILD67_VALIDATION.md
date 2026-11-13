# Build 67: iOS 27 scene lifecycle launch repair

The existing build 66 exited before the logo after the test phone moved to
iOS 27.2.1. Three matching reports reached UIKit's scene-adoption evaluation.
The launcher linked SDK 27.1 without a scene manifest. Certificate, profile,
package architecture and library resolution checks passed. This is separate
from the older role-menu allocation pressure.

Build 67 adds an original single-scene host around Unity's existing application
delegate and rendering window. Window/root identity, bounded late attachment,
visibility intent and lifecycle forwarding are preserved. See [the host contract](IOS_SCENE_HOST.md).
Managed source, release identity, game content, account provider and saved-login
storage are unchanged.

## Checks completed

- All 392 configured regression tests passed. The separate physical-destination
  unit tests also passed.
- The final adapter passed four unit tests and eight owned-collaborator cases,
  totaling 142 assertions for initializer/active/attachment ordering, exceptions,
  early-event recovery and reconnect. Its UIKit fixture compiles for iOS and
  Simulator. Earlier actual iOS 27.0 simulator runs passed 55 visible and 56 hidden
  checks on an earlier revision; those are supporting window/lifecycle evidence,
  not a final-order runtime proof. Low disk space prevented another simulator boot.
- Strict iOS ARM64 compilation passed with warnings treated as errors.
- The signed candidate compiled with all 168 native input hashes unchanged.
  The existing managed NativeAOT library is reused; 796 source/224 resource
  selections and the official EHR release identity remain unchanged.
- Six isolated passive-host tests and 14 physical-destination unit tests passed.
  The runtime test copy uses a separate executable name to suppress interactive
  overlay/bootstrap work, without adding a production authentication bypass.

- Final signed Mac startup passed with one original scene window/root attached,
  5,049 options, 292 bindings, one source load, no unavailable targets and no
  dynamic-code flags. All four candidate binaries stayed unchanged. Passive
  validation recorded zero ownership checks, prompts, submissions or SDK logins.
- The original initializer runs in the first scene foreground phase, before
  activation. Testing only late initialization exposed Unity's keyboard-order
  assertion on Mac; no assertion or private engine-ready byte was modified.
  The initial test target also needed explicit UIKit linkage. One successful
  testcase run then lost its result import to disk exhaustion. Only completed
  build caches and incomplete importer scratch were cleared; a fresh run with
  verbose test diagnostics disabled completed successfully and supplied the
  accepted proof.
- The existing phone app upgraded from 66 to 67 over Wi-Fi. Exact version,
  normal foreground launch and the same process still running on a delayed check
  were confirmed. Its numeric cache showed complete source startup, no iterator
  callback failures and completed UI ticks. The remembered key passed ownership
  verification and actual EOS/full game-account completion without a prompt or
  manual submission. No reset, uninstall, pairing or security change occurred.

Broader role, lobby-search and multiplayer acceptance remain outside this
launch repair. The phone observation establishes startup and remembered login.

The public handoff contains source and owned tests. Raw phone reports, local
maps, device identifiers, signing material, keys and game binaries remain
outside Git.
