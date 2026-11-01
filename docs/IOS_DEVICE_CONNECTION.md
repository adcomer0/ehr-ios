# Development-device connection checks

These checks apply to normal local development installation, using an existing
trusted pairing and a profile that covers the exact device. They do not provide
internet-based installation or distribution signing.

Use the device identifier from a private file outside Git. Query fresh CoreDevice
inventory and direct details for that exact physical device, checking model,
pairing, transport, connected tunnel and developer-service readiness. A wireless
transfer is established by `localNetwork` in the actual install preflight and a
successful receipt plus an installed-version query after USB has been removed.
A USB-connected successful query alone does not establish wireless delivery.

If the paired device initially appears unavailable, make a fresh exact-device
details request and allow a short bounded discovery interval before requesting
another cable connection. Retained hostnames can become stale as services change
when USB is removed; a missing saved Bonjour name alone is not a complete device
readiness test. Resolve current advertisements with their actual network-interface
scope. A refused legacy endpoint does not establish that the modern pairing
service is unreachable. Keep all identifiers, IP addresses and raw diagnostics
outside Git.

Check connection failure separately from installation and application launch.
A phone can receive an update over Wi-Fi while its lock screen blocks a later
foreground launch. Record the successful installation rather than describing
that entire operation as a failed transfer; the player can open the app normally.

The build-66 test established an actual Wi-Fi upgrade followed by a successful
idle connection check. Existing wireless settings and pairing were already
correct in that run; no toggle or reset was applied. This does not identify the
cause of earlier intermittent outages or guarantee future network availability.

Apple's [current pairing guide](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac)
describes the supported Wi-Fi/IPv6 requirements and version-dependent pairing UI.
[TN3158](https://developer.apple.com/documentation/technotes/tn3158-resolving-xcode-15-device-connection-issues)
covers CoreDevice network, VPN and packet-filter interference.
[TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
explains local-network privacy and helper-process attribution. Use current
platform diagnostics to select a repair; do not repeatedly reset trust or
change unrelated security settings based on an old DNS lookup.
