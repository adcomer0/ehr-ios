> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# HTML color compatibility

The installed game does not resolve Unity's HTML-color internal call. Actual
build21 checked both the simple and full-signature resolver names without
invoking an unverified function. Native Color32 and its r/g/b/a Byte fields exist.

`HtmlColorCompatibility.cs` independently implements the documented Unity2022.3
input formats and named colors. It produces packed RGBA bytes; generated source
facades still use the real native four-Single Color constructor. It does not
invent a native MethodInfo or represent the missing engine call as available.
Only NOT_FOUND from resolving the internal call selects this compatibility
path. Candidate integrity, type, field-layout and other errors remain errors.

The contract is [Unity's API documentation](https://docs.unity3d.com/2022.3/Documentation/ScriptReference/ColorUtility.TryParseHtmlString.html).
No Unity implementation code is copied. The supported names use standard CSS
RGBA values. Unlisted formats are rejected; unsupported undocumented behavior is
not claimed.

Build22 verifies all22 documented names, case insensitivity, short/full hex with
and without alpha, malformed inputs and null. Every successful conversion
round-trips through the actual game's ToHtmlStringRGBA. Runtime evidence reports
`implementation=2`, `implementationName=documented_compatibility`.

The optional native adapter remains gated by the loaded image, complete signed
candidate hash and executable bounds. If that call exists in a future verified
build, it additionally proves Color32 payload layout using exported field access.
That engine path is currently unavailable and has not passed runtime execution.
