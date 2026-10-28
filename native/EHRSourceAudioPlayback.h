#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// Main-thread only, optional retirement of only this adapter's cached clips.
// Stops each exact own clip if an existing SoundManager is available; always
// attempts each own Destroy and root release. No unrelated game audio changes.
int32_t ehr_source_audio_close_v1(void);
// Explicit optional startup proof. Refuses if production cache is already in
// use. Writes/reads only authored WAVs beneath configured own EHR DataRoot,
// uploads all18 resources/19bounded chunks and compares every sample via native
// AudioClip.GetData. Does not call Play or change account/gameplay state.
// int32[16] success: {1,0,6,18,19,18,1,1,18,18,1,0,0,18,0,0}.
int32_t ehr_source_ios_audio_loader_probe_v1(int32_t *proof,size_t count);
#ifdef __cplusplus
}
#endif
