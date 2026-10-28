#pragma once
#include "EHRRuntimeGateway.h"
// INTERNAL NATIVE INTERFACE ONLY. These borrowed pointers come from the
// gateway's own metadata token map and exported runtime APIs, never from C#.
// This UUID/source-hash-specific adapter does not define a portable MethodInfo
// layout and never calls the copied native target or asserts a callback ABI.
namespace ehr_pinned {
struct MethodFacts {
    const void *method;
    const void *metadata_owner;
    const void *public_declaring_class;
    const char *public_name;
    uint32_t public_token;
};
EHRRuntimeStatus validate(const MethodFacts &facts, uint64_t expected_rva,
                          uint64_t *observed_rva);
// Verifies the exact source allowlist, loaded UUID, whole signed candidate
// SHA256, and that this entry is in its file-backed executable ranges.
EHRRuntimeStatus validate_engine_entry(const void *entry);
}
