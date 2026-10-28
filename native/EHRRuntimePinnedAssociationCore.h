#pragma once
#include "EHRRuntimePinnedAssociation.h"
#include <cstring>
#include <limits>
#include <vector>

namespace ehr_pinned {
struct ExecutableRange { uintptr_t begin; uint64_t size; };
struct VerifiedImage {
    uintptr_t base = 0;
    uintptr_t header_end = 0;
    bool uuid_verified = false, source_verified = false, candidate_hash_verified = false;
    std::vector<ExecutableRange> executable_file_ranges;
};
// The production caller must validate image provenance before entering this
// function. Tests supply ORIGINAL own byte storage, not copied game structures.
inline EHRRuntimeStatus compare_known_layout(const MethodFacts &facts,
    const VerifiedImage &image, uint64_t expected_rva, uint64_t *observed_rva) {
    if (!observed_rva) return EHR_RUNTIME_BAD_ARGUMENT;
    *observed_rva = 0;
    if (!expected_rva || expected_rva % 4) return EHR_RUNTIME_BAD_ARGUMENT;
    if (!image.uuid_verified || !image.source_verified || !image.candidate_hash_verified ||
        !image.base || image.header_end <= image.base) return EHR_RUNTIME_UNSUPPORTED;
    if (!facts.method || !facts.metadata_owner || !facts.public_declaring_class ||
        !facts.public_name || !facts.public_token) return EHR_RUNTIME_BAD_ARGUMENT;
    if ((facts.public_token >> 24) != 6 || !(facts.public_token & 0xffffff) ||
        facts.metadata_owner != facts.public_declaring_class) return EHR_RUNTIME_TYPE_MISMATCH;
    static_assert(sizeof(uintptr_t) == 8, "Pinned ARM64 layout requires 64-bit pointers");
    const auto *bytes = static_cast<const unsigned char *>(facts.method);
    uintptr_t target = 0, name = 0, owner = 0;
    uint32_t token = 0;
    // These four offsets are proven by this exact framework's runtime_invoke,
    // method_get_name, method_get_declaring_type and method_get_token exports.
    // memcpy avoids pointer-alignment/aliasing assumptions about opaque storage.
    memcpy(&target, bytes, sizeof(target));
    memcpy(&name, bytes + 0x18, sizeof(name));
    memcpy(&owner, bytes + 0x20, sizeof(owner));
    memcpy(&token, bytes + 0x48, sizeof(token));
    if (name != reinterpret_cast<uintptr_t>(facts.public_name) ||
        owner != reinterpret_cast<uintptr_t>(facts.public_declaring_class) || token != facts.public_token)
        return EHR_RUNTIME_TYPE_MISMATCH;
    if (!target) return EHR_RUNTIME_UNSUPPORTED;
    if (target % 4 || target < image.header_end) return EHR_RUNTIME_TYPE_MISMATCH;
    size_t executable = 0;
    for (const auto &range : image.executable_file_ranges) {
        if (range.size <= std::numeric_limits<uintptr_t>::max() - range.begin &&
            target >= range.begin && target - range.begin <= range.size &&
            4 <= range.size - (target - range.begin)) ++executable;
    }
    if (executable != 1 || target < image.base) return EHR_RUNTIME_TYPE_MISMATCH;
    *observed_rva = target - image.base;
    return *observed_rva == expected_rva ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH;
}
}
