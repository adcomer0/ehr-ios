# Local signing and tooling inputs

The source has no developer team, app identifier, certificate, profile, or device
identifier defaults. Supply your own `--team-id` and `--bundle-id` to
`tools/build_game_probe.py`, `tools/verify_signing.py`,
`tools/install_protected_iphone.py`, and `tests/runtime/run_native_runtime_test.py`.
`--team-name` optionally asserts the profile's human-readable team name. The
prototype Xcode generator also requires explicit team and bundle arguments.
The official game's bundle identifier is rejected; this app is separate.

All signature/profile expiry, exact device coverage, signing certificate,
platform capability, binary pin, passed Mac startup, and upgrade-only checks
still apply. The runtime runner substitutes the supplied bundle identifier into
its own generated XCTest host and assertions. The optional installer accepts
only the same exact app tested by the supplied Mac proof, and never uninstalls
or imports app data. Physical diagnostics currently require an iPhone 17 Pro Max
(`iPhone18,2`); the device-model gate is intentionally retained.

A valid developer Apple capability is not evidence that the publisher's
backend accepts that developer's Apple client/audience. Apple/EOS authentication
and complete multiplayer behavior are not established by these local checks.

Set `DOTNET` to your .NET executable, pass `--dotnet` where offered, or put
`dotnet` on `PATH`. Standard `DOTNET_CLI_HOME` and `NUGET_PACKAGES` environment
variables are honored without a personal path override. `EHR_UPSTREAM_REPO`
selects the pinned upstream checkout for inventory tools; their fallback is a
sibling `EndlessHostRoles` directory. `--repo`/`--upstream` remain available.
The native-source inventory defaults to this checkout.

Store signing profiles, exact destination-ID files, game apps, generated private
maps, runtime receipts, and test artifacts outside Git. The builder and runtime
runner never fetch or publish game content. Source SHA/UUID/native address pins
remain explicit compatibility gates and must not be replaced with guessed data.

The focused portable-signing, installer, and physical-runner tests use original
synthetic fixtures. A clean clone does not contain the private local game input,
source-composition outputs, signing material, or historical runtime proofs.
A full pipeline run requires materializing the documented pinned inputs locally;
passing source-only tests must not be described as physical gameplay proof.
