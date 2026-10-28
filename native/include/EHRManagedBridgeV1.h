#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

// Matches EHRRuntimeGateway.h ABI 1. All callbacks must obey that gateway's
// Unity-main-thread, strong-root ownership, exact-type and unsupported-call rules.
// Function table and payload sizes are checked before use; no struct-return ABI.
typedef uint64_t EHRManagedToken;
typedef struct EHRManagedArgumentV1 {
    uint32_t kind;
    uint32_t reserved;
    EHRManagedToken token;
    const void *bytes;
    size_t byte_count;
} EHRManagedArgumentV1;
typedef struct EHRManagedGatewayV1 {
    uint32_t abi_version;
    uint32_t byte_size;
    uint32_t (*runtime_abi_version)(void);
    int32_t (*initialize)(void);
    int32_t (*find_class)(const char *, const char *, const char *, uint64_t *);
    int32_t (*object_class)(uint64_t, uint64_t *);
    int32_t (*find_method)(uint64_t, const char *, const char *const *, size_t, const char *, int, uint64_t *);
    int32_t (*find_field)(uint64_t, const char *, const char *, int, uint64_t *);
    int32_t (*invoke)(uint64_t, uint64_t, const EHRManagedArgumentV1 *, size_t, uint64_t *, uint64_t *);
    int32_t (*read_field)(uint64_t, uint64_t, uint64_t *);
    int32_t (*write_field)(uint64_t, uint64_t, const EHRManagedArgumentV1 *);
    int32_t (*value_size)(uint64_t, size_t *);
    int32_t (*box)(uint64_t, const void *, size_t, uint64_t *);
    int32_t (*copy_value)(uint64_t, void *, size_t, size_t *);
    int32_t (*string_create)(const uint16_t *, size_t, uint64_t *);
    int32_t (*string_copy)(uint64_t, uint16_t *, size_t, size_t *);
    int32_t (*object_release)(uint64_t);
    int32_t (*object_retain)(uint64_t, uint64_t *);
    // Optional diagnostics for the pinned native entry hook; they do not mutate
    // game state. Both are required for the live self-test to report success.
    uint64_t (*broadcast_callback_count)(void);
    int32_t (*pinned_image_observed)(void);
} EHRManagedGatewayV1;

typedef struct EHRManagedSelfTestV1 {
    uint32_t abi_version;
    uint32_t byte_size;
    int32_t pass;
    int32_t status;
    int32_t dynamic_code_flags;
    int32_t actual_getter_value;
    int32_t offline_value;
    int32_t online_value;
    int32_t expected_online_value;
    int32_t pinned_image_observed;
    uint64_t callbacks_before;
    uint64_t callbacks_after;
    uint64_t rooted_results_released;
} EHRManagedSelfTestV1;

int32_t ehr_managed_bind_gateway(const EHRManagedGatewayV1 *, size_t);
int32_t ehr_managed_gateway_self_test(EHRManagedSelfTestV1 *, size_t);
// Executes exact unchanged upstream ServerUpdatePatch.Postfix through compile
// adapters. Native caller supplies its observed network mode. Always invoke the
// original native game getter before applying this postfix.
int32_t ehr_managed_server_version_postfix(int32_t original, int32_t online,
                                        int32_t local, int32_t *result);
int32_t ehr_managed_abi_version(void);
int32_t ehr_managed_dynamic_code_flags(void);
int32_t ehr_source_integer_option(int32_t min, int32_t max, int32_t step, int32_t index);
float ehr_source_float_option(float min, float max, float step, int32_t index);
int32_t ehr_managed_is_version_modded_prefix(int32_t *result, int32_t *run_original);
#ifdef __cplusplus
}
#endif
