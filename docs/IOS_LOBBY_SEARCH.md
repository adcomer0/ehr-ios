# Native EHR lobby search

Build 64's selected `--lobby-search-map` profile adds the official EHR `mod`
filter to the original **Online → Find Game** request. It follows
[Innersloth's per-request mod filter contract](https://github.com/Innersloth-LLC/AmongUsModdingInformation).
Choose the desired region and game filters. Matching public rooms must exist
in that matchmaker pool; a room listed on the separate EHR website is not
necessarily advertised there. The **EHR lobbies** website browser and original
room-code join remain available. See [website browsing](IOS_LOBBY_BROWSER.md).

The port retains its current global host-only registration and protocol path
for vanilla peers. The adapter changes only the verified native search callsite:
it invokes the original registration helper first, then conditionally appends
EHR's public GUID filter. It does not write the global registration, change host
packets, manufacture game listings or alter version/account checks.

## Runtime contract

The private map pins the exact source image/metadata, static helper, request
iterator callsite, constructor and Guid method identities. Passive preparation
validates methods, fields and the closed List API without constructing a filter
or making a request. Its bound predicate requires the same current credential's
ownership proof and actual full game sign-in.

Only the main-thread request from the pinned return site can append a filter.
Unknown callers and workers retain the original helper behavior. Registration
must remain empty. Existing, duplicate, malformed or foreign mod filters are
checked before mutation; a valid existing EHR filter is reused. The list identity,
registration and account gate are checked again before Add.

Original native constructors and Guid.Parse create the filter payload. Public
runtime fields/boxed values avoid a guessed Guid-by-value ABI; no reflection
Activator or private class offsets are used. All owned roots are released.
Constructor/API failures leave the original request path in charge and produce
only bounded numeric status/phase counters, with no room, player or response
content. No credentials are read by the adapter.

`tools/prepare_lobby_search_map.py --help` describes local map preparation.
Use a legitimate matching framework and metadata outside Git; keep generated
maps and headers private. The builder rejects search without the full source
itch.io profile, preserves existing hook selections and hashes the installed
binding header. Different game versions require fresh mapping and validation.

## Validation scope

The owned fixture exercises original-first ordering, caller/account/worker
guards, repeated requests, duplicate/foreign/malformed entries, constructor/Add
failure containment and root conservation. The signed runtime probe then uses
fresh original filter objects, Guid and the closed List API after source startup.
It performs no actual search, account action, registration write or host change.
The installer requires that proof and passive zero counters before delivery.

Successful live Find Game results and joining still require a player check.
See [build 64 validation](BUILD64_VALIDATION.md). Do not infer live acceptance
from a constructor probe or disable compatibility checks to force a result.
