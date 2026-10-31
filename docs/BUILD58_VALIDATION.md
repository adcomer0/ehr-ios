# Branded build 58 validation

Historical checkpoint: build 59 adds the mandatory itch.io ownership gate and
opt-in EHR website integration. These build-58 observations do not establish
ownership verification; see [the current sign-in flow](ITCH_SIGN_IN.md).

Build 58 is the **EHR Among Us** development candidate. It upgrades the working
build-57 app identity, adding the original EHR icon, the redesigned itch.io
entry and Account controls. It does not change the NativeAOT managed source,
the pinned game framework or the first-profile guest guard.

## Automated and signed checks

- All 344 configured Python regression tests passed, including the owned
  runtime, provider, signing, protected-install and icon/builder fixtures.
- The unchanged native authentication runtime retained its 844-check fixture
  baseline. The credential/callback/storage policy passed 477 checks.
- The production UIKit controller compiled for iOS ARM64 with warnings treated
  as errors. An actual simulator UIKit run passed 139 assertions. Portrait,
  both landscape orientations, software keyboard, account creation and removal
  confirmation screenshots were reviewed. A separate Account landscape review
  passed 16 assertions for signed-in, unsigned recovery and removal-result
  states. Compact landscape Account controls scroll vertically.
- The branded app was signed with the owner's matching development profile.
  The matching signed Mac startup passed with four candidate binaries
  unchanged, 5,049 options and 292 active patch targets. The provider prepared
  with zero credential submissions, SDK login or migration actions and no
  cleared-session state.
- Original SDK callback/default-value marshaling and silent-delegate binding
  passed, with 6,815 roots before and after. This proof read no credential,
  invoked no real login and created no account.
- All 159 native source pins matched the staged candidate. Its visible label
  and packaged primary iPhone/iPad icon references were checked; the brand
  artwork was inspected in the actual bundle.

The fixture uses owned synthetic credentials, mocked Keychain calls and owned
callback substitutes. It does not exercise a player's remote account. The Mac
startup result establishes native integration, not an iPhone gameplay test.

## Device delivery

On the exact paired test iPhone, the protected installer confirmed the existing
working app at build 57, upgraded it to 58 over USB, and verified the installed
version. It preserved that bundle and its storage; it did not uninstall or reset
that working app, read its credentials or operate account UI.

Only after that successful upgrade, a separate user-authorized cleanup checked
both exact app identities and versions, removed the legacy build-56 **EHR Native
Preview**, and confirmed the legacy app absent and **EHR Among Us** still at 58.
The official game and other phones were not operated. The public protected
installer continues to have no automatic uninstall path.

The OS reports **EHR Among Us** at build 58. Physical Home Screen icon refresh,
new-build sign-in behavior and gameplay still require player observation.
Build 57's earlier first-profile completion and later automatic remembered-key
login remain the available real account observations; see
[their precise limits](ISOLATED_SIGNIN_TEST.md).

## Release scope

The public handoff contains source, original artwork and build tooling. The
current development profile is for registered devices. Wider distribution
requires the EHR team's authorized signing and game-content distribution path;
these checks do not establish App Store/TestFlight eligibility or publisher
approval. Existing-guest migration, every role/map and authenticated multiplayer
coverage remain outside this checkpoint. See the
[maintainer handoff](MAINTAINER_HANDOFF.md) and [known issues](KNOWN_ISSUES.md).
