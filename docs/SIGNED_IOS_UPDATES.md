> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Signed iOS update handoff

`adapt_signed_updater.py` is a pinned source adaptation applied after the
source-attribute name pass. It preserves upstream GitHub release requests,
version/title comparisons and popup presentation. It changes the desktop DLL
asset policy to an immutable, native-host-configured HTTPS instructions URL.
The original binary replacement, temporary DLL downloading, residue deletion
and legacy folder-deletion paths are removed from this iOS source overlay.

`SourceSignedUpdates.cs` is the original replacement backend. An explicit source
update action opens configured instructions; with no configuration it explains
that a rebuilt, signed iPhone app is required. A configured URL is not proof of
a remote app signature. The host must provide the intended release instructions.
This code does not download/install an app, mutate files, move accounts, link
identities, reset saves or copy data.

Production integration includes `SourceSignedUpdates.cs` and
`NativeSignedUpdates.cs`. After native source-host binding and before source
startup, call `ehr_source_updates_configure(nullptr,0)` to explicitly configure
no available instructions, or pass the reviewed UTF8 HTTPS instructions URL.
The configuration is immutable. Actual opening uses the real facade
Application.OpenURL only after the user's update action.

Validation: five source-adaptation tests, four original NativeAOT process
fixtures exercising absent/configured URL, invalid URLs, immutable configuration
and main-thread guards. Fixture callbacks never open a real browser or network
connection. The complete replacement-source compilation reaches zero errors;
this does not prove the full source plugin can run before its remaining native
bindings and coroutine lifetime bridge are installed.
