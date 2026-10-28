> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

The pinned source contains real mobile behavior gaps despite compiling. The
included inventory has141 lexical platform/input sites; comments and conditional
debug code are explicitly not classified as active features.

This package changes six compiled source files only. EHR's own OperatingSystem
helper shadows System.OperatingSystem in the full source project; it gains IsIOS
from Unity RuntimePlatform.IPhonePlayer (reference enum value8). The two original
Android-only NoClip collider writes also run on iOS. The original touch button's
canMove, IntroDestroyed, online-started and countdown availability expression is
unchanged. An iOS-only check runs before OnGUI's HUD/frame early returns, restoring
collision and clearing the flag if no longer eligible, including with the panel
closed. Scene change/destruction also restore it. Reconciliation never enables
NoClip. Missing/destroyed local players clear the flag without dereferencing them.

The desktop ControllerManager postfix also runs on iOS. Its old collider predicate
omitted the button's intro/countdown restrictions. Those restrictions are added
only on iOS, so an external keyboard cannot re-enable collision bypass during a
countdown. The original desktop and Android behavior is unchanged. Another narrow
iOS change stops the F1-held-key 'else Hide' from immediately dismissing a role
info panel explicitly opened by the existing touch button. The original opening,
host, game/movement phase and outside-phase hide guards remain unchanged; this
change never opens a panel by itself. The desktop controller patch remains active.

Steam-only steam_appid.txt creation now skips iOS, as it already skips Android.
Log export and old-log cleanup select the existing host-owned Main.DataPath on iOS
instead of DesktopDirectory. Cleanup's original dry-run, confirmation, age limit,
exact folder-name/path checks and Android early return remain unchanged. No actual
filesystem deletion or account operation was performed by these tools/tests.

Apply the tools in this order to the CURRENT protected full-source project:

1. prepare_ios_mobile_behavior.py on the current post-UIKit, scene-owned GUI source
   and current OperatingSystem.cs, into a fresh directory.
2. prepare_platform_project.py to replace those two compile items in a fresh project.
3. prepare_ios_storage_behavior.py on that project, retaining all current Utils/
   player-join/JSON/bootstrap changes, into another fresh directory.
4. prepare_ios_role_info_behavior.py on that project, retaining current ControlPatch
   attributes and behavior, into the final fresh project.

The supplied ProtectedCompile project is the tested joined example, including the current canonical account callback exclusion policy. Prefer regenerating
against current inputs rather than replacing the parent's project wholesale. Every
adapter fails if its exact source anchors change. There are no new native hooks,
ABI changes, synthetic engine declarations, account/authentication changes or
disabled host/online protections.

Remaining concrete gaps and required checks:

- The custom-sound path is now adapted separately, with actual data/muted-route
  and all18-resource loader proof on the Mac iOS runtime. See IOS_AUDIO.md for
  exact bounds and remaining physical-phone playback verification.
- Chat history and completion now have guarded touch requests that reuse the
  original handler; numeric ×1/×5/×10 and confirmed host meeting selection are
  implemented in IOS_TOUCH_SHORTCUTS.md. The real GetInstanceID path and owned
  scalar state pass actual44 runtime checks. Interactive controls/IME remain
  phone playtests, and the original native character filter stays active.
- The obsolete desktop Ctrl+V caretPos path now skips iOS, leaving native
  TouchScreenKeyboard/SetText handling intact. See IOS_KEYBOARD_PASTE.md.
- Actual iOS metadata has LobbyInfoPane.CopyCodeButton/CopyGameCode; a duplicate
  was not added. Its particular scene visibility remains unobserved.
- Completed own log/translation exports can be selected in a user-triggered
  UIKit share picker; see IOS_EXPORT_SHARING.md. No automated share presentation
  or transmission was performed. Native viewport geometry also accounts for a
  docked full-width keyboard; see IOS_KEYBOARD_VIEWPORT.md.
- The role-info renderer clones AccountManager's DOB-screen visual hierarchy;
  availability on the iOS scene needs verification. No account UI or policy is
  changed by this package.
- Original paging already supports vertical touch swipes, Zoom already supports
  pinch, and settings search already has a PassiveButton. The existing UIKit
  client menu covers the main host shortcuts. These are source observations,
  not claims that all such interactions have run on the phone.

Do not blindly copy Android exclusions. Task-assignment and Starlight server-list
workarounds are Android-specific. EAC's Android disable must not be extended to
iOS. Windows CPU-affinity/window-resolution behavior is desktop-specific. The
existing signed-update handoff and UIKit renderer cover the known stripped
DownloadHandler.data and IMGUI presentation differences; source/reference coverage
reports alone do not prove every other native leaf API is available.

Owned regression tests execute the actual generated helper/predicate source:
261 NoClip reconciliation cases,1024 controller restriction cases,256 role-info
phase/input checks, and8 sandbox/Steam policy checks. They use only owned test
objects, not a fake game simulator. The joined full source build passes with
zero errors; existing nullable/trimming warnings remain. No actual iOS scene,
collider, joystick, audio or gameplay execution is claimed for this package.
