# Build 62: release identity and ownership validation

This development candidate combines the ownership-gated itch.io login and EHR
website integration with a correction to the upstream release identity.
It is not a distribution approval or complete gameplay certification.

## Live ownership and account evidence

The exact native helper first returned a correct negative lookup on Mac for a
known non-owning account: HTTP 200, no entitlement. The official API returned
an empty object for `owned_keys`, rather than an array. The parser now accepts
only that exact empty object as a negative result after valid pagination; it
cannot establish ownership. Nonempty objects and malformed rows still fail.

After the player purchased Among Us, build 61 on iPhone returned HTTP 200 and
verified one claimed Among Us record. A later bounded numeric cache showed one
SDK login, actual EOS success (0), full game-account completion and the directory
gate allowed. This separates the Mac negative result from the iPhone positive
and account observations. No key, account ID or raw response is public.

## EHR host compatibility

The official 8.0.3 mod artifact advertises `ce23f0d(main)`; the previous iOS build
advertised `ce23f0d(HEAD)` from a detached upstream checkout. Version, fork and
source commit match, but EHR correctly compares the full tag. The build tool now
uses the reviewed release's canonical GitInfo branch for that exact clean
source pin. It checks the actual compiled assembly's version, fork, branch,
short commit and full SHA before accepting a build. The comparator is unchanged.
See [release identity provenance](UPSTREAM_RELEASE_IDENTITY.md).

## Remembered login

A verified saved-key attempt can wait for normal native login capture for at
most 120 seconds when no form, capture or SDK activity exists. A normal capture
or explicit Account sign-in resumes that same attempt. Timers do not retry game
login. Cancel, Clear, new input, expiry and capture failure retire the wait;
expiry retains only the independent ownership result. Manual key entry and
actual SDK/full-account requirements remain unchanged.

## Build and device validation

- All 359 configured Python regression tests passed. The ownership transport
  passed 3,761 owned checks; the provider passed 1,477. Six new release-identity
  tests include real GitInfo compilation from a detached fixture with the same
  cache, plus rejection of incorrect or missing identity fields.
- The unchanged 796-source, 224-resource manifest compiled for `ios-arm64`.
  The actual intermediate assembly contains version `8.0.3`, fork `EHR`, branch
  `main`, commit `ce23f0d` and the exact pinned full SHA. The metadata reader
  does not execute the inspected assembly.
- All 162 native source pins remained unchanged during the signed app build.
  Signed Mac startup passed with all four candidate binaries unchanged,
  5,049 options, 292 active bindings and no unavailable targets.
- Passive startup made no ownership requests or account actions. Ownership,
  directory access and deferred-login state were false; countdown and directory
  ticks were zero. The directory predicate was compiled and bound.
- The protected installer upgraded the existing test iPhone from 61 to 62 over
  USB, confirmed its installed version, launched normally and observed the
  process running. It did not uninstall or reset the app.
- The post-launch numeric cache verified one ownership check, one genuine SDK
  login, EOS success (0), full game-account completion and the directory gate
  allowed. There were zero prompts or manual key submissions; no form was
  visible. This establishes a remembered-key login on build 62 after upgrade.

Live joining of another official host and EHR website acceptance still require
player tests.
Existing first-profile, guest-migration and wider role/map limits are described
in [known issues](KNOWN_ISSUES.md) and [the sign-in flow](ITCH_SIGN_IN.md).

The public source excludes game binaries/assets, private credentials, signing
material, device identifiers and raw diagnostics. Build locally with legitimate
game inputs and your own provisioning. See [maintainer handoff](MAINTAINER_HANDOFF.md).
