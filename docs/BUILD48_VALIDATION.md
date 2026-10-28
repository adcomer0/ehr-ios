# Development build 48 validation

Validated on 2026-10-28 against the pinned Among Us iPhoneOS 2026.9.29 (3)
framework, Unity 2022.3.62f3, and EHR v8.0.3. The signed local candidate uses
NativeAOT, with no runtime JIT. No game binaries, assets, profiles, device
identifiers or raw runtime reports are part of this repository.

## Passed

- NativeAOT compilation of all 796 selected C# inputs and 224 exact resource
  names; metadata-only audit found no game assembly references.
- Actual compiled callback argument audit: 334 callbacks, 168 argument edges,
  zero mismatches and zero unresolved edges.
- 263 owned regression tests, using explicit local historical fixture inputs
  where required. This is not a claim that a clean clone includes those inputs.
- Strict iPhone ARM64 compilation and signed iOS-on-Mac startup: EHR loaded
  once, initialized 5,049 options and activated 292 permitted bindings from
  298 metadata targets. The six account/consent exclusions remain in place.
- Real-runtime coroutine probe retained 1,024 completed native carriers with
  one active owned carrier. Registry state stayed at the existing source
  baseline plus one; every late `MoveNext` remained false. Eight samples
  verified native terminal exceptions, duplicate rejection and closed IDs.
  Registry state and exact owned-root count returned to baseline. No forced GC,
  Unity scheduling, lobby, account or network operation was performed by this
  probe.
- Actual UnityAction ownership, touch scalar/identity, muted audio, all-resource
  audio-loader and failure-cleanup probes. Cleanup left no active source state,
  current-yield roots or association weak roots.
- The explicitly opted-in retry guard prepared and enabled successfully in the
  actual runtime. Failure-handler entries and completed calls remained zero:
  these tests did not start sign-in or exercise the failure UI. A separate
  metadata-only test also passed with activation disabled.
- The four candidate executables were unchanged by both signed Mac tests.

The standard retry-guard build default remains off. The development opt-in is
separate from the compiled initial-state flag, and the protected installer
requires matching actual prepared/enabled startup evidence when requested.

## Still unresolved

Physical build 47 is the failure baseline: lobby settings lagged, game start
went black, and native Apple sign-in repeated after EOS result 7000. A new
phone test must establish whether build 48 changes those symptoms. The
coroutine capacity defect has been repaired and tested in the real runtime;
other black-screen paths may remain. The additional numeric diagnostics are
intended to identify their exact operation and source callback.

The retry guard changes only the repeated failure flow. It does not make EOS
accept an Apple token. Successful account authentication, native failure UI,
online discovery, vanilla-peer joining, complete rounds and all role behavior
remain unverified. Account/progression safety and protection from bans have
not been established. Valuable accounts remain outside testing.
