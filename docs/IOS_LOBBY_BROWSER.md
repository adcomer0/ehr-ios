# Browse EHR website lobbies

The **EHR → EHR lobbies** action opens the official
[EHR lobby page](https://app.gurge44.eu/lobbies) inside Apple's Safari view.
This is separate from the stock game's public matchmaker. An empty stock search
does not establish that the website directory has no rooms.

The selected host-only source deliberately leaves the game's global mod-GUID
registration empty to retain the current vanilla-peer hosting path. Its EHR
search patch adds a filter tag, which is separate from that registration. These
are known differences from the upstream modded-client search setup; the exact
cause of an empty stock result set has not been established. This browser does
not change global registration or claim to repair stock matchmaking.

The website owns its sign-in and authorization. Its page currently polls
`/get-all-lobbies-json`; an anonymous request returns HTTP 403, and the site's
own code switches to its login view. The app does not turn that denial into a
fake empty lobby list, invent an anonymous API, or borrow a website cookie.
The website may require its own sign-in and in-game verification. That session
is separate from the app's itch.io key and EOS/game login.

Use the website's own **Copy** action for a room you choose, return with **Done**,
select the matching game region, and use the original game's code-entry join.
Check the listed EHR version, status, map and region. Custom regions or maps may
require additional compatible support. The app does not automatically join,
install a region/map, or bypass native ownership, account or version checks.

`EHRPresentLobbyBrowser(UIViewController *)` creates the Safari controller only
after the player's button action and main-thread/foreground/presenter-readiness
checks. There is no startup preload, background feed polling, website content
inspection, clipboard read, cookie bridge, credential read or lobby diagnostic
logging. The initial destination is fixed HTTPS. Subsequent navigation belongs
to the website and Safari, including its normal account pages and links.

Owned presentation fixtures compile the production action with fake
UIKit/Safari objects. They check unavailable/background/busy/worker rejection,
the exact destination, **Done**, full-screen presentation and duplicate taps,
without making a real request. The source also compiles against the actual iOS
SDK; neither check establishes a live website login or room join.

```sh
python3 -m unittest discover -s tests -p 'test_lobby_browser.py' -v
```

The original native controller is linked with `SafariServices.framework` by the
full-game builder. No selected C# source or website code is modified.
