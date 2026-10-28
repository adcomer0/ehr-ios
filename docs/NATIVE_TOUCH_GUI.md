> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# Targeted iOS client controls

This original UIKit renderer replaces only the presentation backend used by the
pinned EHR `ClientControlGUI`. It does not declare missing Unity IMGUI APIs.
The source adapter verifies the reviewed input SHA and preserves `DrawButtons`
through the end of the file byte for byte, including host/lobby/game guards and
the original actions. No game binaries, metadata, account data, or credentials
are included.

`TouchGUIStyle`, its normal/hover/active states, and `TouchTexture` are explicitly
local presentation values. The renderer uses UIButton, UILabel, UISlider and
UIScrollView. It reads real facade Color/Rect/Vector2 members and passes its own
PODs across the fixed C function table. It never guesses IL2CPP struct layouts.
Normal/pressed/pointer-hover backgrounds, text, font traits/alignment, rounded
edges, opacity, a scroll track/thumb, title dragging, safe areas and rotation
clamping are implemented. The supported rich-label tags are b/i/size/color;
unknown tags remain literal. There is no HTML/WebView resource loading.

The root view passes touches outside the actual panel/toggle to the game. UIKit
events only set bounded pending values. A button action is consumed once by a
matching currently emitted key and label, at most one action per rendered frame.
Removing or hiding a control discards its pending input. The original source
evaluates eligibility before requesting each control. Rendering runs at 20 Hz;
original Unity OnGUI invocations drive it on the main thread.

## Integration

1. Compile `native/EHRTouchUI.mm` into the native helper; link UIKit and QuartzCore.
2. Include `managed/NativeTouchGUI.cs` with the generated live facades. It supports
   both flat research names and source-surface names via generated aliases.
3. After binding the live gateway and before creating GUI source components,
   resolve `ehr_touch_ui_bind_v1` from the NativeAOT image and call it with
   `EHRTouchUIGetV1(), sizeof(EHRTouchUIV1)`. Return 0 is required. Bind is once,
   main-thread only; unavailable renderer never silently becomes a fake GUI.
4. Generate the reviewed ClientControlGUI overlay with:
   `python3 tools/adapt_touch_gui.py --input PATH/Modules/ClientControlGUI.cs --output OUT/ClientControlGUI.cs`.
   Apply the separate source-component Scene subscription ownership overlay
   **after** this pass. Preserve the added `TouchGUI.Hide()` in OnDestroy.
5. Run native `EHRTouchUISelfTest(proof,12)` and managed
   `ehr_touch_ui_managed_contract_test(proof,8)` through an app-hosted XCTest.
   These tests do not execute game actions. Then test the actual source lifecycle
   and visible controls separately before claiming the complete UI works.

Native proof slots: pass,status,viewport scale,button creation,queued press,
duplicate-key rejection,press consumed once,removed/changed-action input dropped,
rich text,slider value,hidden-input/scroll offset,malformed UTF8/geometry rejected.
Managed slots: pass,bound-main,table72,frame48,item240/style192,dynamicCodeFlags,
action-key separation,no active frame. DynamicCodeFlags must be 0.

## Validation

The stage has an iOS-arm64 `-Wall -Wextra -Werror` object build, seven independent
source-adaptation regression tests and an original macOS NativeAOT function-table
fixture with seventeen checks. The fixture uses explicitly synthetic Color/Rect
values, not game facades or a game process. Its proof records that distinction.
Actual UIKit/self-test and rendered source lifecycle results are still pending
the parent's next signed candidate; compile success is not gameplay proof.

`Compile/EHR.csproj` is a local diagnostic project joining the full upstream
source and live replacement runtime. It is not a standalone production project
or a portable repository input. Its current six remaining errors concern the
separate complex-delegate surface and desktop binary updater adaptation.

Known separate behavior: the original DrawButtons body still has Android-only
NoClip collider adjustments. Preserving that body does not prove iOS NoClip
behavior. Source components and Scene delegate subscription cleanup are separate
required runtime integrations. This renderer never touches account progress,
links identities, resets saves, replaces application data, or installs updates.
