#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>
// Passive main-thread metadata preparation. No request, constructor, account
// operation or registration write occurs. Enabled only by the selected build.
typedef int32_t (*EHRLobbySearchAllowed)(void);
FOUNDATION_EXPORT int32_t EHRLobbySearchPrepare(EHRLobbySearchAllowed allowed);
// Explicit user selection: 0 keeps the original All lobbies search; 1 adds
// the EHR mod filter. Main-thread only. The default is All. Stores only this
// nonsensitive integer in this app's own preferences; never starts a search.
FOUNDATION_EXPORT int32_t EHRLobbySearchGetSelection(void);
FOUNDATION_EXPORT int32_t EHRLobbySearchSetSelection(int32_t selection);
// Fixed numeric counters only; no room, player, credential or response content.
FOUNDATION_EXPORT NSDictionary *EHRLobbySearchCopyStatus(void);
// Owned original-runtime filter objects only. No real game owner, request,
// account, scene, service, clipboard or global registration mutation is used.
FOUNDATION_EXPORT NSDictionary *EHRLobbySearchSelfTest(void);
