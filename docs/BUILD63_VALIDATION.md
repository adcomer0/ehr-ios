# Build 63: EHR directory access and exact iPad delivery

The EHR badge menu now includes **EHR lobbies**, which opens the official
[EHR directory](https://app.gurge44.eu/lobbies) in Apple's in-app Safari view.
The official website owns its sign-in and lobby list. Its feed currently denies
anonymous access, so this version does not offer a fabricated anonymous list.
Choose a lobby on the website, copy its code, tap **Done**, select the same game
region and join through the game's original code entry.

This is separate from the stock public matchmaker. Global mod registration,
server filters, selected managed sources, game account handling and version
checks remain unchanged. Website login is separate from the itch.io key; the
app does not read website content, cookies, credentials or the clipboard.
There is no browser preload, background feed request or automatic room join.
See [browser contracts](IOS_LOBBY_BROWSER.md).

## Validation

- All 361 configured Python regression tests passed. Fourteen additional
  physical-destination/preflight tests passed, including exact iPad models and
  refusal of mismatched, simulated, unpaired or ambiguous destinations.
- The production browser action passed 17 owned presentation checks and strict
  iOS ARM64 compilation without making website requests or reading credentials.
- All 164 native input hashes remained unchanged during the signed app build.
- Signed Mac startup passed with all four candidate binary hashes unchanged,
  5,049 options, 292 active bindings and no unavailable targets. Ownership
  requests, directory traffic and pending account activity remained zero.
- The build uses the same verified NativeAOT library as build 62, including the
  canonical official-release identity and ownership-gated authentication.

The protected installer now accepts an explicitly identified exact physical
`iPad` model as well as `iPhone`; its default iPhone remains unchanged. It still
requires the exact device identifiers, paired physical connection, matching
model/details, development readiness, paid profile coverage, successful Mac
proof, unchanged candidate hashes and installed-version confirmation. Initial
installation never launches, deletes or resets an existing app.

Build 62's remembered-key sign-in and successful official-host join are
[separate phone evidence](BUILD62_VALIDATION.md). Website account authorization,
lobby listing/verification and the directory-to-game flow still need player
testing. This is a development source handoff, not distribution approval or
complete role/map coverage.
