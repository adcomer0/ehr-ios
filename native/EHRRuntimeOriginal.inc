// Included once by EHRRuntimeGateway.mm after its existing private helpers and
// REQUIRE_READY macro. It deliberately shares that gateway's owned metadata and
// roots; it introduces no object layouts, address offsets or raw-pointer ABI.
#include "EHRRuntimeOriginal.h"
#include "EHROriginalInvocationGate.hpp"
#include <atomic>
#include <memory>

namespace {
struct OriginalRoute {
    EHRRuntimeToken methodToken = 0;
    const Method *method = nullptr;
    uint64_t expectedRVA = 0;
};
struct OriginalCall {
    uint64_t target = 0;
    EHRRuntimeToken methodToken = 0;
    const Method *method = nullptr;
    bool attempted = false, inProgress = false, runtimeEntered = false, consumed = false;
    uint32_t hookConsumptions = 0;
    EHRRuntimeStatus routingFailure = EHR_RUNTIME_OK;
};
struct OriginalRoutes {
    OriginalRoute version;
    std::unordered_map<uint64_t, OriginalRoute> registered;
    uint64_t nextInvocation = UINT64_C(0x4f52490000000001);
    std::unordered_map<EHROriginalInvocationToken, std::unique_ptr<OriginalCall>> calls;
};
OriginalRoutes &originalRoutes() { static OriginalRoutes value; return value; }
thread_local OriginalCall *activeOriginalCall = nullptr;
std::atomic<uint64_t> originalBypasses{0};

EHRRuntimeStatus originalRoute(uint64_t target, const OriginalRoute **result) {
    *result = nullptr;
    if (target != EHR_ORIGINAL_TARGET_BROADCAST_VERSION) {
        const auto found = originalRoutes().registered.find(target);
        if (found == originalRoutes().registered.end()) return EHR_RUNTIME_NOT_FOUND;
        *result = &found->second;
        return EHR_RUNTIME_OK;
    }
    auto &route = originalRoutes().version;
    if (!route.method) {
        EHRRuntimeToken constants = 0, token = 0;
        auto status = ehr_runtime_find_class("Assembly-CSharp.dll", "", "Constants", &constants);
        if (status != EHR_RUNTIME_OK) return status;
        status = ehr_runtime_find_method(constants, "GetBroadcastVersion", nullptr, 0,
                                         "System.Int32", 1, &token);
        if (status != EHR_RUNTIME_OK) return status;
        const Metadata *resolved = lookup(token, MetadataKind::Method);
        const RuntimeClass *expected = klass(constants);
        if (!resolved || resolved->owner != expected) return EHR_RUNTIME_TYPE_MISMATCH;
        const Method *method = static_cast<const Method *>(resolved->pointer);
        if (state().api.method_get_declaring_type(method) != expected ||
            state().api.method_is_generic(method)) return EHR_RUNTIME_TYPE_MISMATCH;
        route = {token, method, 0};
    }
    *result = &route;
    return EHR_RUNTIME_OK;
}
EHRRuntimeStatus exactOriginalMethod(const OriginalRoute &route, EHRRuntimeToken token) {
    const Metadata *method = lookup(token, MetadataKind::Method);
    if (!method) return EHR_RUNTIME_INVALID_TOKEN;
    return token == route.methodToken && method->pointer == route.method ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH;
}
struct ActiveOriginalScope {
    OriginalCall &call;
    OriginalCall *previous;
    explicit ActiveOriginalScope(OriginalCall &value) : call(value), previous(activeOriginalCall) {
        call.inProgress = true;
        activeOriginalCall = &call;
    }
    ~ActiveOriginalScope() {
        activeOriginalCall = previous;
        call.inProgress = false;
    }
};

// Used by both existing caught invocation entry points. Preflight never holds a
// bypass permit. Nested ordinary facade invokes after entry get no new permit.
Object *invokeWithOriginalPermit(const Method *method, void *instance,
    void **arguments, Exception **exception) {
    OriginalCall *call = activeOriginalCall;
    if (!call || call->runtimeEntered)
        return state().api.runtime_invoke(method, instance, arguments, exception);
    if (method != call->method) {
        call->routingFailure = EHR_RUNTIME_TYPE_MISMATCH;
        return nullptr;
    }
    call->runtimeEntered = true;
    ehr::OriginalInvocationPermit permit(call->target, method);
    struct ProofOnExit {
        OriginalCall &call;
        const ehr::OriginalInvocationPermit &permit;
        ~ProofOnExit() { call.consumed = permit.consumed(); }
    } proof{*call, permit};
    return state().api.runtime_invoke(method, instance, arguments, exception);
}
void originalProof(const OriginalCall &call, EHROriginalInvocationProofV1 *proof) {
    *proof = {1, sizeof(*proof), call.attempted ? 1u : 0u, call.runtimeEntered ? 1u : 0u,
              call.consumed ? 1u : 0u, call.hookConsumptions};
}
}

bool EHRTryConsumeOriginalInvocation(uint64_t target, const void *method) noexcept {
    if (!ehr::OriginalInvocationPermit::tryConsume(target, method)) return false;
    OriginalCall *call = activeOriginalCall;
    if (call && call->target == target && call->method == method) ++call->hookConsumptions;
    originalBypasses.fetch_add(1, std::memory_order_relaxed);
    return true;
}
uint64_t EHROriginalInvocationBypassCount(void) noexcept {
    return originalBypasses.load(std::memory_order_relaxed);
}
extern "C" EHRRuntimeStatus ehr_runtime_original_register(uint64_t target,
    EHRRuntimeToken token, uint64_t expectedRVA) {
    REQUIRE_READY();
    if (target <= EHR_ORIGINAL_TARGET_BROADCAST_VERSION || !expectedRVA || expectedRVA % 4)
        return EHR_RUNTIME_BAD_ARGUMENT;
    try {
        const Metadata *resolved = lookup(token, MetadataKind::Method);
        if (!resolved) return EHR_RUNTIME_INVALID_TOKEN;
        const OriginalRoute *version = nullptr;
        auto status = originalRoute(EHR_ORIGINAL_TARGET_BROADCAST_VERSION, &version);
        if (status != EHR_RUNTIME_OK) return status;
        const Method *method = static_cast<const Method *>(resolved->pointer);
        if (method == version->method) return EHR_RUNTIME_TYPE_MISMATCH;
        auto &routes = originalRoutes().registered;
        const auto prior = routes.find(target);
        if (prior != routes.end())
            return prior->second.methodToken == token && prior->second.method == method &&
                prior->second.expectedRVA == expectedRVA ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH;
        for (const auto &route : routes)
            if (route.second.method == method || route.second.expectedRVA == expectedRVA)
                return EHR_RUNTIME_TYPE_MISMATCH;
        if (routes.size() >= 512) return EHR_RUNTIME_LIMIT;
        uint64_t observed = 0;
        status = ehr_runtime_validate_native_method(token, expectedRVA, &observed);
        if (status != EHR_RUNTIME_OK) return status;
        if (observed != expectedRVA) return EHR_RUNTIME_TYPE_MISMATCH;
        routes.emplace(target, OriginalRoute{token, method, expectedRVA});
        return EHR_RUNTIME_OK;
    } catch (...) { return EHR_RUNTIME_UNSUPPORTED; }
}
extern "C" EHRRuntimeStatus ehr_runtime_original_target_method(uint64_t target, EHRRuntimeToken *method) {
    if (!method) return EHR_RUNTIME_BAD_ARGUMENT;
    *method = 0;
    REQUIRE_READY();
    try {
        const OriginalRoute *route = nullptr;
        const auto status = originalRoute(target, &route);
        if (status == EHR_RUNTIME_OK) *method = route->methodToken;
        return status;
    } catch (...) { return EHR_RUNTIME_UNSUPPORTED; }
}
extern "C" EHRRuntimeStatus ehr_runtime_original_begin(uint64_t target,
    EHRRuntimeToken method, EHROriginalInvocationToken *invocation) {
    if (!invocation) return EHR_RUNTIME_BAD_ARGUMENT;
    *invocation = 0;
    REQUIRE_READY();
    try {
        const OriginalRoute *route = nullptr;
        auto status = originalRoute(target, &route);
        if (status != EHR_RUNTIME_OK) return status;
        status = exactOriginalMethod(*route, method);
        if (status != EHR_RUNTIME_OK) return status;
        auto &routes = originalRoutes();
        if (routes.calls.size() >= 1024 || routes.nextInvocation == UINT64_MAX) return EHR_RUNTIME_LIMIT;
        const auto token = routes.nextInvocation++;
        auto call = std::make_unique<OriginalCall>();
        call->target = target; call->methodToken = method; call->method = route->method;
        routes.calls.emplace(token, std::move(call));
        *invocation = token;
        return EHR_RUNTIME_OK;
    } catch (...) { return EHR_RUNTIME_UNSUPPORTED; }
}
extern "C" EHRRuntimeStatus ehr_runtime_original_end(EHROriginalInvocationToken invocation) {
    REQUIRE_READY();
    auto &calls = originalRoutes().calls;
    const auto found = calls.find(invocation);
    if (found == calls.end()) return EHR_RUNTIME_INVALID_TOKEN;
    if (found->second->inProgress) return EHR_RUNTIME_BAD_ARGUMENT;
    calls.erase(found);
    return EHR_RUNTIME_OK;
}
static EHRRuntimeStatus invokeOriginal(EHROriginalInvocationToken invocation,
    uint64_t target, EHRRuntimeToken method, EHRRuntimeToken instance,
    const EHRRuntimeArgument *arguments, size_t count,
    const EHRRuntimeByRefOutput *outputs, size_t outputCount, bool explicitRefs,
    EHRRuntimeToken *result, EHRRuntimeToken *exception,
    EHROriginalInvocationProofV1 *proof, size_t proofSize) {
    if (!result || !exception || !proof || proofSize != sizeof(*proof) ||
        overlaps(result, sizeof(*result), exception, sizeof(*exception)) ||
        overlaps(result, sizeof(*result), proof, sizeof(*proof)) ||
        overlaps(exception, sizeof(*exception), proof, sizeof(*proof))) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = *exception = 0;
    *proof = {1, sizeof(*proof), 0, 0, 0, 0};
    REQUIRE_READY();
    const auto found = originalRoutes().calls.find(invocation);
    if (found == originalRoutes().calls.end()) return EHR_RUNTIME_INVALID_TOKEN;
    OriginalCall &call = *found->second;
    if (target != call.target || method != call.methodToken) return EHR_RUNTIME_TYPE_MISMATCH;
    const OriginalRoute *route = nullptr;
    auto status = originalRoute(target, &route);
    if (status != EHR_RUNTIME_OK) return status;
    status = exactOriginalMethod(*route, method);
    if (status != EHR_RUNTIME_OK) return status;
    if (call.attempted || call.inProgress) return EHR_RUNTIME_BAD_ARGUMENT;
    call.attempted = true;
    try {
        // A static initializer can recursively call this same getter. Complete
        // it through the caught gateway before installing the one-shot permit,
        // so that such a call cannot consume the outer method's permit.
        const Metadata *resolved = lookup(method, MetadataKind::Method);
        if (!staticFieldSupported(resolved->owner)) {
            status = ehr_runtime_initialize_class(metadata(MetadataKind::Klass, resolved->owner, resolved->owner), exception);
            if (status != EHR_RUNTIME_OK) { originalProof(call, proof); return status; }
        }
        ActiveOriginalScope scope(call);
        status = explicitRefs ? ehr_runtime_invoke_with_refs(method, instance, arguments, count,
            outputs, outputCount, result, exception) :
            ehr_runtime_invoke(method, instance, arguments, count, result, exception);
        if (call.routingFailure != EHR_RUNTIME_OK) status = call.routingFailure;
    } catch (...) { status = EHR_RUNTIME_UNSUPPORTED; }
    originalProof(call, proof);
    if (status == EHR_RUNTIME_OK && (!call.consumed || call.hookConsumptions != 1)) {
        if (*result) ehr_runtime_object_release(*result);
        *result = 0;
        return EHR_RUNTIME_UNSUPPORTED;
    }
    return status;
}
extern "C" EHRRuntimeStatus ehr_runtime_invoke_original(EHROriginalInvocationToken invocation,
    uint64_t target, EHRRuntimeToken method, EHRRuntimeToken instance,
    const EHRRuntimeArgument *arguments, size_t count,
    EHRRuntimeToken *result, EHRRuntimeToken *exception,
    EHROriginalInvocationProofV1 *proof, size_t proofSize) {
    return invokeOriginal(invocation,target,method,instance,arguments,count,nullptr,0,false,
        result,exception,proof,proofSize);
}
extern "C" EHRRuntimeStatus ehr_runtime_invoke_original_with_refs(EHROriginalInvocationToken invocation,
    uint64_t target, EHRRuntimeToken method, EHRRuntimeToken instance,
    const EHRRuntimeArgument *arguments, size_t count,
    const EHRRuntimeByRefOutput *outputs, size_t outputCount,
    EHRRuntimeToken *result, EHRRuntimeToken *exception,
    EHROriginalInvocationProofV1 *proof, size_t proofSize) {
    return invokeOriginal(invocation,target,method,instance,arguments,count,outputs,outputCount,true,
        result,exception,proof,proofSize);
}
