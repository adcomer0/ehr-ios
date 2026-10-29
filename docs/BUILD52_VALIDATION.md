# Development build 52 validation

This candidate retains the build-51 native diagnostics and repairs two selected
source paths: system-message network sends now honor the native chat-mode gate,
and the delayed join-time name restore revalidates its lobby and owner. See
[the source behavior and evidence](MULTIPLAYER_SEND_GUARDS.md).

The compilation inputs contain 796 C# files and 224 exact resources. Only
`Utils.cs` and `PlayerJoinAndLeftPatch.cs` differ from the build-48 selection
reused through native build 51. The source and resource manifest is frozen and
verified before compilation; the candidate requires a new managed NativeAOT
library. Runtime JIT is not used.

## Passed

- All 297 owned regression tests passed with the explicitly configured local
  historical source fixtures. This is not a clean-clone claim.
- Fresh `ios-arm64` NativeAOT publication, with all required production exports.
  A metadata-only artifact audit confirmed 224 exact resource names and no game
  assembly references.
- An offline compiled callback audit covered 334 callbacks and 168 argument
  reads, with zero mismatches or unresolved reads. The audit required its public
  NuGet runtime dependencies in an explicitly supplied reference directory.
- The extracted system-chat gate passed 4,032 owned cases / 29,580 assertions,
  including missing or throwing settings, unknown modes, local/remote/broadcast
  targets and supplied writers. Denied paths created no writer and added no
  bytes. Removing just the helper and guard restored the prior selected file
  byte for byte. The remaining network implementation was an owned sentinel;
  this fixture did not operate the game, a network or an account.
- Signed iOS-on-Mac full startup initialized 5,049 options and 292 permitted
  bindings, with the six account/consent exclusions retained. Dynamic-code flags
  stayed zero. All four source candidate executables remained unchanged.
- The actual-runtime host-start adapter proof passed 46 checks and root
  conservation. The isolated authentication observer passed 87 checks without
  credential reads, real authentication, account or network operations. Startup
  authentication events and disconnect observations stayed zero.
- The retained-carrier, touch/action, muted-audio, resource-loader and
  failure-cleanup probes passed in the same signed runtime run.

The protected installer verified and completed an in-place build-51-to-52
upgrade on the exact test iPhone over its `localNetwork` developer connection.
The installed build was queried and confirmed. Installation did not launch the
app, uninstall anything, access an app container, change pairing/security, or
operate an account. No build-52 physical multiplayer or authentication success
is independently certified by the installer.

## Subsequent user report and numeric observation

Following delivery, the user reported playing a match with a peer using the
ordinary unmodified client. This supports one host/vanilla-peer gameplay path;
the exact settings, complete outcome and all-role behavior were not established.

A subsequent copy of the host app's own bounded numeric cache records player
join, host-start/ship initialization and player spawns. It also records
`GameStartManager.Start` / `CheckSettingsDiffs` null-reference failures and ten
map-door postfix cast failures. Its single recorded disconnect is reason 16
(`Destroy`), rather than reason 10. No game-end route appears in this cache.
The cache has no explicit build identity, so its emitter build cannot be
independently identified solely from these fields. This observation is not a
clean runtime or complete-round certification.

Apple authorization and the correct Apple credential type reached EOS in
physical build 51; EOS returned 7000 and the game fell back to a device guest.
That provider rejection remains unresolved in this candidate. The native chat
gate is a concrete parity correction, not proof of the reason-10 server rule.
Normal rounds, all roles, progression safety and protection from bans remain
unverified. Keep valuable accounts outside testing.
