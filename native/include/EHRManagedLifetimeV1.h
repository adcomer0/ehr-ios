#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct EHRManagedLifetimeV1 {
    uint32_t abi_version;
    uint32_t byte_size;
    int32_t (*object_same)(uint64_t, uint64_t, int32_t *);
    int32_t (*object_identity_hash)(uint64_t, int32_t *, uint64_t *);
    int32_t (*object_release_deferred)(uint64_t);
    int32_t (*drain_deferred_releases)(size_t *);
} EHRManagedLifetimeV1;
int32_t ehr_generated_bind_lifetime(const EHRManagedLifetimeV1 *, size_t);
// Six Int32 outputs: pass,status,same-object identity,distinct object,
// idempotent disposal,worker/finalizer reclamation. Uses own boxed test values.
int32_t ehr_generated_lifetime_self_test(int32_t *, size_t);
#ifdef __cplusplus
}
#endif
