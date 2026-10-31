# Build 59: ownership and EHR website validation

Historical evidence. See [build 62 validation](BUILD62_VALIDATION.md) for the
subsequent live lookup fix and release-identity correction.

Build 59 requires the itch.io credential's account to have a claimed Among Us
entitlement, verified against the official owned-keys API before game login.
The original EOS result and full-account completion remain distinct; neither
replaces the ownership check. A full-window app input cover prevents using the
game before ownership is verified, including the temporary-account route.

## Checks

- All 353 configured Python regression tests passed on the final source.
- The exact ownership transport passed 462 owned checks using a fake URL
  protocol, covering game-ID/schema validation, pagination, response/deadline
  limits, redirects, scope/authentication errors and cancellation.
- The exact provider passed 1,064 owned checks, including saved-key bootstrap,
  fresh normal/silent renewal, main-thread delivery and stale cancellation/key
  generations. Passive preparation performs no Keychain or network actions.
- UI policy passed 558 checks; an actual UIKit run passed 178 assertions. The
  ownership input cover passed a separate 18-assertion simulator run, with actual
  portrait/landscape screenshots reviewed. Every touch rechecks ownership, so
  removal blocks game input before the next refresh timer.
- Five directory tests passed, including 54 compiled owned-fixture assertions.
  They exercise the selected C# implementation with fake game objects and HTTP
  handlers, including escaping, fixed endpoints, response limits, room/host/
  region changes, late response cancellation, mid-lobby opt-in and recovery
  after account renewal. An unbound/denied gate performs no game snapshot reads
  or external requests. Duplicate recovery ticks coalesce.
- The final 796-source, 224-resource manifest compiled for `ios-arm64` with
  NativeAOT. The six callback exclusions and protected `/level` behavior remain
  selected; the source has no dependency on original game DLLs.
- The signed native candidate and matching Mac startup passed with all four
  candidate binaries unchanged, 5,049 options and 292 active bindings. All 162
  native source pins matched. The original SDK marshal/silent-delegate proof
  conserved 7,049 roots before and after.
- The website predicate bound successfully but remained denied at startup;
  directory ticks/status and ownership requests were zero. No credentials were
  read and no real account, login, listing or verification was operated by the
  owned fixtures or signed startup probe.

The native library installs interactive UI only in the actual `EHRNativeGame`
launcher. Loading it in the passive validation host prepares bindings without
saved-key acquisition or interactive account work. There is no production flag
for skipping ownership checks in the itch.io provider.

## Device and service observations

The protected installer upgraded the working test phone from 58 to 59 over
USB and confirmed the installed version. The user's known non-owning itch.io
account received HTTP 200 but the strict ownership parser returned status 5
(response validation failed), with zero SDK logins. This is a failure-path
observation, not yet a successful negative ownership lookup. Build 60 adds
bounded numeric response-structure diagnostics to identify the mismatch; keep
purchases on hold until that result is understood. EHR website acceptance has
not been tested.

The existing real account evidence is build 57's first-profile completion and
later remembered-key login, before ownership was enforced. Those observations
remain historical. Build 59's account/library result and EHR website acceptance
need player observation. No EHR verification code, account identifier, bearer
or room-management secret is included in public evidence.

## Player flow

Use the itch.io key for an account that owns or has claimed Among Us. A purchase
on another store is not shown in that account's itch.io library. A network or
scope failure does not establish missing ownership. Claim an existing bundle or
gift if necessary, then retry with the same owning account.

After completed game sign-in, create an **Online** lobby and enable **List this
lobby on the EHR website** in EHR settings. Wait for the listing-created message,
then enter a fresh `/confirmauth CODE` from the EHR website. The website remains
the authority on whether verification succeeds. The ownership query sends the key to itch.io. Game authentication then passes
the credential to the bundled EOS SDK. The EHR website never receives that
itch.io key: listing creation uses the game's actual EOS bearer and subsequent
updates use a bounded, RAM-only room-management token.

This is a development candidate. It is not App Store/TestFlight approval, a
release signing profile or complete multiplayer/role/map coverage. See
[the user flow](ITCH_SIGN_IN.md), [directory contracts](IOS_LOBBY_DIRECTORY.md)
and [maintainer handoff](MAINTAINER_HANDOFF.md).
