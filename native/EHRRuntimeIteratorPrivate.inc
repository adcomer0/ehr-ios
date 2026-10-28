// Included once after REQUIRE_READY inside current EHRRuntimeGateway.mm.
#include "EHRRuntimeIteratorPrivate.h"
#include "EHRRuntimeReflection.h"
#include <cstdlib>
EHRRuntimeStatus EHRRuntimeIteratorPin(EHRRuntimeToken borrowed, EHRRuntimeToken *owned, void **identity) {
    if (!owned || !identity) return EHR_RUNTIME_BAD_ARGUMENT;
    *owned = 0; *identity = nullptr;
    REQUIRE_READY();
    Object *value = nullptr;
    auto status = object(borrowed, &value);
    if (status != EHR_RUNTIME_OK || !value) return status == EHR_RUNTIME_OK ? EHR_RUNTIME_BAD_ARGUMENT : status;
    auto &s = state();
    if (s.roots.size() >= kMaxRoots || s.next == UINT64_MAX) return diagnosticLimit(
        s.roots.size()>=kMaxRoots?ehr_diagnostics::PinRootCapacity:ehr_diagnostics::TokenExhaustion,
        s.roots.size()>=kMaxRoots?s.roots.size():s.next,s.roots.size()>=kMaxRoots?kMaxRoots:UINT64_MAX);
    const uint32_t handle = s.api.gchandle_new(value, true);
    if (!handle) return EHR_RUNTIME_NOT_READY;
    try {
        const auto token = s.next++;
        s.roots.emplace(token, handle); *owned = token;
        *identity = s.api.gchandle_get_target(handle);
        if (*identity) return EHR_RUNTIME_OK;
        s.roots.erase(token);
    } catch (...) { s.api.gchandle_free(handle); return EHR_RUNTIME_LIMIT; }
    s.api.gchandle_free(handle); *owned = 0;
    return EHR_RUNTIME_INVALID_TOKEN;
}
EHRRuntimeStatus EHRRuntimeIteratorBorrow(EHRRuntimeToken borrowed, void **result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = nullptr; REQUIRE_READY();
    // A raw borrow outlives this function's call-local weak promotion. Obtain
    // an independently owned strong root with Pin before borrowing weak self.
    if (weakTokens().count(borrowed)) return EHR_RUNTIME_UNSUPPORTED;
    Object *value = nullptr; const auto status = object(borrowed, &value);
    if (status == EHR_RUNTIME_OK) *result = value;
    return status;
}
void EHRRuntimeIteratorRaise(EHRRuntimeStatus status) {
    // No native pointer enters NativeAOT, and no native exception crosses it.
    const auto raise = reinterpret_cast<void (*)(Exception *)>(symbol("il2cpp_raise_exception"));
    if (!raise || ready() != EHR_RUNTIME_OK) abort();
    const char *name = status == EHR_RUNTIME_UNSUPPORTED ? "NotSupportedException" : "InvalidOperationException";
    EHRRuntimeToken exceptionClass = 0;
    OwnedObjectToken exception, constructionException;
    auto result = ehr_runtime_find_class("mscorlib.dll", "System", name, &exceptionClass);
    if (result == EHR_RUNTIME_OK)
        result = ehr_runtime_construct(exceptionClass, nullptr, 0, &exception.value, &constructionException.value);
    void *value = nullptr;
    const auto token = constructionException.value ? constructionException.value : exception.value;
    if (result != EHR_RUNTIME_OK && !constructionException.value) abort();
    if (EHRRuntimeIteratorBorrow(token, &value) != EHR_RUNTIME_OK || !value) abort();
    raise(static_cast<Exception *>(value));
    abort(); // Export is noreturn in this runtime; returning would hide failure.
}
