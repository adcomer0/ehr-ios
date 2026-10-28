#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Metadata/native association only: no constructor, cctor or gameplay call.
int32_t EHRGameStartIteratorPrepare(void);
// Activation is explicit, main-thread, and belongs after full source startup.
// Disable before source failure cleanup. Inactive hooks forward original once.
int32_t EHRGameStartIteratorSetEnabled(int32_t enabled);
NSDictionary *EHRGameStartIteratorCopyStatus(void);
// Own fabricated iterators + copied production callbacks; no original MoveNext
// or real host factory. A null owner is allowed ONLY by its internal test seam.
NSDictionary *EHRGameStartIteratorSelfTest(void);
bool ehr_native_game_start_move_next_hook(void *self,const void *methodInfo);
#ifdef __cplusplus
}
#endif
