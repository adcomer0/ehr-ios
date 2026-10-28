> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Passive EOS login result observation

This observer records only numeric EOS `ResultCode`, observer status, count and
normal/silent phase. It does not log callback objects, ClientData, identifiers,
tokens, credential responses, error strings or account state. It does not start
login, retry login, link accounts, modify providers, suppress failures or alter
permissions. A zero result is known success only when observerStatus is zero.

The pinned clear framework has two ordinary instance methods on EOSManager:
`EOSConnectPlatformLoginCallback(ref LoginCallbackInfo)` and
`EOSConnectPlatformSilentLoginCallback(ref LoginCallbackInfo)`. The pre-sign
patcher supplies independent original trampolines. Each compiled forwarder calls
that original exactly once with unchanged self, same by-reference pointer and
same hidden MethodInfo. Optional observer exceptions are contained; exceptions
from the original retain their original behavior. No runtime executable memory
is allocated or modified.

`EHREOSLoginDiagnosticsPrepare()` must run on Unity's main thread after successful
`ehr_runtime_initialize()`. It returns EHRRuntimeStatus (0 ready). It resolves
all three exact signatures through the existing gateway and validates their
RVAs through the signed-framework hash/UUID/public-metadata association guard.
The third method is the real public `LoginCallbackInfo.get_ResultCode`, a pinned
pure scalar getter verified offline on this source image. It is called directly
with the real immutable metadata borrow. The mixed-reference callback struct is
never boxed, copied, parsed or accessed through private offsets. Getter metadata
and its class are process-lived borrows; no managed object roots are allocated.

If preflight fails, observation records that status and original forwarding
continues. Null info records BAD_ARGUMENT and still forwards it unchanged. The
UUID-checked original image-base resolver retains existing hard build-invariant
failure behavior: a missing matching loaded image aborts rather than executing
an invalid trampoline. This is unreachable in a correctly pinned installed
hooked image; it is separate from optional getter availability.

Two new native diagnostic contracts are separate from the EHR source catalog.
No selector target IDs, callback policies, existing alias maps or activation
sets change. The shared writer's `eosLogin.normal` and `eosLogin.silent` rows have
fixed numeric fields `resultCode`, `observerStatus`, `observedCount`.

## Builder integration

1. Run `tools/eos_login_hook_inputs.py selectors --output PRIVATE/selectors.json`.
2. Run existing `tools/map_harmony_native_targets.py` with original framework,
   metadata, these selectors and existing game's pin report. Keep output private.
3. After existing full-catalog and iterator input joins, call
   `merge_eos_login_inputs(hook_map, eos_report, contracts)`; write returned maps
   and append its two names to selected_hooks. Preserve hook_aliases unchanged.
4. Run existing strict pre-sign patcher over the complete selected set. Generate
   `EHREOSLoginBinding.generated.h` with `binding_header(hook_manifest)`.
5. Compile `native/EHREOSLoginDiagnostics.mm` with the same generated include path
   and shared numeric writer. Add the small native image-base accessor patch.
6. Call `EHREOSLoginDiagnosticsPrepare()` immediately after runtime initialize,
   before any full-source callbacks. Do not turn an observer status into a
   source-startup/authentication gate.

Input SHA/UUID allowlists intentionally support only the analyzed current local
framework. The merger rejects wrong signatures, shared/generic/abstract entries,
wrong token/RVA, missing getter, wrong provenance or existing entry aliases.
The final patcher independently proves relocation at the actual full-batch slot.

Own fixtures test unchanged argument identity, unavailable preflight, both
phases, success/error/unknown numeric values, null info, writer failure, original
exception propagation and main-thread preparation. They perform zero game,
account or network operations. Real EOS observation still requires a separately
reviewed installed candidate and the user's authorized single login attempt;
these tests do not establish why the earlier phone login failed.
