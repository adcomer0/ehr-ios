> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

# iOS client-control sizing

This overlay consumes the CURRENT post-UIKit, Scene-owned, mobile-behavior ClientControlGUI and current NativeTouchGUI. It changes client-control presentation only. It preserves every visibility, host, phase and action guard; the action body is byte-identical after normalizing the two zoom-slider geometry expressions. It does not change the native renderer's global font floor or the 72-byte touch table.

The current transformed source already makes action buttons about 47.52 pt tall and the toggle 46.08 pt at equal horizontal/vertical density. The upstream PC scale is not used by this selected source. This pass makes the 44 pt touch and 14 pt text minima explicit, raises the smaller drag hint to 14 pt, raises the slider's touch rectangle to 44 pt, and measures horizontal and vertical density separately. Window width/height fit the native safe area. A first successful BeginFrame rebuilds the initial density 1 fallback; later density, screen-size, and safe-area changes reflow styles and window dimensions while preserving dragged position in logical points and clamping it safely.

Apply AFTER the current full-source/audio project, preserving all non-UI items:

```sh
python3 tools/prepare_control_sizing.py \
  --gui-source /absolute/current/ClientControlGUI.cs \
  --touch-source /absolute/current/NativeTouchGUI.cs \
  --project /absolute/current/EHR.csproj \
  --output /absolute/fresh/output
```

Frozen selected join is `Overlay41/EHR.csproj`, based on the production audio case-policy `EHR-iOS-audio-names-stage/Names41/EHR.csproj`. Only the two UI Compile inputs change. Root may replay the tool against a newer project selecting the same current UI inputs.

`tests/test_control_sizing.py` checks action/visibility guards, first-frame ordering, local font scope, unchanged ABI, unknown-source rejection, slider geometry, and retention of every other full-project input. Run it with `EHR_CONTROL_SIZING_INPUT_PROJECT=/absolute/current/input/EHR.csproj`; without an explicit generated input it skips these source checks. Nine tests pass, including rebasing unrelated relative source/resource paths when emitting a new project. `tools/check_control_geometry.py --overlay /absolute/current/overlay --output FRESH` compiles exact extracted transformed metrics/style/window/toggle/slider presentation methods with the actual transformed NativeTouchGUI against owned numeric viewport/table inputs. No Unity/game object or native game method exists in that fixture. It checks 667/852/956 pt iPhone landscape sizes, 393 pt portrait and 768/1024/1366 pt iPads across 42 density scenarios, including unequal horizontal/vertical mapping, density changes, safe bounds, dragging, and rotation. Its 5,882 assertions verify emitted point rectangles/text metrics, rather than simulating gameplay or claiming an engine render.

The full selected EHR project compiles with 0 errors (10,311 existing warnings). NativeAOT publication, actual UIKit rendering/typography and physical-phone usability remain runtime gates owned by the main agent; this package performs no account/game/UI operations.
