#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// Independent pure managed export. Exactly10 output words, initialized by the
// callee; no game/runtime pointer, filesystem, account or network operation.
//0=pass,1=role colors,2=option presets,3=case-sensitive UserData,
//4=numeric achievement enum,5=exact request property names,6=translation stream,
//7=numeric combo dictionary keys,8=tags/presets/news,9=JSON reflection disabled.
// Return0 means words0..8 passed. Require word9==1 separately for NativeAOT.
int32_t ehr_source_json_self_test_v1(uint32_t *output,size_t count);
#ifdef __cplusplus
}
#endif
