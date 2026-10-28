#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct EHRManagedReflectionV1 {
    uint32_t abi_version;
    uint32_t byte_size;
    int32_t (*class_from_type_object)(uint64_t, uint64_t *);
    int32_t (*make_generic_class)(uint64_t, const uint64_t *, size_t, uint64_t *, uint64_t *);
    int32_t (*construct)(uint64_t, const uint64_t *, size_t, uint64_t *, uint64_t *);
    int32_t (*initialize_class)(uint64_t, uint64_t *);
} EHRManagedReflectionV1;
int32_t ehr_generated_bind_reflection(const EHRManagedReflectionV1 *, size_t);
// Four Int32 outputs: pass, status, live mutations/copy, enumeration version guard.
int32_t ehr_generated_list_self_test(int32_t *, size_t);
#ifdef __cplusplus
}
#endif
