#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct EHRManagedMethodsV1 {
    uint32_t abi_version;
    uint32_t byte_size;
    int32_t (*method_object)(uint64_t,uint64_t *);
    int32_t (*method_from_object)(uint64_t,uint64_t *);
    int32_t (*make_generic_method)(uint64_t,const uint64_t *,size_t,uint64_t *,uint64_t *);
} EHRManagedMethodsV1;
int32_t ehr_generated_bind_methods(const EHRManagedMethodsV1 *,size_t);
int32_t ehr_generated_singleton_self_test(int32_t *,size_t);
#ifdef __cplusplus
}
#endif
