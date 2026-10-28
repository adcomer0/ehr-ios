> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Apple sign-in diagnostic observer

The native-only observer forwards the pinned AppleAuthManager request,
success and error methods exactly once. It never starts, retries, cancels or
suppresses authentication. Existing native authentication and account checks
remain authoritative; no credential, saved account or provider flag is changed.

Installation requires the main thread and the existing pinned engine validator
(full candidate hash, source allowlist, UUID and executable image bounds).
Every original Objective-C method must be declared on the actual class with the
exact reviewed argument count/type encoding and expected source RVA. All three
methods are checked before mutation. A different image/method fails closed.

After ehr_runtime_initialize succeeds, call
EHRRuntimeDiagnosticsRecordAuthInstall(EHRAppleAuthDiagnosticsInstall()). Add
EHRAppleAuthDiagnostics.mm to the native helper build. Install result0 means
installed/idempotent;1 wrong thread;2 image pin not ready/mismatch;3 class absent;
4 selector/type/IMP mismatch. This optional observer status does not mark auth
or source startup successful.

The existing numeric diagnostic writer receives request, success, error and
overlap counts. Errors retain only domain0(other),1(Apple Authorization),
2(OSStatus),3(Cocoa),4(URL) and an int32 code. The domain is compared against
fixed strings; arbitrary domain text is never retained or written.
localizedDescription, userInfo, underlying errors, account identifiers,
credentials and tokens are never read or written. Overlap is an observation,
not a proven cause or suppression gate. Counters saturate at1000000; at most64
weak controller identities are observed without extending native lifetimes.

The own Objective-C fixture checks24 conditions: exact original forwarding,
preflight rejection without mutation, worker rejection, idempotence, numeric
redaction, overlap observation, and forwarding after a diagnostic-writer fault.
It performs no game authorization or network requests. A production arm64-iOS
compile passes. Actual pinned installation and an authorized user login outcome
must still be observed on the new candidate. Compilation is not authentication
proof, an audience fix, or evidence of account preservation.
