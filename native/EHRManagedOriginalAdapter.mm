#include "EHRRuntimeOriginal.h"
#include "EHRManagedOriginalV1.h"
#include <array>
#include <memory>
#include <limits>
#include <unordered_map>

static_assert(sizeof(EHRManagedGatewayV1) == 152, "Do not change the core gateway ABI");
static_assert(sizeof(EHRManagedOriginalV1) == 40, "OriginalV1 must stay a separate fixed table");
static_assert(sizeof(EHRManagedOriginalProofV1) == 24);
static_assert(sizeof(EHROriginalInvocationProofV1) == 24);
static_assert(sizeof(EHRManagedOriginalSelfTestV1) == 64);

namespace {
struct OriginalPool {
    std::array<uint64_t, 2> roots{};
    bool nativeClosed = false;
};
std::unordered_map<uint64_t, std::unique_ptr<OriginalPool>> &pools() {
    static std::unordered_map<uint64_t, std::unique_ptr<OriginalPool>> value;
    return value;
}
bool overlap(const void *left, size_t leftSize, const void *right, size_t rightSize) {
    const auto a = reinterpret_cast<uintptr_t>(left), b = reinterpret_cast<uintptr_t>(right);
    if (!a || !b || leftSize > std::numeric_limits<uintptr_t>::max() - a ||
        rightSize > std::numeric_limits<uintptr_t>::max() - b) return true;
    return a < b + rightSize && b < a + leftSize;
}
int32_t targetMethod(uint64_t target, uint64_t *method) {
    try { return ehr_runtime_original_target_method(target, method); }
    catch (...) { if (method) *method = 0; return EHR_RUNTIME_UNSUPPORTED; }
}
int32_t begin(uint64_t target, uint64_t method, uint64_t *invocation) {
    if (!invocation) return EHR_RUNTIME_BAD_ARGUMENT;
    *invocation = 0;
    const auto ready = ehr_runtime_initialize();
    if (ready != EHR_RUNTIME_OK) return ready;
    uint64_t token = 0;
    try {
        // Allocate pool storage before opening the native invocation, so an
        // allocation failure cannot leave an untracked native capability.
        auto pool = std::make_unique<OriginalPool>();
        auto status = ehr_runtime_original_begin(target, method, &token);
        if (status != EHR_RUNTIME_OK) return status;
        if (!pools().emplace(token, std::move(pool)).second) {
            ehr_runtime_original_end(token);
            return EHR_RUNTIME_BAD_ARGUMENT;
        }
        *invocation = token;
        return EHR_RUNTIME_OK;
    } catch (...) {
        if (token) ehr_runtime_original_end(token);
        return EHR_RUNTIME_UNSUPPORTED;
    }
}
int32_t invoke(uint64_t invocation, uint64_t target, uint64_t method, uint64_t instance,
    const EHRManagedArgumentV1 *arguments, size_t count, uint64_t *result, uint64_t *exception,
    EHRManagedOriginalProofV1 *proof, size_t proofSize) {
    if (!result || !exception || !proof || result == exception || proofSize != sizeof(*proof) ||
        count > 128 || (count && !arguments) ||
        overlap(result, sizeof(*result), exception, sizeof(*exception)) ||
        overlap(result, sizeof(*result), proof, sizeof(*proof)) ||
        overlap(exception, sizeof(*exception), proof, sizeof(*proof))) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = *exception = 0;
    *proof = {1, sizeof(*proof), 0, 0, 0, 0};
    const auto ready = ehr_runtime_initialize();
    if (ready != EHR_RUNTIME_OK) return ready;
    auto found = pools().find(invocation);
    if (found == pools().end()) return EHR_RUNTIME_INVALID_TOKEN;
    OriginalPool &pool = *found->second;
    if (pool.nativeClosed) return EHR_RUNTIME_INVALID_TOKEN;
    try {
        EHRRuntimeArgument converted[128];
        for (size_t i = 0; i < count; ++i) {
            const auto &value = arguments[i];
            converted[i] = {value.kind, value.reserved, value.token, value.bytes, value.byte_count};
        }
        uint64_t returned = 0, raised = 0;
        EHROriginalInvocationProofV1 nativeProof{};
        const auto status = ehr_runtime_invoke_original(invocation, target, method, instance,
            count ? converted : nullptr, count, &returned, &raised, &nativeProof, sizeof(nativeProof));
        // One accepted native request returns at most one result and exception
        // root. The native route rejects a repeat before creating either root.
        if ((returned && pool.roots[0]) || (raised && pool.roots[1])) {
            if (returned) ehr_runtime_object_release(returned);
            if (raised) ehr_runtime_object_release(raised);
            return EHR_RUNTIME_BAD_ARGUMENT;
        }
        if (returned) pool.roots[0] = returned;
        if (raised) pool.roots[1] = raised;
        *result = returned; *exception = raised;
        *proof = {nativeProof.abi_version, nativeProof.byte_size, nativeProof.original_request_accepted,
            nativeProof.runtime_invoke_entered, nativeProof.permit_consumed, nativeProof.hook_consumptions};
        return status;
    } catch (...) { return EHR_RUNTIME_UNSUPPORTED; }
}
int32_t end(uint64_t invocation) {
    const auto ready = ehr_runtime_initialize();
    if (ready != EHR_RUNTIME_OK) return ready;
    auto found = pools().find(invocation);
    if (found == pools().end()) return EHR_RUNTIME_INVALID_TOKEN;
    try {
        OriginalPool &pool = *found->second;
        if (!pool.nativeClosed) {
            const auto status = ehr_runtime_original_end(invocation);
            if (status != EHR_RUNTIME_OK) return status;
            pool.nativeClosed = true;
        }
        // Expire the native capability before releasing its roots. If release
        // and deferred enqueue both fail, retain that root in this pool and
        // return its failure; a later End can retry without losing ownership.
        int32_t releaseStatus = EHR_RUNTIME_OK;
        for (auto &root : pool.roots) if (root) {
            const auto released = ehr_runtime_object_release(root);
            if (released == EHR_RUNTIME_OK) root = 0;
            else {
                const auto deferred = ehr_runtime_object_release_deferred(root);
                if (deferred == EHR_RUNTIME_OK) root = 0;
                else releaseStatus = deferred;
            }
        }
        if (!pool.roots[0] && !pool.roots[1]) pools().erase(found);
        return releaseStatus;
    } catch (...) { return EHR_RUNTIME_UNSUPPORTED; }
}
}

void EHRManagedOriginalMakeTable(EHRManagedOriginalV1 *table) noexcept {
    if (table) *table = {1, sizeof(*table), targetMethod, begin, invoke, end};
}
uint64_t EHRManagedOriginalOpenPoolCount(void) noexcept { return pools().size(); }
uint64_t EHRManagedOriginalPooledRootCount(void) noexcept {
    uint64_t count = 0;
    for (const auto &entry : pools()) for (const auto token : entry.second->roots) if (token) ++count;
    return count;
}
