# Default-disabled EOS 7000 retry guard

This native behavior change is separate from passive Apple/EOS diagnostics.
It is compiled only when the builder receives `--auth-retry-guard-map`, starts
disabled. A separate signed startup request can enable it only after successful
runtime metadata preparation. Actual metadata preparation and independent review
are required before a controlled development build requests activation.
A metadata-only test is not proof of failure UI or backend authentication.

## Pinned flow and permitted substitution

The supported framework's normal `EOSConnectPlatformLoginCallback` handles
result 7000 by clearing its cached platform credential through original code.
When the original continuation cannot complete, it clears `tryingToLogin` and
calls `LoginWithCorrectPlatform` again. A passive observer reads only the
existing public numeric ResultCode getter; the original callback still runs
once with the same receiver, by-reference callback payload and hidden MethodInfo.

A native thread-local scope permits only the same receiver's synchronous nested
retry during that known normal 7000 callback on the main thread. Silent callbacks
clear inherited eligibility temporarily. Other codes, unavailable observations,
other receivers, worker calls and later manual sign-in keep their original path.
The scope restores its previous state during native exception unwinding.

When explicitly enabled after review, the guard first requires the original
`tryingToLogin == false` state. It locates only existing `_instance` static
storage on the exact closed `DestroyableSingleton<AccountManager>` parent.
Public metadata must prove exact field types and that the parent declares no
`.cctor`; `class_is_inited` establishes metadata readiness only. It never calls
an Instance getter, initializes an account, or guesses object offsets. Gateway
readiness precedes public field reads, and independent strong and pinned roots
stabilize the receiver and existing AccountManager during the call.

Only after every check passes does the guard substitute the game's real
`AccountManager.PlatformSignInFail` for that automatic retry. This existing
method retains its own native checks, failure UI and TempAccount branch. No
success, cancellation, online permission or identity state is manufactured.
A preflight failure forwards the original retry. After the native failure
handler starts, its exceptions propagate; the guard never retries after partial
failure handling. Existing source permission/account protections remain active.

The exact source framework SHA, metadata SHA, UUID, native method association,
installed entry contract, relocation, generated trampoline and final signed
framework hash remain mandatory gates. The failure method is validated but is
not itself hooked. This extra contract does not change source target IDs.

## Validation and remaining gates

The own compiled fixtures exercise exact metadata rejection (including `.cctor`
and unresolved generic field types), native frame forwarding, scoped eligibility,
preflight fallback, native exception propagation, and zero leaked roots. They
use original test objects/functions and make no game account/auth requests.
Strict iOS ARM64 compilation is a separate check from actual runtime execution.

`EHRAuthRetryGuardPrepare()` resolves metadata only. It does not read singleton
storage or invoke login/failure methods. If actual generic metadata reports `T`
instead of AccountManager, preparation fails and the guard must remain disabled.
`EHRAuthRetryGuardCopyStatus()` reports fixed own numeric state/counters.
`EHRAuthRetryGuardSetEnabled(1)` is an explicit main-thread operation requiring
successful preparation. `EHRAuthRetryGuardStart(1)` calls Prepare first and only
then enables on success. The startup binder calls this solely in an explicitly
opted-in development build; the default request is false and performs neither
preparation nor activation. No startup operation invokes authentication or an
account method.

The actual Mac metadata-only gate has passed: main-thread/idempotent preparation,
worker rejection, disabled state and zero failure-handler entries, with candidate
binaries unchanged. Independent native review found no blocking issue. This
establishes readiness, not live error-flow behavior. Follow [the metadata-only
procedure and opt-in checks](AUTH_RETRY_METADATA_BUILD.md) for each changed
candidate. Review the actual failure UI under an
explicitly authorized test. Even a functioning guard leaves EOS 7000 a real
platform-authentication failure; [publisher integration](PUBLISHER_AUTH_INTEGRATION.md)
is a separate concern. A current working online lobby must not be described as
disconnected solely because this separate platform sign-in failed.
