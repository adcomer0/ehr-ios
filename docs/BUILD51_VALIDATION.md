# Development build 51 validation

Validated on 2026-10-28 against the pinned iPhoneOS 2026.9.29 (3) framework,
Unity 2022.3.62f3 and EHR v8.0.3. The 796 selected C# inputs, 224-resource catalog
and managed build-48 NativeAOT library remain unchanged. Changes are in native
diagnostics and their build/test/delivery integration. No runtime JIT is used.

## Why this candidate exists

Build 49 reached a real solo game. Build 50 still failed Apple/EOS sign-in and
disconnected its host after a vanilla peer joined. Its last credential enum came
from a later fallback and its numeric cache omitted the disconnect reason.
Build 51 preserves a bounded authentication-event history and records the
original scalar disconnect reason. These additions diagnose the failures; they
do not claim to repair authentication or multiplayer.

## Passed

- 294 owned regression tests, with explicitly configured local historical
  source-pipeline fixtures where required. This is not a clean-clone claim.
- Strict ARM64 iOS compilation. Synthetic native forwarding fixtures preserve
  each original argument/call and restore nested thread-local scopes across
  C++ and Objective-C exceptions. The credential observer uses only a pinned
  public scalar getter; it never reads token strings, client data or options.
- The actual production-thunk fixture passed 57 disconnect-recorder checks,
  including signed scalar values, unavailable/invalid metadata and arguments,
  unchanged dispatch/original calls, root balance and worker snapshots.
- Signed iOS-on-Mac full startup: 5,049 options and 292 permitted bindings,
  with the six account/consent exclusions retained. Authentication preparation
  succeeded and production authentication-event counters stayed zero.
- Actual-runtime isolated authentication-recorder proof: 87 checks, bounded
  32-event storage, preservation of the middle Apple enum before later fallback,
  and redaction of unavailable scalar values. No real authentication, account,
  credential payload, network or executable-write operation was performed.
- The game-start adapter, 1,024-retained-carrier, touch/action, muted audio,
  resource-loader and failure-cleanup probes passed. All four source-candidate
  executables remained unchanged by the signed runtime test.

The protected installer requires the matching startup, bounded isolated proof,
exact-device/profile coverage and four tested binary pins. Its Mac proof also
requires zero observed disconnect/authentication activity. The build-49-to-50
phone upgrade was verified over the local-network developer connection, followed
by a confirmed build-50-to-51 wireless upgrade. Phone authentication and peer-join
observations for the new build-51 diagnostics are still pending.

## Limits

These diagnostics collect fixed numeric fields only. They do not decode a live
identity token or establish which provider configuration rejected it. API-version
fields are labelled as static declarations, not live observations. Asynchronous
EOS callbacks have no object/account correlation identifier; event order alone
must not be treated as an exact request match during overlapping attempts.

Authentication, normal multiplayer rounds, meetings, all roles, account/progression
safety and protection from bans remain unresolved or unverified. The delayed
post-disconnect name restore is a known separate cleanup defect. See
[known issues](KNOWN_ISSUES.md) and [authentication diagnostics](AUTH_HANDOFF_DIAGNOSTICS.md).
