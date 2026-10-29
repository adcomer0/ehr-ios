# Passive Apple-to-EOS handoff diagnostics

The optional native observer records the order of the existing Apple and EOS
authentication callbacks. It does not authenticate a player, replace credentials,
change an audience or nonce, create or link accounts, grant permissions, or make
the backend accept a rejected request. Peer lobby disconnects are investigated
separately; this trace does not establish their cause.

The implementation is [EHRAuthHandoffDiagnostics.mm](../native/EHRAuthHandoffDiagnostics.mm).
Build selection is explicit through `--auth-handoff-map`, requires the full-source
profile, passive EOS result observer and platform sign-in capabilities, and sets
`EHRAuthHandoffDiagnosticsCompiled`. It is absent by default. Original input maps,
generated binding headers, signed apps and device traces stay outside Git.

## What is observed

Three pre-sign entry forwarders observe:

1. `EOSManager.OnGetCredentials(ICredential)`: entry and ordinary return only.
   The credential argument is forwarded without inspection.
2. `ConnectInterface.Login(ref LoginOptions, object, OnLoginCallback)`: entry and
   ordinary return, with a thread-local scope around the original call. Options,
   `ClientData` and callback objects are not inspected.
3. `CredentialsInternal.Set(ref Credentials)`: inside a main-thread login scope,
   the exact pinned public `Credentials.get_Type` scalar getter is called. The
   original marshaler then receives its unchanged arguments.

The existing positive Apple completion observer supplies the Apple-success
event. The existing pinned public EOS `ResultCode` observer supplies normal and
silent result events. See [Apple observation](APPLE_AUTH_DIAGNOSTICS.md) and
[EOS result observation](EOS_LOGIN_DIAGNOSTICS.md).

Each forwarder calls its original exactly once with unchanged receiver,
arguments and hidden `MethodInfo`. Original exceptions propagate; a missing
return event can therefore indicate an exception or an unfinished call. Nested
login scopes restore their previous depth and serial, including during exception
unwinding. Optional scalar-observation failures record an unavailable status and
leave original forwarding intact.

Preparation runs on the main thread and resolves exact public metadata
signatures, native RVAs and the getter's immutable metadata borrow through the
existing hash/UUID association checks. It does not invoke authentication,
construct game objects, run class initializers, or inspect credentials. The
reviewed getter is a scalar leaf with no calls or allocations.
`LoginOptions.get_Credentials` is deliberately not used: its mixed-reference
nullable result would require a separate safe ownership/ABI design.

## Snapshot schema 2

`EHRAuthHandoffDiagnosticsCopyStatus()` returns `schemaVersion: 2`, aggregate
counters and an `events` array containing the most recent **32** events, ordered
oldest to newest. `eventCapacity`, `eventCount` and `eventOverwrites` expose the
bound and overwritten history. Counters saturate at their fixed limits; the
snapshot is not an unbounded audit log.

Every event contains exactly these six numeric fields:

| Field | Meaning |
| --- | --- |
| `sequence` | Process-local occurrence order shared by these handoff phases. |
| `monotonicNs` | Monotonic clock nanoseconds, sampled under the sequence lock; zero means unavailable. Equal timestamps are permitted. |
| `phase` | Phase number from the table below. |
| `status` | Observation status; zero means the scalar observation was available. |
| `scalarValue` | Credential enum or EOS result for scalar phases; otherwise zero. Unavailable observations also use zero. |
| `loginScopeSerial` | Generated process-local serial grouping synchronous login entry/type/return events; zero for phases outside that scope. |

| Phase | Event |
| --- | --- |
| 0 | Apple success callback observed |
| 1 | Managed `OnGetCredentials` entered |
| 2 | Managed `OnGetCredentials` returned |
| 3 | EOS Connect login entered |
| 4 | Credential-type observation |
| 5 | EOS Connect login returned |
| 6 | Normal EOS result observation |
| 7 | Silent EOS result observation |

A phase-4 event with `status: 0, scalarValue: 11` observes `AppleIdToken`.
A phase-6 event with `status: 0, scalarValue: 7000` observes a backend rejection;
zero observation status does not mean backend authentication succeeded.
When observation status is nonzero, `scalarValue: 0` is an unknown placeholder,
not a successful EOS result or a known credential type.

The generated scope serial is not an object address, gateway token, account ID
or credential identifier. It groups only synchronous calls. Sequence and timing
alone cannot prove which asynchronous result belongs to a request when multiple
requests overlap. No token bytes, credential strings, nonce values, callback
payloads, account/device identifiers, URLs or arbitrary error text are recorded.

Writers and snapshots share one bounded-state mutex. Timestamp sampling occurs
under that lock so concurrent publishers cannot invert timestamp assignment.
Foundation containers are created after copying the state; worker snapshots
make no game/runtime/metadata calls.

## Static declarations and live evidence

`declaredCredentialsApiVersionStatic: 1` and
`declaredLoginApiVersionStatic: 2` describe constants verified in the pinned
original marshaling code. They are **not live API-version field observations**.
The original code also selects the Apple identity-token getter, UTF-8 converts
its byte array, and selects enum 11. Its explicit request nonce/state are null.
This audit provides no basis for substituting an authorization code or changing
nonce handling speculatively.

In build 50, the last normal EOS result was 7000 at sequence 10, while the last
credential type was 10 (`DeviceidAccessToken`) at sequence 12 during a later
fallback. The last-only snapshot had overwritten the earlier type observation.
It therefore **cannot establish that the Apple request used the wrong type**.
Schema 2 preserves the intermediate type event while it remains within the
32-event history. It cannot reconstruct missing build-50 events retroactively.

### Observed phone trace in build 51

The build-51 phone trace retains all 13 events with no ring overwrites,
observation faults, unknown scalar observations or out-of-scope marshal calls:

| Sequence | Observation |
| --- | --- |
| 1–3 | Initial guest login, scope 1, credential type 10. |
| 4 | One positive Apple authorization callback. |
| 5–6 | One managed `OnGetCredentials` entry and ordinary return. |
| 7–9 | Connect login, scope 2, credential type **11 (`AppleIdToken`)**, ordinary return. |
| 10 | One normal EOS result: **7000**, observation status 0. |
| 11–13 | Later fallback login, scope 3, credential type 10, ordinary return. |

This confirms that the observed Apple-path request selected the correct
credential enum. The later device-ID fallback explains the last-value 10; it is
not evidence of a wrong Apple credential type. The managed callback completed
and the Connect request began about 0.625 seconds after the Apple completion;
the normal EOS result followed about 0.378 seconds later. The trace does not
show a long client handoff delay.

A read-only comparison of nine relevant build-51 authentication method bodies
also matches the original game, excluding only the three expected observer
entry branches. This includes the identity-token decoder, UTF-8 handoff,
credential-type getter and original EOS marshalers. API-version constants remain
the statically verified 1 and 2; they have not become live observations.

No concrete local implementation defect is established by this evidence.
Missing managed callback delivery and wrong credential-enum selection are not
supported explanations for this attempt. The trace does not inspect the token
payload or prove its issuance time, freshness, signature, audience, nonce, or
acceptance by the configured provider. Those validation questions remain open;
correct enum selection alone cannot distinguish them. No token, audience, nonce
or permission substitution is justified by the result.

## Validation limits

The owned forwarding fixture covers unchanged arguments/original-once behavior,
unavailable metadata, scalar getter failures, nested scopes, C++/Objective-C
exception unwinding and concurrent numeric snapshots. Ring tests retain an
intermediate type 11 through EOS 7000 and a later type 10, then verify wraparound,
unknown-value redaction and the fixed numeric shape.

`EHRAuthHandoffDiagnosticsSelfTest()` uses isolated recorder state and has **87
checks**. Its schema remains `ehr.auth-handoff-proof.v1`; success also requires
prepared metadata. It reports `isolatedRecorder: true` and explicit negative
flags for real authentication, credential reads, network operations and runtime
executable writes. It invokes no original authentication method and does not
modify the production event history.

```sh
python3 -m unittest discover -s tests -p 'test_auth_handoff_*.py' -v
```

Focused owned tests, strict iOS ARM64 compilation and signed build-51 Mac runtime
validation passed. The actual isolated recorder probe passed 87 checks and all
four candidate executables remained unchanged. Build 51 was then confirmed as
a wireless phone upgrade from 50. Its observed phone trace above still ends in
EOS 7000, so authentication remains unsuccessful. Compilation, metadata
readiness and isolated fixtures do not prove account progression safety.

## Legitimate publisher configuration check

EOS 7000 is `EOS_Connect_ExternalTokenValidationFailed`; it does not uniquely
identify an audience, expiry, nonce, serialization or provider problem. Epic
lists provider-configuration failure separately as 7007. That distinction does
not establish that every configuration mismatch must return 7007.
[Epic SDK error codes](https://dev.epicgames.com/docs/epic-online-services/sdk-error-codes?lang=zh-CN)

Apple uses the native app's bundle identifier as its client identifier. The
verifier must validate the identity token's audience against the intended client
identifier, together with signature, issuer, expiry and nonce requirements.
Local signing/capability success alone cannot establish backend acceptance.
[Apple native client identity](https://developer.apple.com/documentation/technotes/tn3159-migrating-sign-in-with-apple-users-for-an-app-transfer),
[Apple verification](https://developer.apple.com/documentation/signinwithapple/verifying-a-user)

The concrete question for the publisher's authorized backend administrator is:

> Is `${NATIVE_BUNDLE_ID}` an accepted native Apple client for `${EOS_PRODUCT}`,
> enabled in `${EOS_SANDBOX}` and used by `${EOS_DEPLOYMENT}`, under the intended
> Apple developer relationship: **yes or no**? If no, what authorized app
> identity/configuration should this distribution use? If yes, can the owner or
> Epic support provide a redacted validation-failure category for this attempt?

Epic configures external identity providers for a product and enables them per
sandbox. Request a categorical configuration result or sanitized support
correlation, not private keys, client secrets, tokens or user identities.
[Epic identity-provider management](https://dev.epicgames.com/docs/epic-online-services/eos-fundamentals/identity-provider-management)

Provider acceptance is the next legitimate configuration check, not a proven
cause of this 7000. A more specific rejection category depends on what the
publisher's or Epic's authorized tooling exposes; the public client result
alone does not supply it. No account linking, account reset or credential
inspection is required to ask that configuration question.

An unrelated EOS product does not establish compatibility with existing game
progression: its Product User IDs are product-specific. Apple cross-team user
migration likewise requires its documented transfer process. Preserve native
consent, permission, account and failure handling while investigating.
[Epic Connect identity model](https://dev.epicgames.com/docs/epic-online-services/eos-fundamentals/connect-interface/connect-guide/log-in-with-an-epic-games-account),
[Apple app/user transfers](https://developer.apple.com/documentation/signinwithapple/transferring-your-apps-and-users-to-another-team)

See [publisher coordination](PUBLISHER_AUTH_INTEGRATION.md) and the separate
[default-disabled retry guard](AUTH_RETRY_GUARD.md). Neither diagnostics nor that
guard makes EOS accept a rejected credential.
