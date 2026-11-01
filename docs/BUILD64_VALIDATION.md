# Build 64: native search and iterator failure handling

The native Find Game request now adds the official EHR `mod` filter after the
original registration helper, only at the pinned search callsite and after
same-key ownership and full game sign-in. See [the search contract](IOS_LOBBY_SEARCH.md).
Global host registration and the
existing protocol/version checks remain unchanged. Website browsing remains
available through **EHR → EHR lobbies**; that site owns its separate login.

## Scrolling crash evidence and repair

An owned build-63 OS report matched the tested helper and Unity images. Its
stack reaches an explicit `abort` in the native iterator error path before
exception borrowing or `il2cpp_raise_exception`. The shared abort block covers
unavailable runtime/export state and failed exception lookup/construction; the
report alone does not distinguish them. Unity's crash handler subsequently
recorded SIGSEGV. The report does not indicate jetsam or a resource exception.

The replacement creates the actual System exception through validated public
IL2CPP APIs and holds a call-local pinned native GC handle. It uses neither
reflection Activator nor a gateway object token, so a full token registry does
not prevent constructing the error. Real errors still reach the original native
exception mechanism after the failed coroutine is retired. No success is
fabricated and no account or permission state is changed.

A separate numeric coroutine diagnostic reports source ID, iterator type hash,
failure phase and primary/cleanup status. It is sampled before cancellation.
A failure-only atomic snapshot survives later startup in
`EHRDiagnostics/last-iterator-failure-v1.json`. It contains no exception text,
room/player/account values or credentials. See [the numeric ABI](IOS_COROUTINE_FAILURE.md).
The underlying role-menu source fault and complete scrolling behavior still
need a new phone reproduction; this repair targets the observed abort path.

## Validation

- All 374 configured regression tests and 14 separate physical-destination tests
  passed on the final implementation.
- The 796 selected sources and 224 resource descriptors compiled with NativeAOT.
  Compiled metadata retains the verified official 8.0.3 release identity.
- All 166 native source pins stayed unchanged during the signed app build.
- Signed Mac checks using the current canonical test source passed: 5,049
  options, 292 active bindings, no unavailable targets, and all four candidate
  binaries unchanged. The source-failure reader bound successfully.
- The actual exception implementation created both expected exception types,
  caught both real raises, returned from neither raise, released two native
  handles and preserved 6,844 gateway roots. The owned capacity fixture also
  exercises a full token map without allocating a gateway token for the error.
- The actual original Guid/filter constructors and closed List API passed five
  owned-object checks: append, duplicate detection, one resulting filter and
  unchanged empty global registration. Roots remained 6,844. No real search,
  account action, host packet change or registration write was performed.
- The managed coroutine fixture passed 287 checks. The persistence fixture
  passed 300, including startup preservation, atomic replacement and refusal
  to follow symlinks/hardlinks. Search fixtures passed 89 checks, and the join
  privacy fixture passed 760. The accepted clipboard code is no longer logged.

The first baseline Mac run used an earlier composed test source and was not
accepted for delivery. The current run includes both new proofs. Xcode exported
them under UUID names; the runner's schema-to-name mapping was updated and the
unchanged exported bytes were normalized to the required proof filenames. The
protected installer rejects missing/failed proofs before any device operation.

Initial protected delivery attempts found the paired devices unreachable. A later
USB connection allowed an in-place build-64 upgrade and launch on the test iPhone.
Its numeric cache confirmed a fresh ownership check, EOS success and full account
completion without a prompt or manual key submission. The player subsequently
scrolled the impostor roles without the earlier Home Screen exit, after a few
seconds of blocked scrolling. Returning to the main menu froze the game, and
Find Game remained empty. These observations motivate [build 65](BUILD65_VALIDATION.md);
they do not establish a complete menu or search repair.

Live Find Game results/joining, renewed role scrolling and wider role/map
coverage remain player acceptance work. This is a development source handoff;
release signing and authorized game-content distribution remain the release
team's responsibility. No game binaries, profiles, keys or raw reports are
included in the public repository.
