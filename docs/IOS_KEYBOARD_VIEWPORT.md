> Implementation-stage notes. For the current public snapshot and prerequisites, start with [BUILDING.md](BUILDING.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Historical fixture paths are placeholders, not included artifacts.

The native touch renderer previously reported only the host view's safe-area insets. It had no keyboard geometry handling.

The iOS 15 minimum permits reading the host view's public `keyboardLayoutGuide.layoutFrame`. The guide reports its owning view's coordinates, so the renderer converts from that owner only if needed. It does not change constraints, keyboard focus, input text or `followsUndockedKeyboard`. This also reads the current geometry when the keyboard was already visible before the first frame.

Only an intersection covering the full horizontal safe content area and reaching the bottom safe edge increases the existing `safe_bottom` value. Partial-width/floating rectangles, undocked rectangles with a bottom gap, empty frames and offscreen frames leave it unchanged. The logical pixel conversion still happens once in the original frame code. The 72-byte table and 48-byte frame remain unchanged; existing managed sizing observes the changed safe height and reflows normally. Source action/focus guards are unchanged.

Apple's [keyboard layout guide example](https://developer.apple.com/documentation/uikit/adjusting-your-layout-with-keyboard-layout-guide) explains that the default guide tracks docked keyboards and reports the bottom safe area when hidden or undocked. Its [followsUndockedKeyboard documentation](https://developer.apple.com/documentation/uikit/uikeyboardlayoutguide/followsundockedkeyboard) describes the opt-in behavior for floating keyboards. This patch leaves that property untouched.

The pure numeric fixture passed 4,921 checks across device sizes, nonzero origins, safe areas, density conversions, docked and floating geometry, offscreen frames and invalid inputs. The actual native file compiles for iOS arm64 with ARC and `-Wall -Wextra -Werror`. No keyboard or UI was presented in these checks. Real iPhone keyboard, rotation and IME playtests remain pending.
