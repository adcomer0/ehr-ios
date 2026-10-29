// Included once after REQUIRE_READY inside current EHRRuntimeGateway.mm.
#include "EHRRuntimeIteratorPrivate.h"
#include "EHRRuntimeReflection.h"
#include "EHRIteratorTerminalMarker.hpp"
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
namespace ehr_iterator_terminal {
struct State {
    ehr_iterators::TerminalMarker cache;
    RuntimeClass *carrierClass = nullptr;
    Field *field = nullptr;
    EHRRuntimeToken markerRoot = 0; // One pinned private object for runtime lifetime.
    Object *marker = nullptr;
};
State terminalStateValue;
State &terminalState() { return terminalStateValue; }
template<class F> EHRRuntimeStatus contain(F action) {
    @try { try { return action(); } catch (...) { return EHR_RUNTIME_MANAGED_EXCEPTION; } }
    @catch (__unused NSException *error) { return EHR_RUNTIME_MANAGED_EXCEPTION; }
}
EHRRuntimeStatus prepare(EHRRuntimeToken carrier) {
    REQUIRE_READY();
    Object *value = nullptr;
    auto status = object(carrier, &value);
    if (status != EHR_RUNTIME_OK || !value) return status == EHR_RUNTIME_OK ? EHR_RUNTIME_BAD_ARGUMENT : status;
    auto &s = terminalState(); auto &api = state().api;
    if (s.cache.ready())
        return api.object_get_class(value) == s.carrierClass && s.cache.hasClassHeader(value, s.carrierClass)
            ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH;
    EHRRuntimeToken carrierClass = 0, fieldToken = 0, objectClass = 0;
    status = ehr_runtime_find_class("mscorlib.dll", "System.Collections", "ArrayList+ArrayListEnumeratorSimple", &carrierClass);
    if (status == EHR_RUNTIME_OK)
        status = ehr_runtime_find_field(carrierClass, "_currentElement", "System.Object", 0, &fieldToken);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_class("mscorlib.dll", "System", "Object", &objectClass);
    if (status != EHR_RUNTIME_OK) return status;
    auto *expected = klass(carrierClass);
    const auto *field = lookup(fieldToken, MetadataKind::Field);
    if (!expected || !field || field->owner != expected ||
        api.object_get_class(value) != expected || !s.cache.hasClassHeader(value, expected)) return EHR_RUNTIME_TYPE_MISMATCH;
    auto *reference = const_cast<Field *>(static_cast<const Field *>(field->pointer));
    if (api.field_get_flags(reference) & (kStatic | kInitOnly | kLiteral)) return EHR_RUNTIME_TYPE_MISMATCH;
    const auto instanceSize = reinterpret_cast<uint32_t (*)(RuntimeClass *)>(symbol("il2cpp_class_instance_size"));
    const auto fieldOffset = reinterpret_cast<size_t (*)(Field *)>(symbol("il2cpp_field_get_offset"));
    const auto headerSize = reinterpret_cast<uint32_t (*)()>(symbol("il2cpp_object_header_size"));
    if (!instanceSize || !fieldOffset || !headerSize) return EHR_RUNTIME_NOT_FOUND;
    for (const auto address : {reinterpret_cast<const void *>(instanceSize), reinterpret_cast<const void *>(fieldOffset), reinterpret_cast<const void *>(headerSize)}) {
        status = ehr_pinned::validate_engine_entry(address);
        if (status != EHR_RUNTIME_OK) return status;
    }
    const size_t size = instanceSize(expected), offset = fieldOffset(reference), header = headerSize();
    OwnedObjectToken marker, exception, pinned;
    status = ehr_runtime_construct(objectClass, nullptr, 0, &marker.value, &exception.value);
    if (status != EHR_RUNTIME_OK || exception.value) return status == EHR_RUNTIME_OK ? EHR_RUNTIME_MANAGED_EXCEPTION : status;
    void *identity = nullptr;
    status = EHRRuntimeIteratorPin(marker.value, &pinned.value, &identity);
    if (status != EHR_RUNTIME_OK) return status;
    if (api.object_get_class(static_cast<Object *>(identity)) != klass(objectClass)) return EHR_RUNTIME_TYPE_MISMATCH;
    // All fallible validation precedes publishing the immutable worker cache.
    if (!s.cache.configure(expected, identity, offset, size, header)) return EHR_RUNTIME_TYPE_MISMATCH;
    s.carrierClass = expected; s.field = reference; s.marker = static_cast<Object *>(identity);
    s.markerRoot = pinned.take();
    return EHR_RUNTIME_OK;
}
}
EHRRuntimeStatus EHRRuntimeIteratorTerminalPrepare(EHRRuntimeToken carrier) {
    return ehr_iterator_terminal::contain([&] { return ehr_iterator_terminal::prepare(carrier); });
}
EHRRuntimeStatus EHRRuntimeIteratorMarkTerminal(EHRRuntimeToken carrier) {
    return ehr_iterator_terminal::contain([&]() -> EHRRuntimeStatus {
        // The caller already holds a gateway-created strong pin and the
        // registry publication lock. Do not attach threads, schedule drains,
        // invoke managed constructors or promote weak handles under that lock.
        if (!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
        if (!state().loaded) return EHR_RUNTIME_NOT_READY;
        auto &s = ehr_iterator_terminal::terminalState();
        if (!s.cache.ready()) return EHR_RUNTIME_NOT_READY;
        Object *value = nullptr; const auto status = object(carrier, &value);
        if (status != EHR_RUNTIME_OK || !value) return status == EHR_RUNTIME_OK ? EHR_RUNTIME_BAD_ARGUMENT : status;
        auto &api = state().api;
        if (api.object_get_class(value) != s.carrierClass || !s.cache.hasClassHeader(value, s.carrierClass)) return EHR_RUNTIME_TYPE_MISMATCH;
        // The registry still contains this exact pinned identity. Workers take
        // that route and cannot read this payload while the barrier writes it.
        api.field_set_value_object(value, s.field, s.marker);
        return api.field_get_value_object(s.field, value) == s.marker && s.cache.contains(value)
            ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH;
    });
}
bool EHRRuntimeIteratorIsTerminal(const void *identity) noexcept {
    return ehr_iterator_terminal::terminalState().cache.contains(identity);
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
