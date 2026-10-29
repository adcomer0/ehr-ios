# Installing on an additional test iPhone

The official game and the separately signed EHR test app have different bundle
identities. Install only the selected EHR bundle; do not uninstall the official
game, import its container or link its account to the test app. Use a temporary
guest in the EHR app while authentication remains unresolved. A separate bundle
does not establish protection from server enforcement or progression problems.

## Pair and identify the physical destination

Identify the intended phone by its user-confirmed name, then preserve its exact
CoreDevice identifier and UDID in a private JSON file outside Git. Confirm its
physical model, existing pairing, transport, tunnel and development-service
readiness. Never substitute another visible phone or a simulator.

Apple supports first-time wireless pairing on iOS 27 or later through Device
Hub's nearby-device flow. Earlier iOS versions need an initial cable pairing.
After pairing, Wi-Fi development requires local connectivity and a working
developer tunnel. Verify it after disconnecting the cable; do not infer wireless
readiness from a USB connection. See [Apple's Device Hub instructions](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub).

## Provisioning and the tested candidate

The candidate's provisioning profile must cover that exact phone and match its
signing certificate, team, bundle and capabilities. Existing coverage for one
phone does not cover a second phone automatically. An Apple account membership
or program-agreement requirement must be resolved through the authorized account
holder before generating a new profile.

If a profile or signature changes, create a new candidate outside Git and repeat
the signed Mac validation. The installer requires the matching four binary
hashes, exact profile/Info hashes, passed full startup and the applicable native
adapter/diagnostic proofs. It cannot reuse the old proof after re-signing.

## Explicit first installation

`tools/install_protected_iphone.py` retains upgrade-only behavior by default.
For an additional phone with no existing copy of the EHR bundle, add
`--initial-install` and an explicit `--expected-product-type`, such as
`iPhone18,2`, to the normal candidate, Mac-proof, private-device-file, identity
and output arguments. The model must match the identified physical destination.

The first-install mode requires the exact EHR bundle to be absent. It refuses
an existing app and cannot be combined with `--launch`. It queries only that
bundle, preserves the normal signing/device/proof checks, installs once, then
confirms the exact installed version. It does not uninstall, read app containers,
change pairing/security, accept game terms or operate an account.

`--preflight-only` can check readiness without installing. For an existing EHR
copy, omit `--initial-install` and provide a strictly newer tested candidate.
