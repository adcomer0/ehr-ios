# Native message permissions and delayed lobby cleanup

Build 51 recorded disconnect reason 10 (`DisconnectReasons.Hacking`) from the
original disconnect call. The exact pinned metadata declares that value. This
identifies a server rejection category, without identifying the offending
packet or rule. No server enforcement is disabled or masked by these changes.

## Match the native free-chat gate

The pinned game's `ChatController.SendChat` reaches its free-chat sender only
when the current multiplayer chat mode is `FreeChatOrQuickChat` (1).
`QuickChatOnly` is 2. EHR's lower-level `Utils.SendMessage` constructs chat RPCs
itself and previously omitted that gate. Join-time welcome messages use this
path. Their timing was close to the observed disconnect; causation remains
unproven.

The selected source now checks the same current native chat mode before
creating, appending to or sending a system-message network writer. A missing
settings object, unknown mode or failed getter denies the send. The existing
message addressed only to the local owner remains local. A denied broadcast is
displayed locally; a denied remote-only message is skipped. An existing writer
is returned without adding message bytes.

This uses the existing settings bindings. It does not add an EOS credential or
permission API, change a chat setting, force authentication, or substitute an
authorization result. It also does not establish whether the server will accept
all other EHR RPC traffic. Custom-options sync retains its vanilla-client guard.

## Revalidate the delayed name restore

The join callback schedules a four-second name restore. A physical trace showed
its `RpcSetName` null-reference exception after the host had already disconnected
and returned to the menu. This was a secondary cleanup failure.

The scheduled callback now captures scalar game/client/network identity and
local-player network ID. On expiry it reacquires the native client and player,
requires the same joined lobby and host, verifies local ownership and player
data, and only then applies the suffix and sends the original name restore.
The task is skipped when the current lobby phase, host status or captured
identities no longer match. This is not a connection-generation proof if every
captured identity is later reused.
The valid-lobby path retains the original unconditional name restore.

Both changes are in the selected C# inputs and require a fresh NativeAOT build.
They introduce no native hook, ABI, callback registration or gateway operation.
See [current failures](KNOWN_ISSUES.md) and [build-52 validation](BUILD52_VALIDATION.md)
for the tests and their limits.
