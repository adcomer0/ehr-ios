> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

The status panel's **Share exports** button opens an iOS list of already saved EHR log dumps and translation exports. The user selects one file, then chooses a destination in the normal iOS share sheet. The implementation does not invoke source export commands, present a sheet during startup, upload files or operate on account/game state.

The root is computed with the same native `NSApplicationSupportDirectory/EHRSource` rule used to configure the source host. The selected source `Main.DataPath` returns that host root. Only these exact shapes are eligible:

- `EHR_Logs/yyyy-MM-dd_HH.mm.ss/EHR-v<version>-LOG.html`
- `Language/export_<language>.dat`

The source's `DumpLog` closes a synchronous file copy before returning; `ExportCustomTranslation` closes its synchronous `WriteAllText` before returning. Their completed outputs are separate from the live logger. The picker runs on the main UI thread after a user tap and excludes the live log, translation inputs/templates, account/config/preset files, empty files, directories, pipes, symbolic links and hard links. Logs are limited to 16 MiB and translations to 8 MiB. The scanner has a 4,096-entry global work budget and lists at most 128 eligible recent files.

A row is reopened through no-follow directory/file descriptors. Root and file identity must still match the listing. The selected regular, single-link file is copied completely into a new exclusive private temporary file. Size, identity, modification time and change time are checked before and after the read. Changed or replaced exports are rejected. Only the completed read-only snapshot URL is handed to `UIActivityViewController`; no source directory URL is shared. Original exports are never removed or overwritten. Temporary snapshots remain available for the full activity lifetime and are left to normal OS temporary-file cleanup.

The native helper adds no NativeAOT function table or managed ABI. Add `native/EHRExportSharing.mm` to the full native helper's compilation sources and import its header from the status overlay. The reviewed overlay adds a 44-point share button, retains the existing 44-point status button and makes status text scroll when needed. `prepare_export_overlay.py` produces that pinned narrow join for review; the adopted native source itself is the canonical build input afterwards.

Own checks compile and run only synthetic filesystem fixtures. They cover allowlisting, symlinks/hard links, nonregular and oversized files, changed/replaced files, deterministic modification during copy, exact full snapshots, exclusive destinations and bounded enumeration. UIKit source is compiled for iOS arm64 with ARC and `-Wall -Wextra -Werror`. No actual share sheet presentation or transmission is automated.

Apple documents the standard [activity controller](https://developer.apple.com/documentation/uikit/uiactivityviewcontroller) and [popover source view](https://developer.apple.com/documentation/uikit/uipopoverpresentationcontroller/sourceview). The picker supplies the selected row as the iPad popover anchor.
