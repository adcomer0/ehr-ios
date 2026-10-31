#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>
// Passive main-thread metadata preparation. No request, constructor, account
// operation or registration write occurs. Enabled only by the selected build.
typedef int32_t (*EHRLobbySearchAllowed)(void);
FOUNDATION_EXPORT int32_t EHRLobbySearchPrepare(EHRLobbySearchAllowed allowed);
// Fixed numeric counters only; no room, player, credential or response content.
FOUNDATION_EXPORT NSDictionary *EHRLobbySearchCopyStatus(void);
// Owned original-runtime filter objects only. No real game owner, request,
// account, scene, service, clipboard or global registration mutation is used.
FOUNDATION_EXPORT NSDictionary *EHRLobbySearchSelfTest(void);
