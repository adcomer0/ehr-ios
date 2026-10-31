#pragma once
#import <Foundation/Foundation.h>
@class UIViewController;

// Call only from the player's EHR lobbies action. Presents the official site;
// never reads website credentials, cookies, content, clipboard or lobby data.
// No preload, background refresh, game join or native state change occurs.
FOUNDATION_EXPORT void EHRPresentLobbyBrowser(UIViewController * _Nullable presenter);
