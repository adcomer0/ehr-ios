# Native EHR lobby search

The selected `--lobby-search-map` profile uses the original
**Online → Find Game** request. The build-65 candidate adds an explicit selector
in the **EHR badge** panel:

- **All lobbies** is the default. It keeps the game's original search without
  adding EHR's mod filter. Normal region, mode, map, language and server
  eligibility rules still apply; this is not a search across every MCI mod.
- **EHR lobbies** adds the official EHR `mod` filter for GUID-registered EHR
  all-client lobbies when ownership and full game sign-in are verified. EHR
  host-only lobbies without that registration belong to the ordinary pool and
  are not guaranteed to appear in this filtered pool.

After changing the selector, return to Find Game and refresh it. Changing the
choice does not start a request or refresh automatically. The app saves only
the choice, an integer 0 or 1, in its own preferences. Missing or malformed
preferences default to All.

Build 64 always added the EHR filter; an empty list in that build is not proof
that the ordinary pool is empty. The EHR filter follows
[Innersloth's per-request mod filter contract](https://github.com/Innersloth-LLC/AmongUsModdingInformation).
Matching public rooms must exist in the chosen matchmaker pool; a room listed
on the separate EHR website is not necessarily advertised there. The
**EHR lobbies** website browser and original
room-code join remain available as a separate action. See
[website browsing](IOS_LOBBY_BROWSER.md).

The port retains its current global host-only registration and protocol path
for vanilla peers. The adapter changes only the verified native search callsite:
it invokes the original registration helper first, then conditionally appends
EHR's public GUID filter. It does not write the global registration, change host
packets, manufacture game listings or alter version/account checks.

## Runtime contract

The private map pins the exact source image/metadata, static helper, request
iterator callsite, constructor and Guid method identities. Passive preparation
validates methods, fields and the closed List API and loads only the saved
search choice, without constructing a filter or making a request. Its bound
predicate requires the same current credential's ownership proof and actual
full game sign-in.

All mode returns after the original helper. Only EHR mode on the main-thread
request from the pinned return site can append a filter.
Unknown callers and workers retain the original helper behavior. Registration
must remain empty. Existing, duplicate, malformed or foreign mod filters are
checked before mutation; a valid existing EHR filter is reused. The list identity,
registration, selection and account gate are checked again before Add.

Original native constructors and Guid.Parse create the filter payload. Public
runtime fields/boxed values avoid a guessed Guid-by-value ABI; no reflection
Activator or private class offsets are used. All owned roots are released.
Constructor/API failures leave the original request path in charge and produce
only bounded numeric status/phase counters, with no room, player or response
content. No credentials are read by the adapter.

The numeric snapshot uses schema 2 and includes the current choice, whether it
has been loaded, choice-change count and All-mode forwards alongside the
existing call, apply, failure and phase counters. The worker getter reads only
owned atomics and the fixed bundle flag; it does not load preferences or query
an account or game object.

`tools/prepare_lobby_search_map.py --help` describes local map preparation.
Use a legitimate matching framework and metadata outside Git; keep generated
maps and headers private. The builder rejects search without the full source
itch.io profile, preserves existing hook selections and hashes the installed
binding header. Different game versions require fresh mapping and validation.

## Validation scope

The owned fixture exercises original-first ordering, caller/account/worker
guards, repeated requests, duplicate/foreign/malformed entries, constructor/Add
failure containment, All/EHR switching, strict preference values and root
conservation. The signed runtime probe uses
fresh original filter objects, Guid and the closed List API after source startup.
It performs no actual search, account action, registration write or host change.
The installer requires that five-check, phase-8 proof and passive zero counters
before delivery. Either saved selection is permitted; selection must be an
integer 0 or 1 and already loaded, with zero changes or search forwards during
the passive probe.

Successful live Find Game results and joining with the selector still require
a player check. The All default is not yet proof that the observed empty screen
is fixed. The version path remains unchanged. See
[build 64 validation](BUILD64_VALIDATION.md) for the earlier construction proof.
Do not infer live acceptance
from a constructor probe or disable compatibility checks to force a result.
