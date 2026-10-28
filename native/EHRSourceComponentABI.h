#pragma once
#include "EHRRuntimeGateway.h"
#ifdef __cplusplus
extern "C" {
#endif
// Separate ABI, core GatewayV1 remains 152 bytes. Tokens below are owned
// gateway IDs, never pointers/GCHandle values. Callback creates consumes its
// owned weak self on entry even if construction fails.
typedef struct EHRSourceComponentNativeV1 {
 uint32_t abi_version,byte_size;
 EHRRuntimeStatus (*register_type)(uint32_t);
 EHRRuntimeStatus (*type_class)(uint32_t,EHRRuntimeToken *);
 EHRRuntimeStatus (*add)(uint32_t,EHRRuntimeToken,uint64_t *,EHRRuntimeToken *,EHRRuntimeToken *);
 EHRRuntimeStatus (*lookup)(uint32_t,EHRRuntimeToken,uint64_t *);
 EHRRuntimeStatus (*weak)(EHRRuntimeToken,EHRRuntimeToken *);
 EHRRuntimeStatus (*weak_alive)(EHRRuntimeToken,int32_t *);
} EHRSourceComponentNativeV1;
typedef struct EHRSourceComponentCallbacksV1 {
 uint32_t abi_version,byte_size;
 int32_t (*create)(uint32_t,EHRRuntimeToken,uint64_t *);
 int32_t (*dispatch)(uint64_t,uint32_t);
 int32_t (*release)(uint64_t);
 int32_t (*count)(uint32_t *);
} EHRSourceComponentCallbacksV1;
#ifdef __cplusplus
}
static_assert(sizeof(EHRSourceComponentNativeV1)==56);
static_assert(sizeof(EHRSourceComponentCallbacksV1)==40);
#endif
