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
namespace ehr_iterator_exception {
struct FactoryAPI {
    const Image *(*corlib)() = nullptr;
    Exception *(*create)(const Image *, const char *, const char *, const char *) = nullptr;
    void (*raise)(Exception *) = nullptr;
    const Image *core = nullptr;
};
struct Counts { uint64_t created = 0, released = 0; };
// This root deliberately does not enter the gateway token map. An iterator
// failure must remain raisable when that map has reached its capacity. Only
// the real runtime's UInt32 GC-handle API owns the pinned object lifetime.
struct NativeException {
    uint32_t handle = 0;
    Object *identity = nullptr;
    RuntimeClass *expected = nullptr;
    FactoryAPI factory{};
    void (*release)(uint32_t) = nullptr;
    Counts *counts = nullptr;
    NativeException() = default;
    NativeException(const NativeException &) = delete;
    NativeException &operator=(const NativeException &) = delete;
    ~NativeException() {
        if (handle) { release(handle); if (counts) ++counts->released; }
    }
    void take(NativeException &other) {
        handle = other.handle; identity = other.identity; expected = other.expected;
        factory = other.factory; release = other.release; counts = other.counts;
        other.handle = 0; other.identity = nullptr;
    }
};
EHRRuntimeStatus prepare(EHRRuntimeStatus failure, FactoryAPI &factory, RuntimeClass **expected) {
    *expected = nullptr;
    if (failure <= EHR_RUNTIME_OK || failure > EHR_RUNTIME_AMBIGUOUS) return EHR_RUNTIME_BAD_ARGUMENT;
    const auto readiness = ready(); if (readiness != EHR_RUNTIME_OK) return readiness;
    factory.corlib = reinterpret_cast<decltype(factory.corlib)>(symbol("il2cpp_get_corlib"));
    factory.create = reinterpret_cast<decltype(factory.create)>(symbol("il2cpp_exception_from_name_msg"));
    factory.raise = reinterpret_cast<decltype(factory.raise)>(symbol("il2cpp_raise_exception"));
    auto &api = state().api;
    const void *entries[] = {
        reinterpret_cast<const void *>(factory.corlib), reinterpret_cast<const void *>(factory.create),
        reinterpret_cast<const void *>(factory.raise), reinterpret_cast<const void *>(api.image_get_name),
        reinterpret_cast<const void *>(api.class_from_name), reinterpret_cast<const void *>(api.class_get_name),
        reinterpret_cast<const void *>(api.class_get_namespace), reinterpret_cast<const void *>(api.class_is_assignable_from),
        reinterpret_cast<const void *>(api.object_get_class), reinterpret_cast<const void *>(api.gchandle_new),
        reinterpret_cast<const void *>(api.gchandle_get_target), reinterpret_cast<const void *>(api.gchandle_free)
    };
    for (const void *entry : entries) {
        if (!entry) return EHR_RUNTIME_NOT_FOUND;
        const auto status = ehr_pinned::validate_engine_entry(entry);
        if (status != EHR_RUNTIME_OK) return status;
    }
    factory.core = factory.corlib();
    if (!factory.core) return EHR_RUNTIME_NOT_READY;
    const char *imageName = api.image_get_name(factory.core);
    if (!imageName || strcmp(imageName, "mscorlib.dll")) return EHR_RUNTIME_TYPE_MISMATCH;
    const char *name = failure == EHR_RUNTIME_UNSUPPORTED ? "NotSupportedException" : "InvalidOperationException";
    RuntimeClass *base = api.class_from_name(factory.core, "System", "Exception");
    *expected = api.class_from_name(factory.core, "System", name);
    if (!base || !*expected) return EHR_RUNTIME_NOT_FOUND;
    const char *actualName = api.class_get_name(*expected), *space = api.class_get_namespace(*expected);
    if (!actualName || !space || strcmp(actualName, name) || strcmp(space, "System") ||
        !api.class_is_assignable_from(base, *expected)) return EHR_RUNTIME_TYPE_MISMATCH;
    return EHR_RUNTIME_OK;
}
EHRRuntimeStatus make(EHRRuntimeStatus failure, NativeException &output, Counts *counts = nullptr) {
    if (output.handle) return EHR_RUNTIME_BAD_ARGUMENT;
    @try { try {
        NativeException value; auto status = prepare(failure, value.factory, &value.expected);
        if (status != EHR_RUNTIME_OK) return status;
        const char *name = failure == EHR_RUNTIME_UNSUPPORTED ? "NotSupportedException" : "InvalidOperationException";
        Object *created = reinterpret_cast<Object *>(value.factory.create(value.factory.core, "System", name, "EHR source iterator failed."));
        if (!created) return EHR_RUNTIME_NOT_READY;
        auto &api = state().api;
        value.handle = api.gchandle_new(created, true);
        if (!value.handle) return EHR_RUNTIME_NOT_READY;
        value.release = api.gchandle_free; value.counts = counts;
        if (counts) ++counts->created;
        value.identity = api.gchandle_get_target(value.handle);
        if (!value.identity || api.object_get_class(value.identity) != value.expected) return EHR_RUNTIME_TYPE_MISMATCH;
        output.take(value); return EHR_RUNTIME_OK;
    } catch (...) { return EHR_RUNTIME_MANAGED_EXCEPTION; } }
    @catch (__unused NSException *error) { return EHR_RUNTIME_MANAGED_EXCEPTION; }
}
}
void EHRRuntimeIteratorRaise(EHRRuntimeStatus status) {
    // No native pointer enters NativeAOT, and no native exception crosses it.
    ehr_iterator_exception::NativeException exception;
    if (ehr_iterator_exception::make(status, exception) != EHR_RUNTIME_OK) abort();
    exception.factory.raise(reinterpret_cast<Exception *>(exception.identity));
    abort(); // Export is noreturn in this runtime; returning would hide failure.
}
extern "C" __attribute__((visibility("default")))
NSDictionary *EHRRuntimeIteratorExceptionSelfTest(void) {
    using namespace ehr_iterator_exception;
    if (!NSThread.isMainThread) return @{@"schema":@"ehr.iterator-exception-factory-proof.v1",@"success":@NO,@"status":@(EHR_RUNTIME_WRONG_THREAD)};
    const size_t before = state().roots.size(); Counts counts;
    uint32_t constructed = 0, exactTypes = 0, caught = 0, returned = 0;
    EHRRuntimeStatus status = EHR_RUNTIME_OK;
    const EHRRuntimeStatus failures[] = {EHR_RUNTIME_BAD_ARGUMENT, EHR_RUNTIME_UNSUPPORTED};
    @try { try {
        for (size_t i = 0; i < 2; ++i) {
            NativeException exception;
            status = make(failures[i], exception, &counts);
            if (status != EHR_RUNTIME_OK) break;
            constructed |= uint32_t(1) << i;
            if (state().api.object_get_class(exception.identity) == exception.expected) exactTypes |= uint32_t(1) << i;
            // The real public runtime raise and its C++ catch are both native.
            // No .NET callback or raw exception-wrapper layout is inspected.
            try { exception.factory.raise(reinterpret_cast<Exception *>(exception.identity)); returned |= uint32_t(1) << i; }
            catch (...) { caught |= uint32_t(1) << i; }
            if (state().api.gchandle_get_target(exception.handle) != exception.identity ||
                state().api.object_get_class(exception.identity) != exception.expected) { status = EHR_RUNTIME_TYPE_MISMATCH; break; }
        }
    } catch (...) { status = EHR_RUNTIME_MANAGED_EXCEPTION; } }
    @catch (__unused NSException *error) { status = EHR_RUNTIME_MANAGED_EXCEPTION; }
    const size_t after = state().roots.size();
    const bool success = status == EHR_RUNTIME_OK && constructed == 3 && exactTypes == 3 && caught == 3 &&
        !returned && counts.created == 2 && counts.released == 2 && before == after;
    return @{@"schema":@"ehr.iterator-exception-factory-proof.v1",@"success":@(success),@"status":@(status),
        @"constructedMask":@(constructed),@"exactTypeMask":@(exactTypes),@"caughtMask":@(caught),@"returnedMask":@(returned),
        @"nativeHandlesCreated":@(counts.created),@"nativeHandlesReleased":@(counts.released),
        @"rootsBefore":@(before),@"rootsAfter":@(after),@"rootAccountingBalanced":@(before == after && counts.created == counts.released),
        @"reflectionActivatorUsed":@NO,@"nativeAotCallbackEntered":@NO,@"gameOwnerInvoked":@NO,@"accountOrNetworkActions":@NO,
        @"directPublicApiExploratoryProbe":@NO};
}
