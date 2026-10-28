#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Main-thread only, AFTER source application Prepare (own data root configured).
// Does not call source Main, game actions, AudioSource, SoundManager or Play.
// Count16. Success return0: [0]=1,[1]=0,[2]=8,[3..12]=1,[13]=18,[14]=0,[15]=0.
// [2] stage:1fixtures,2resources,3paths,4APIs,5created,6roundtrip,7offset,8cleanup.
// [12] means actual Destroy scheduled + owned gateway root released, not an
// immediate native-engine destruction claim. [14] is dynamic-code flags.
int32_t ehr_source_audio_data_probe_v1(int32_t *proof,size_t count);
int32_t ehr_source_audio_copy_error_v1(uint8_t *output,size_t capacity,size_t *required);
// Separate OPTIONAL muted route, main-thread after full real source Load.
// Finds an existing active SoundManager via public Unity Object.FindObjectOfType;
// no singleton getter, AddComponent or Instantiate is called by this probe.
// The native manager retains responsibility for its normal internal source pool.
// Own eight-zero-sample clip at volume0; stop targets only that clip. Count16.
// Return0: [0]=1,[1]=0,[2]=7,[3..10]=1,[11]=0,[12]=8,[13]=1,[14..15]=0.
// Return3 at stage1 means no existing manager; no getter/create/play was forced.
int32_t ehr_source_muted_sound_probe_v1(int32_t *proof,size_t count);
#ifdef __cplusplus
}
#endif
