#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// proof[6]: pass,status,Connecting<CreateGameOptions> metadata,
// PlayerHasTaskOfType<HudOverrideTask> metadata,Get<ServerListButton> metadata,
// actualStringObjectAndNull. Metadata lookup includes real generic inflation and
// exact closed signature validation; it DOES NOT execute these game methods.
int32_t ehr_generated_generic_game_methods_self_test(int32_t *proof,size_t count);
#ifdef __cplusplus
}
#endif
