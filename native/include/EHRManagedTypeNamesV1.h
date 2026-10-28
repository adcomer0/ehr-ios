#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct EHRManagedTypeNamesV1 {
    uint32_t abi_version;
    uint32_t byte_size;
    int32_t (*class_type_name)(uint64_t, char *, size_t, size_t *);
    int32_t (*vector_class)(uint64_t, uint64_t *);
} EHRManagedTypeNamesV1;
int32_t ehr_generated_bind_type_names(const EHRManagedTypeNamesV1 *, size_t);
#ifdef __cplusplus
}
#endif
