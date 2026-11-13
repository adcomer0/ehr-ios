# Single-scene Unity host

Apple requires the scene lifecycle for applications linked with the iOS 27 SDK.
The previous launcher linked SDK 27.1 but declared no scene manifest. Three
build-66 phone reports on iOS 27.2.1 reached UIKit's no-scene-lifecycle evaluation
before the game logo. Local signatures and the developer profile remained valid.
See [Apple's migration guide](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle)
and [Unity's platform notice](https://discussions.unity.com/t/info-apple-update-your-editor-to-receive-uiscene-lifecycle-support/1709065).

The original native launcher now configures `EHRUnitySceneDelegate` before
Unity's public UIApplicationMain entry. The builder replaces inherited scene
configuration with one application-window scene and disables multiple scenes.
Unity still owns UIApplicationMain, its application delegate, rendering window
and root view controller.

The adapter obtains the window through the public app-controller and
UIApplicationDelegate selectors, validates its identity and attaches that same
window to the accepted UIWindowScene. It creates no game window or root. Late
window availability retries on main at 100 ms intervals, at most 100 attempts.
The generation/scene guards retire old retries when a scene disconnects.
On the first real foreground transition, the bridge invokes Unity's existing
idempotent `initUnityWithApplication:` selector. Its void/object Objective-C
signature and implementation image are checked against the configured framework.
This initializes Unity before activation: the old delegate can skip that work
when UIKit reports a background state during scene-based cold launch. Initializing
only after activation exposes an old Unity keyboard-order assertion on the Mac.
No private engine-ready byte or keyboard assertion is changed.

The initial legacy foreground callback is skipped for cold-launch parity; later
foreground, active, resign and background callbacks forward once per transition.
Entered callbacks cannot replay after reentry or an exception. Initial attachment
waits until Unity initialization has completed, so showing a window cannot precede
its startup setup. The exact startup ordering is checked against the real engine,
as well as owned collaborators.

A window already visible before attachment is made key and visible afterward.
An intentionally hidden or lazy window stays hidden for Unity to show. The root
is preserved. Disconnect/reconnect can reuse the same Unity window; a foreign
scene, role or replacement application delegate is rejected. Own diagnostic
snapshots contain atomic numeric counters, without UIKit access on a worker,
addresses, account state or text.

This host targets one normal application scene. It does not add multiwindow
support or forward optional scene URL/user-activity events. The configured
manual-key and remembered-login flow does not use those optional callbacks.

Signed startup validation waits for source initialization and one scene whose
window is attached, has a root and is identical to the original delegate's
window. The protected installer requires that proof. Passive XCTest copies use
a separate executable name, `EHRPassiveRuntimeHost`, so interactive overlay
presentation and saved-key acquisition stay outside validation. Only the test
copy is renamed and resealed; the four candidate binaries and profile remain
pinned and unchanged. The shipped application's identity and ownership flow
remain intact.
