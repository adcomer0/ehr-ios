#import <Foundation/Foundation.h>
#include "EHRRuntimeGateway.h"
#include "EHRRuntimeDiagnostics.h"
#include "EHRRuntimeEngineColor.h"
#include "EHRRuntimePinnedAssociation.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <cstring>
#include <limits>
#include <unordered_map>
#include <unordered_set>
#include <array>
#include <mutex>
#include <dispatch/dispatch.h>
#include <vector>
#include <string>

// Exported Unity 2022.3 runtime APIs only (version-specific internal ABI). IL2CPP layouts, field offsets and native method
// entry addresses are intentionally absent from this gateway.
namespace {
struct Domain;
struct Assembly;
struct Image;
struct RuntimeClass;
struct Type;
struct Object;
struct String;
struct Exception;
struct Method;
struct Field;
constexpr size_t kMaxAssemblies = 512, kMaxMembers = 65536, kMaxParents = 32;
constexpr size_t kMaxArguments = 128, kMaxBytes = 1024 * 1024, kMaxRoots = 65536;
constexpr uint32_t kStatic = 0x10, kInitOnly = 0x20, kLiteral = 0x40;
enum class MetadataKind { Klass, Method, Field };
struct Metadata { MetadataKind kind; const void *pointer; RuntimeClass *owner; };
struct API {
    Domain *(*domain_get)();
    const Assembly **(*domain_get_assemblies)(const Domain *, size_t *);
    const Image *(*assembly_get_image)(const Assembly *);
    const char *(*image_get_name)(const Image *);
    RuntimeClass *(*class_from_name)(const Image *, const char *, const char *);
    RuntimeClass *(*class_get_nested_types)(RuntimeClass *, void **);
    const char *(*class_get_name)(RuntimeClass *);
    const char *(*class_get_namespace)(RuntimeClass *);
    RuntimeClass *(*class_get_parent)(RuntimeClass *);
    RuntimeClass *(*class_from_type)(const Type *);
    RuntimeClass *(*class_from_system_type)(Object *);
    RuntimeClass *(*array_class_get)(RuntimeClass *, uint32_t);
    const Type *(*class_get_type)(RuntimeClass *);
    Object *(*type_get_object)(const Type *);
    bool (*class_is_assignable_from)(RuntimeClass *, RuntimeClass *);
    bool (*class_is_valuetype)(const RuntimeClass *);
    bool (*class_is_generic)(const RuntimeClass *);
    bool (*class_is_inflated)(const RuntimeClass *);
    bool (*class_has_references)(RuntimeClass *);
    bool (*class_is_blittable)(const RuntimeClass *);
    int32_t (*class_value_size)(RuntimeClass *, uint32_t *);
    const Method *(*class_get_methods)(RuntimeClass *, void **);
    Field *(*class_get_fields)(RuntimeClass *, void **);
    const char *(*method_get_name)(const Method *);
    uint32_t (*method_get_token)(const Method *);
    uint32_t (*method_get_flags)(const Method *, uint32_t *);
    uint32_t (*method_get_param_count)(const Method *);
    const Type *(*method_get_param)(const Method *, uint32_t);
    const Type *(*method_get_return_type)(const Method *);
    RuntimeClass *(*method_get_declaring_type)(const Method *);
    bool (*method_is_generic)(const Method *);
    bool (*method_is_inflated)(const Method *);
    Object *(*method_get_object)(const Method *, RuntimeClass *);
    const Method *(*method_get_from_reflection)(Object *);
    const char *(*field_get_name)(Field *);
    int (*field_get_flags)(Field *);
    const Type *(*field_get_type)(Field *);
    Object *(*field_get_value_object)(Field *, Object *);
    void (*field_set_value)(Object *, Field *, void *);
    void (*field_set_value_object)(Object *, Field *, Object *);
    void (*field_static_set_value)(Field *, void *);
    char *(*type_get_name)(const Type *);
    int (*type_get_type)(const Type *);
    bool (*type_is_byref)(const Type *);
    void (*runtime_free)(void *);
    Object *(*runtime_invoke)(const Method *, void *, void **, Exception **);
    RuntimeClass *(*object_get_class)(Object *);
    const Method *(*object_get_virtual_method)(Object *, const Method *);
    void *(*object_unbox)(Object *);
    Object *(*value_box)(RuntimeClass *, void *);
    String *(*string_new_utf16)(const uint16_t *, int32_t);
    int32_t (*string_length)(String *);
    const uint16_t *(*string_chars)(String *);
    void *(*thread_current)();
    void *(*thread_attach)(Domain *);
    // Exact Unity 2022.3 UInt32 GC-handle signatures, pinned to this runtime.
    uint32_t (*gchandle_new)(Object *, bool);
    Object *(*gchandle_get_target)(uint32_t);
    void (*gchandle_free)(uint32_t);
};
struct State {
    API api{};
    bool loaded = false;
    void *framework = nullptr;
    EHRRuntimeToken next = 1;
    std::unordered_map<EHRRuntimeToken, Metadata> metadata;
    std::unordered_map<const void *, EHRRuntimeToken> metadataIDs;
    std::unordered_map<EHRRuntimeToken, uint32_t> roots;
    std::unordered_set<RuntimeClass *> initializedClasses;
    std::unordered_set<RuntimeClass *> initializingClasses;
    std::mutex deferredMutex;
    std::array<EHRRuntimeToken, kMaxRoots> deferred{};
    size_t deferredHead = 0, deferredCount = 0;
    bool deferredDrainScheduled = false;
    uint64_t deferredEnqueued=0,deferredDequeued=0,deferredReleased=0,deferredFull=0;
    size_t deferredHighWater=0;
};
State &state() { static State value; return value; }
EHRRuntimeStatus diagnosticLimit(uint32_t category,uint64_t count,uint64_t limit);
void deferredDrainCallback(void *);
void scheduleDeferredDrainIfNeeded() {
    auto &s = state();
    bool schedule = false;
    {
        std::lock_guard<std::mutex> lock(s.deferredMutex);
        if (s.deferredCount && !s.deferredDrainScheduled) {
            s.deferredDrainScheduled = true;
            schedule = true;
        }
    }
    if (schedule) dispatch_async_f(dispatch_get_main_queue(), nullptr, deferredDrainCallback);
}
void *symbol(const char *name) {
    if (void *value = dlsym(RTLD_DEFAULT, name)) return value;
    auto &s = state();
    if (!s.framework) {
        for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
            const char *path = _dyld_get_image_name(i);
            if (path && strstr(path, "/UnityFramework.framework/UnityFramework")) {
                s.framework = dlopen(path, RTLD_LAZY | RTLD_NOLOAD);
                if (s.framework) break;
            }
        }
    }
    return s.framework ? dlsym(s.framework, name) : nullptr;
}
bool load() {
    auto &s = state();
    if (s.loaded) return true;
    bool complete = true;
#define LOAD(member, name) s.api.member = reinterpret_cast<decltype(s.api.member)>(symbol(name)); complete = complete && s.api.member
    LOAD(domain_get, "il2cpp_domain_get");
    LOAD(domain_get_assemblies, "il2cpp_domain_get_assemblies");
    LOAD(assembly_get_image, "il2cpp_assembly_get_image");
    LOAD(image_get_name, "il2cpp_image_get_name");
    LOAD(class_from_name, "il2cpp_class_from_name");
    LOAD(class_get_nested_types, "il2cpp_class_get_nested_types");
    LOAD(class_get_name, "il2cpp_class_get_name");
    LOAD(class_get_namespace, "il2cpp_class_get_namespace");
    LOAD(class_get_parent, "il2cpp_class_get_parent");
    LOAD(class_from_type, "il2cpp_class_from_type");
    // Reflection conversion is an optional capability, not a prerequisite for
    // existing gateway operations on other inspected runtime versions.
    s.api.class_from_system_type = reinterpret_cast<decltype(s.api.class_from_system_type)>(symbol("il2cpp_class_from_system_type"));
    s.api.array_class_get = reinterpret_cast<decltype(s.api.array_class_get)>(symbol("il2cpp_array_class_get"));
    LOAD(class_get_type, "il2cpp_class_get_type");
    LOAD(type_get_object, "il2cpp_type_get_object");
    LOAD(class_is_assignable_from, "il2cpp_class_is_assignable_from");
    LOAD(class_is_valuetype, "il2cpp_class_is_valuetype");
    LOAD(class_is_generic, "il2cpp_class_is_generic");
    LOAD(class_is_inflated, "il2cpp_class_is_inflated");
    LOAD(class_has_references, "il2cpp_class_has_references");
    LOAD(class_is_blittable, "il2cpp_class_is_blittable");
    LOAD(class_value_size, "il2cpp_class_value_size");
    LOAD(class_get_methods, "il2cpp_class_get_methods");
    LOAD(class_get_fields, "il2cpp_class_get_fields");
    LOAD(method_get_name, "il2cpp_method_get_name");
    // Optional, version-pinned native association capability.
    s.api.method_get_token = reinterpret_cast<decltype(s.api.method_get_token)>(symbol("il2cpp_method_get_token"));
    LOAD(method_get_flags, "il2cpp_method_get_flags");
    LOAD(method_get_param_count, "il2cpp_method_get_param_count");
    LOAD(method_get_param, "il2cpp_method_get_param");
    LOAD(method_get_return_type, "il2cpp_method_get_return_type");
    LOAD(method_get_declaring_type, "il2cpp_method_get_declaring_type");
    LOAD(method_is_generic, "il2cpp_method_is_generic");
    s.api.method_is_inflated = reinterpret_cast<decltype(s.api.method_is_inflated)>(symbol("il2cpp_method_is_inflated"));
    s.api.method_get_object = reinterpret_cast<decltype(s.api.method_get_object)>(symbol("il2cpp_method_get_object"));
    s.api.method_get_from_reflection = reinterpret_cast<decltype(s.api.method_get_from_reflection)>(symbol("il2cpp_method_get_from_reflection"));
    LOAD(field_get_name, "il2cpp_field_get_name");
    LOAD(field_get_flags, "il2cpp_field_get_flags");
    LOAD(field_get_type, "il2cpp_field_get_type");
    LOAD(field_get_value_object, "il2cpp_field_get_value_object");
    LOAD(field_set_value, "il2cpp_field_set_value");
    LOAD(field_set_value_object, "il2cpp_field_set_value_object");
    LOAD(field_static_set_value, "il2cpp_field_static_set_value");
    LOAD(type_get_name, "il2cpp_type_get_name");
    LOAD(type_get_type, "il2cpp_type_get_type");
    LOAD(type_is_byref, "il2cpp_type_is_byref");
    LOAD(runtime_free, "il2cpp_free");
    LOAD(runtime_invoke, "il2cpp_runtime_invoke");
    LOAD(object_get_class, "il2cpp_object_get_class");
    LOAD(object_get_virtual_method, "il2cpp_object_get_virtual_method");
    LOAD(object_unbox, "il2cpp_object_unbox");
    LOAD(value_box, "il2cpp_value_box");
    LOAD(string_new_utf16, "il2cpp_string_new_utf16");
    LOAD(string_length, "il2cpp_string_length");
    LOAD(string_chars, "il2cpp_string_chars");
    LOAD(thread_current, "il2cpp_thread_current");
    LOAD(thread_attach, "il2cpp_thread_attach");
    LOAD(gchandle_new, "il2cpp_gchandle_new");
    LOAD(gchandle_get_target, "il2cpp_gchandle_get_target");
    LOAD(gchandle_free, "il2cpp_gchandle_free");
#undef LOAD
    s.loaded = complete;
    return complete;
}
EHRRuntimeStatus ready() {
    if (![NSThread isMainThread]) return EHR_RUNTIME_WRONG_THREAD;
    if (!load()) return EHR_RUNTIME_NOT_READY;
    Domain *domain = state().api.domain_get();
    if (!domain) return EHR_RUNTIME_NOT_READY;
    if (!state().api.thread_current() && !state().api.thread_attach(domain)) return EHR_RUNTIME_NOT_READY;
    scheduleDeferredDrainIfNeeded();
    return EHR_RUNTIME_OK;
}
bool text(const char *s) { return s && strnlen(s, 4097) <= 4096; }
EHRRuntimeToken metadata(MetadataKind kind, const void *pointer, RuntimeClass *owner) {
    auto &s = state();
    const auto prior = s.metadataIDs.find(pointer);
    if (prior != s.metadataIDs.end()) return prior->second;
    const auto token = s.next++;
    s.metadata.emplace(token, Metadata{kind, pointer, owner});
    s.metadataIDs.emplace(pointer, token);
    return token;
}
const Metadata *lookup(EHRRuntimeToken token, MetadataKind kind) {
    const auto found = state().metadata.find(token);
    return found != state().metadata.end() && found->second.kind == kind ? &found->second : nullptr;
}
RuntimeClass *klass(EHRRuntimeToken token) {
    const auto m = lookup(token, MetadataKind::Klass);
    return m ? const_cast<RuntimeClass *>(static_cast<const RuntimeClass *>(m->pointer)) : nullptr;
}
#include "EHRRuntimeWeakPrelude.inc"
EHRRuntimeStatus diagnosticLimit(uint32_t category,uint64_t count,uint64_t limit) {
    EHRRuntimeGatewayPublishDiagnosticSnapshot();
    EHRDiagnosticLimit(category,count,limit);return EHR_RUNTIME_LIMIT;
}
EHRRuntimeStatus object(EHRRuntimeToken token, Object **value) {
    *value = nullptr;
    if (!token) return EHR_RUNTIME_OK;
    const auto found = state().roots.find(token);
    if (found == state().roots.end()) return EHR_RUNTIME_INVALID_TOKEN;
    if(weakTokens().count(token)){
        if(!WeakTokenScope::current)return EHR_RUNTIME_UNSUPPORTED;
        return WeakTokenScope::current->promote(token,found->second,value);
    }
    *value = state().api.gchandle_get_target(found->second);
    return *value ? EHR_RUNTIME_OK : EHR_RUNTIME_INVALID_TOKEN;
}
EHRRuntimeStatus root(Object *value, EHRRuntimeToken *result) {
    *result = 0;
    if (!value) return EHR_RUNTIME_OK;
    auto &s = state();
    if (s.roots.size() >= kMaxRoots) return diagnosticLimit(ehr_diagnostics::RootCapacity,s.roots.size(),kMaxRoots);
    const uint32_t handle = s.api.gchandle_new(value, false);
    if (!handle) return EHR_RUNTIME_NOT_READY;
    const auto token = s.next++;
    s.roots.emplace(token, handle);
    *result = token;
    return EHR_RUNTIME_OK;
}
bool named(const Type *type, const char *name) {
    if (!type) return false;
    char *actual = state().api.type_get_name(type);
    const bool equal = actual && !strcmp(actual, name);
    if (actual) state().api.runtime_free(actual);
    return equal;
}
bool referenceType(const Type *type) {
    if (!type || state().api.type_is_byref(type)) return false;
    const int kind = state().api.type_get_type(type);
    // Generic instantiations can be either class or struct; let the runtime's
    // class identity determine which. Pointers/function pointers/typedref are
    // deliberately excluded instead of being marshalled as object references.
    if (kind != 0x0e && kind != 0x12 && kind != 0x14 && kind != 0x1c && kind != 0x1d && kind != 0x15) return false;
    RuntimeClass *c = state().api.class_from_type(type);
    return c && !state().api.class_is_valuetype(c);
}
EHRRuntimeStatus valueSize(RuntimeClass *c, size_t *size) {
    *size = 0;
    auto &api = state().api;
    if (api.class_is_generic(c) && !api.class_is_inflated(c)) return EHR_RUNTIME_UNSUPPORTED;
    if (!api.class_is_valuetype(c) || api.class_has_references(c)) return EHR_RUNTIME_UNSUPPORTED;
    uint32_t align = 0;
    const int32_t length = api.class_value_size(c, &align);
    if (length <= 0 || static_cast<size_t>(length) > kMaxBytes) return diagnosticLimit(ehr_diagnostics::ValueSize,length>0?uint64_t(length):0,kMaxBytes);
    const int kind = api.type_get_type(api.class_get_type(c));
    const bool managedScalar = (kind == 0x02 && length == 1) || (kind == 0x03 && length == 2);
    if (!api.class_is_blittable(c) && !managedScalar) return EHR_RUNTIME_UNSUPPORTED;
    if (align > alignof(uint64_t)) return EHR_RUNTIME_UNSUPPORTED;
    *size = static_cast<size_t>(length);
    return EHR_RUNTIME_OK;
}
struct Prepared {
    Object *reference = nullptr;
    std::vector<uint64_t> aligned;
    void *argument = nullptr;
    uint32_t pinnedHandle = 0;
    Prepared() = default;
    Prepared(const Prepared &) = delete;
    Prepared &operator=(const Prepared &) = delete;
    ~Prepared() {
        if (pinnedHandle) state().api.gchandle_free(pinnedHandle);
    }
};
EHRRuntimeStatus prepareBoxedValue(RuntimeClass *expected, const EHRRuntimeArgument &input, Prepared &p) {
    if (input.reserved) return EHR_RUNTIME_BAD_ARGUMENT;
    if (!expected || !state().api.class_is_valuetype(expected) ||
        (state().api.class_is_generic(expected) && !state().api.class_is_inflated(expected))) return EHR_RUNTIME_UNSUPPORTED;
    if (input.kind != EHR_RUNTIME_BOXED_VALUE || input.bytes || input.byte_count) return EHR_RUNTIME_TYPE_MISMATCH;
    Object *boxed = nullptr;
    auto status = object(input.token, &boxed);
    if (status != EHR_RUNTIME_OK) return status;
    if (!boxed || state().api.object_get_class(boxed) != expected) return EHR_RUNTIME_TYPE_MISMATCH;
    // A mixed struct remains in a managed, rooted object. Its contents never
    // cross the ABI as bytes, and the pin outlives the complete invocation.
    p.pinnedHandle = state().api.gchandle_new(boxed, true);
    if (!p.pinnedHandle) return EHR_RUNTIME_NOT_READY;
    Object *pinned = state().api.gchandle_get_target(p.pinnedHandle);
    if (!pinned || state().api.object_get_class(pinned) != expected) return EHR_RUNTIME_TYPE_MISMATCH;
    p.argument = state().api.object_unbox(pinned);
    return p.argument ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH;
}
EHRRuntimeStatus prepareValue(RuntimeClass *expected, const EHRRuntimeArgument &input, Prepared &p) {
    if (input.reserved) return EHR_RUNTIME_BAD_ARGUMENT;
    if (!expected || !state().api.class_is_valuetype(expected)) return EHR_RUNTIME_UNSUPPORTED;
    if (input.kind != EHR_RUNTIME_VALUE || !input.bytes || klass(input.token) != expected) return EHR_RUNTIME_TYPE_MISMATCH;
    size_t bytes = 0;
    auto status = valueSize(expected, &bytes);
    if (status != EHR_RUNTIME_OK) return status;
    if (input.byte_count != bytes) return EHR_RUNTIME_TYPE_MISMATCH;
    p.aligned.resize((bytes + sizeof(uint64_t) - 1) / sizeof(uint64_t));
    memcpy(p.aligned.data(), input.bytes, bytes);
    p.argument = p.aligned.data();
    return EHR_RUNTIME_OK;
}
EHRRuntimeStatus prepareDispatchReceiver(const Method *method, Object *target,
    Prepared &pinned, const Method **dispatchMethod, void **invokeThis) {
    auto &api = state().api;
    *dispatchMethod = target ? api.object_get_virtual_method(target, method) : method;
    *invokeThis = target;
    if (!*dispatchMethod) return EHR_RUNTIME_UNSUPPORTED;
    if (!target) return EHR_RUNTIME_OK;
    RuntimeClass *declaring = api.method_get_declaring_type(*dispatchMethod);
    RuntimeClass *actual = api.object_get_class(target);
    if (!declaring || !actual) return EHR_RUNTIME_TYPE_MISMATCH;
    const bool actualValue = api.class_is_valuetype(actual);
    const bool declaredValue = api.class_is_valuetype(declaring);
    if (declaredValue && (!actualValue || declaring != actual)) return EHR_RUNTIME_TYPE_MISMATCH;
    if (!actualValue) return EHR_RUNTIME_OK;
    pinned.pinnedHandle = api.gchandle_new(target, true);
    if (!pinned.pinnedHandle) return EHR_RUNTIME_NOT_READY;
    pinned.reference = api.gchandle_get_target(pinned.pinnedHandle);
    if (!pinned.reference || api.object_get_class(pinned.reference) != actual) return EHR_RUNTIME_TYPE_MISMATCH;
    // Verified Unity 2022 invokers forward obj unchanged as native this.
    // Choose its representation from the RESOLVED declaring class: Object's
    // own methods still expect a boxed object even when its runtime class is a
    // struct. Value-declared methods expect the exported unbox result instead.
    *invokeThis = declaredValue ? api.object_unbox(pinned.reference) : pinned.reference;
    return *invokeThis ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH;
}
EHRRuntimeStatus prepare(const Type *type, const EHRRuntimeArgument &input, Prepared &p) {
    if (input.reserved) return EHR_RUNTIME_BAD_ARGUMENT;
    if (!type || state().api.type_is_byref(type)) return EHR_RUNTIME_UNSUPPORTED;
    const int kind = state().api.type_get_type(type);
    if (kind == 0x01 || kind == 0x0f || kind == 0x13 || kind == 0x16 || kind == 0x1b || kind == 0x1e) return EHR_RUNTIME_UNSUPPORTED;
    if (referenceType(type)) {
        if (input.kind != EHR_RUNTIME_REFERENCE || input.bytes || input.byte_count) return EHR_RUNTIME_TYPE_MISMATCH;
        auto status = object(input.token, &p.reference);
        if (status != EHR_RUNTIME_OK) return status;
        RuntimeClass *expected = state().api.class_from_type(type);
        if (p.reference && !state().api.class_is_assignable_from(expected, state().api.object_get_class(p.reference))) return EHR_RUNTIME_TYPE_MISMATCH;
        p.argument = p.reference; // runtime_invoke expects the object, not &object
        return EHR_RUNTIME_OK;
    }
    RuntimeClass *expected = state().api.class_from_type(type);
    return input.kind == EHR_RUNTIME_BOXED_VALUE ? prepareBoxedValue(expected, input, p) : prepareValue(expected, input, p);
}
struct RefCopyback { size_t index; void *bytes; size_t byteCount; };
bool addressSpan(const void *pointer, size_t count, uintptr_t &begin, uintptr_t &end) {
    begin = reinterpret_cast<uintptr_t>(pointer);
    if (!pointer || !count || count > std::numeric_limits<uintptr_t>::max() - begin) return false;
    end = begin + count;
    return true;
}
bool overlaps(const void *left, size_t leftCount, const void *right, size_t rightCount) {
    uintptr_t leftBegin = 0, leftEnd = 0, rightBegin = 0, rightEnd = 0;
    if (!addressSpan(left, leftCount, leftBegin, leftEnd) || !addressSpan(right, rightCount, rightBegin, rightEnd)) return true;
    return leftBegin < rightEnd && rightBegin < leftEnd;
}
EHRRuntimeStatus initializeTypeNameOutput(char *utf8, size_t capacity, size_t *required) {
    if (!required) return EHR_RUNTIME_BAD_ARGUMENT;
    if (capacity && utf8 && overlaps(utf8, capacity, required, sizeof(*required)))
        return EHR_RUNTIME_BAD_ARGUMENT;
    *required = 0;
    if (capacity && !utf8) return EHR_RUNTIME_BAD_ARGUMENT;
    if (capacity) utf8[0] = 0;
    return EHR_RUNTIME_OK;
}
EHRRuntimeStatus copyTypeName(const Type *type, char *utf8, size_t capacity, size_t *required) {
    if (!type) return EHR_RUNTIME_NOT_FOUND;
    struct OwnedName {
        char *value;
        ~OwnedName() { if (value) state().api.runtime_free(value); }
    };
    try {
        // type_get_name allocates using the runtime allocator. Copy the whole
        // bounded name before freeing it; its pointer never crosses the ABI.
        const OwnedName name{state().api.type_get_name(type)};
        if (!name.value) return EHR_RUNTIME_NOT_READY;
        const size_t length = strnlen(name.value, kMaxBytes);
        if (length == kMaxBytes) return diagnosticLimit(ehr_diagnostics::TypeNameLength,length,kMaxBytes);
        *required = length + 1;
        if (capacity < *required) {if(capacity||utf8)return diagnosticLimit(ehr_diagnostics::TypeNameCapacity,*required,capacity);return EHR_RUNTIME_LIMIT;}
        memcpy(utf8, name.value, *required);
        return EHR_RUNTIME_OK;
    } catch (...) {
        return EHR_RUNTIME_UNSUPPORTED;
    }
}
EHRRuntimeStatus receiver(const Metadata &m, bool isStatic, EHRRuntimeToken token, Object **target) {
    if (isStatic) {
        *target = nullptr;
        return token == 0 ? EHR_RUNTIME_OK : EHR_RUNTIME_BAD_ARGUMENT;
    }
    auto status = object(token, target);
    if (status != EHR_RUNTIME_OK) return status;
    if (!*target) return EHR_RUNTIME_BAD_ARGUMENT;
    return state().api.class_is_assignable_from(m.owner, state().api.object_get_class(*target)) ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH;
}
bool staticFieldSupported(RuntimeClass *owner) {
    // Metadata initialization and .cctor completion are different in IL2CPP.
    // Do not mistake class_is_inited for a successful managed class initializer.
    // Only a completed, caught managed initializer unlocks this shape.
    if (state().initializedClasses.count(owner)) return true;
    void *iter = nullptr;
    for (size_t i = 0; i < kMaxMembers; ++i) {
        const Method *m = state().api.class_get_methods(owner, &iter);
        if (!m) return true;
        const char *name = state().api.method_get_name(m);
        if (name && !strcmp(name, ".cctor")) return false;
    }
    return false;
}
struct OwnedObjectToken {
    EHRRuntimeToken value = 0;
    OwnedObjectToken() = default;
    OwnedObjectToken(const OwnedObjectToken &) = delete;
    OwnedObjectToken &operator=(const OwnedObjectToken &) = delete;
    ~OwnedObjectToken() { if (value) ehr_runtime_object_release(value); }
    EHRRuntimeToken take() { const auto result = value; value = 0; return result; }
};
struct InitializingClassScope {
    RuntimeClass *owner;
    explicit InitializingClassScope(RuntimeClass *value) : owner(value) {
        state().initializingClasses.insert(owner);
    }
    ~InitializingClassScope() { state().initializingClasses.erase(owner); }
};
size_t drainDeferred(size_t budget) {
    // Main thread and live runtime are established by ready(). The queue lock
    // is never held during root-map mutation or an IL2CPP call.
    auto &s = state();
    size_t freed = 0;
    for (size_t i = 0; i < budget; ++i) {
        EHRRuntimeToken token = 0;
        {
            std::lock_guard<std::mutex> lock(s.deferredMutex);
            if (!s.deferredCount) break;
            token = s.deferred[s.deferredHead];
            s.deferredHead = (s.deferredHead + 1) % kMaxRoots;
            --s.deferredCount;++s.deferredDequeued;
        }
        const auto found = s.roots.find(token);
        if (found == s.roots.end()) continue;
        const uint32_t handle = found->second;
        s.roots.erase(found);weakTokens().erase(token);
        s.api.gchandle_free(handle);
        ++freed;
    }
    {
        std::lock_guard<std::mutex> lock(s.deferredMutex);
        s.deferredDrainScheduled = false;s.deferredReleased+=freed;
    }
    scheduleDeferredDrainIfNeeded();
    EHRRuntimeGatewayPublishDiagnosticSnapshot();
    return freed;
}
void deferredDrainCallback(void *) {
    if (ready() != EHR_RUNTIME_OK) {
        // Preserve roots when Unity is shutting down or unavailable. A later
        // successful gateway call or enqueue can retry, without a busy loop.
        auto &s = state();
        std::lock_guard<std::mutex> lock(s.deferredMutex);
        s.deferredDrainScheduled = false;
        return;
    }
    drainDeferred(1024);
}
}

void EHRRuntimeGatewayPublishDiagnosticSnapshot(void) noexcept {
    if(!NSThread.isMainThread)return;
    auto&s=state();ehr_diagnostics::Gateway value;value.tick=EHRDiagnosticTick();
    value.loaded=s.loaded;value.roots=s.roots.size();value.weak_roots=weakTokens().size();value.root_limit=kMaxRoots;value.deferred_limit=kMaxRoots;
    {std::lock_guard<std::mutex>lock(s.deferredMutex);value.deferred=s.deferredCount;value.deferred_high_water=s.deferredHighWater;
     value.enqueued=s.deferredEnqueued;value.dequeued=s.deferredDequeued;value.released=s.deferredReleased;value.full=s.deferredFull;}
    ehr_diagnostics::state().gateway(value);
}

extern "C" uint32_t ehr_runtime_abi_version(void) { return 1; }
extern "C" EHRRuntimeStatus ehr_runtime_initialize(void) { return ready(); }

#define REQUIRE_READY() WeakTokenScope ehrWeakCallScope_; do { const auto status_ = ready(); if (status_ != EHR_RUNTIME_OK) return status_; } while (0)

#include "EHRRuntimeOriginal.inc"
#include "EHRRuntimeIteratorPrivate.inc"
#include "EHRRuntimeActionPrivate.inc"
#include "EHRRuntimeMetadataPrivate.inc"
#include "EHRRuntimeWeak.inc"

extern "C" EHRRuntimeStatus ehr_runtime_initialize_class(EHRRuntimeToken token, EHRRuntimeToken *exception) {
    if (!exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *exception = 0;
    REQUIRE_READY();
    RuntimeClass *owner = klass(token);
    if (!owner) return EHR_RUNTIME_INVALID_TOKEN;
    auto &s = state();
    if (s.api.class_is_generic(owner) && !s.api.class_is_inflated(owner)) return EHR_RUNTIME_UNSUPPORTED;
    if (s.initializedClasses.count(owner)) return EHR_RUNTIME_OK;
    if (s.initializingClasses.count(owner)) return EHR_RUNTIME_NOT_READY;
    InitializingClassScope initializing(owner);
    OwnedObjectToken typeObject, handleObject, raised, returned;
    auto status = ehr_runtime_class_type_object(token, &typeObject.value);
    if (status != EHR_RUNTIME_OK) return status;
    EHRRuntimeToken typeClass = 0, handleGetter = 0;
    status = ehr_runtime_object_class(typeObject.value, &typeClass);
    if (status != EHR_RUNTIME_OK) return status;
    status = ehr_runtime_find_method(typeClass, "get_TypeHandle", nullptr, 0,
                                     "System.RuntimeTypeHandle", 0, &handleGetter);
    if (status != EHR_RUNTIME_OK) return status;
    status = ehr_runtime_invoke(handleGetter, typeObject.value, nullptr, 0,
                                &handleObject.value, &raised.value);
    if (status != EHR_RUNTIME_OK) {
        *exception = raised.take();
        return status;
    }
    if (!handleObject.value) return EHR_RUNTIME_TYPE_MISMATCH;
    EHRRuntimeToken helpers = 0, runConstructor = 0;
    status = ehr_runtime_find_class("mscorlib.dll", "System.Runtime.CompilerServices", "RuntimeHelpers", &helpers);
    if (status != EHR_RUNTIME_OK) return status;
    const char *parameterTypes[] = {"System.RuntimeTypeHandle"};
    status = ehr_runtime_find_method(helpers, "RunClassConstructor", parameterTypes, 1,
                                     "System.Void", 1, &runConstructor);
    if (status != EHR_RUNTIME_OK) return status;
    EHRRuntimeArgument argument{EHR_RUNTIME_BOXED_VALUE, 0, handleObject.value, nullptr, 0};
    status = ehr_runtime_invoke(runConstructor, 0, &argument, 1, &returned.value, &raised.value);
    if (status != EHR_RUNTIME_OK) {
        *exception = raised.take();
        return status;
    }
    if (returned.value || raised.value) return EHR_RUNTIME_TYPE_MISMATCH;
    s.initializedClasses.insert(owner);
    return EHR_RUNTIME_OK;
}

extern "C" EHRRuntimeStatus ehr_runtime_find_class(const char *imageName, const char *space, const char *name, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    if (!text(imageName) || !text(space) || !text(name) || !*imageName || !*name || strchr(name, '/')) return EHR_RUNTIME_BAD_ARGUMENT;
    try {
        std::vector<std::string> components;
        const char *start = name;
        while (true) {
            const char *separator = strchr(start, '+');
            const size_t length = separator ? static_cast<size_t>(separator - start) : strlen(start);
            if (!length) return EHR_RUNTIME_BAD_ARGUMENT;
            if (components.size() >= kMaxParents) return diagnosticLimit(ehr_diagnostics::NestedDepth,components.size(),kMaxParents);
            components.emplace_back(start, length);
            if (!separator) break;
            start = separator + 1;
        }
        size_t count = 0;
        auto &api = state().api;
        const Assembly **assemblies = api.domain_get_assemblies(api.domain_get(), &count);
        if (!assemblies || count > kMaxAssemblies) return diagnosticLimit(ehr_diagnostics::AssemblyCount,count,kMaxAssemblies);
        RuntimeClass *found = nullptr;
        for (size_t i = 0; i < count; ++i) {
            const Image *image = api.assembly_get_image(assemblies[i]);
            const char *actual = image ? api.image_get_name(image) : nullptr;
            if (!actual || strcmp(actual, imageName)) continue;
            RuntimeClass *candidate = api.class_from_name(image, space, components[0].c_str());
            if (!candidate) continue;
            const char *outerName = api.class_get_name(candidate);
            const char *outerSpace = api.class_get_namespace(candidate);
            if (!outerName || !outerSpace || strcmp(outerName, components[0].c_str()) || strcmp(outerSpace, space)) continue;
            std::vector<RuntimeClass *> path{candidate};
            for (size_t level = 1; level < components.size(); ++level) {
                RuntimeClass *childMatch = nullptr;
                void *iterator = nullptr;
                size_t visited = 0;
                for (; visited < kMaxMembers; ++visited) {
                    RuntimeClass *child = api.class_get_nested_types(candidate, &iterator);
                    if (!child) break;
                    const char *childName = api.class_get_name(child);
                    if (!childName || strcmp(childName, components[level].c_str())) continue;
                    if (childMatch && childMatch != child) return EHR_RUNTIME_AMBIGUOUS;
                    childMatch = child;
                }
                if (visited == kMaxMembers) return diagnosticLimit(ehr_diagnostics::NestedMemberCount,visited,kMaxMembers);
                if (!childMatch) { candidate = nullptr; break; }
                for (RuntimeClass *ancestor : path)
                    if (childMatch == ancestor) return EHR_RUNTIME_UNSUPPORTED;
                path.push_back(childMatch);
                candidate = childMatch;
            }
            if (candidate && found && found != candidate) return EHR_RUNTIME_AMBIGUOUS;
            if (candidate) found = candidate;
        }
        if (!found) return EHR_RUNTIME_NOT_FOUND;
        *result = metadata(MetadataKind::Klass, found, found);
        return EHR_RUNTIME_OK;
    } catch (...) {
        // Metadata setup exports have no exception-out parameter. Missing AOT
        // metadata must not unwind across this public C function.
        return EHR_RUNTIME_UNSUPPORTED;
    }
}
extern "C" EHRRuntimeStatus ehr_runtime_object_class(EHRRuntimeToken token, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    Object *value = nullptr;
    auto status = object(token, &value);
    if (status != EHR_RUNTIME_OK) return status;
    if (!value) return EHR_RUNTIME_BAD_ARGUMENT;
    RuntimeClass *c = state().api.object_get_class(value);
    *result = metadata(MetadataKind::Klass, c, c);
    return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_class_type_object(EHRRuntimeToken token, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    RuntimeClass *c = klass(token);
    if (!c) return EHR_RUNTIME_INVALID_TOKEN;
    return root(state().api.type_get_object(state().api.class_get_type(c)), result);
}
extern "C" EHRRuntimeStatus ehr_runtime_class_from_type_object(EHRRuntimeToken token, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    auto &api = state().api;
    if (!api.class_from_system_type) return EHR_RUNTIME_UNSUPPORTED;
    Object *value = nullptr;
    auto status = object(token, &value);
    if (status != EHR_RUNTIME_OK) return status;
    if (!value) return EHR_RUNTIME_BAD_ARGUMENT;
    // The export accepts the runtime's own reflection object representation,
    // not every user-defined subclass of System.Type. Compare against a real
    // Type object produced by this same runtime before passing the object in.
    EHRRuntimeToken objectClass = 0;
    status = ehr_runtime_find_class("mscorlib.dll", "System", "Object", &objectClass);
    if (status != EHR_RUNTIME_OK) return status;
    OwnedObjectToken canonicalType;
    status = ehr_runtime_class_type_object(objectClass, &canonicalType.value);
    if (status != EHR_RUNTIME_OK) return status;
    Object *canonical = nullptr;
    status = object(canonicalType.value, &canonical);
    if (status != EHR_RUNTIME_OK) return status;
    if (!canonical || api.object_get_class(value) != api.object_get_class(canonical)) return EHR_RUNTIME_TYPE_MISMATCH;
    RuntimeClass *converted = nullptr;
    try {
        // This export also initializes metadata and has no exception-out slot.
        // A missing AOT shape must not unwind through our public C interface.
        converted = api.class_from_system_type(value);
    } catch (...) {
        return EHR_RUNTIME_UNSUPPORTED;
    }
    if (!converted) return EHR_RUNTIME_TYPE_MISMATCH;
    *result = metadata(MetadataKind::Klass, converted, converted);
    return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_class_type_name(EHRRuntimeToken token,
    char *utf8, size_t capacity, size_t *required) {
    const auto status = initializeTypeNameOutput(utf8, capacity, required);
    if (status != EHR_RUNTIME_OK) return status;
    REQUIRE_READY();
    RuntimeClass *c = klass(token);
    if (!c) return EHR_RUNTIME_INVALID_TOKEN;
    return copyTypeName(state().api.class_get_type(c), utf8, capacity, required);
}
extern "C" EHRRuntimeStatus ehr_runtime_field_type_name(EHRRuntimeToken token,
    char *utf8, size_t capacity, size_t *required) {
    const auto status = initializeTypeNameOutput(utf8, capacity, required);
    if (status != EHR_RUNTIME_OK) return status;
    REQUIRE_READY();
    const Metadata *m = lookup(token, MetadataKind::Field);
    if (!m) return EHR_RUNTIME_INVALID_TOKEN;
    Field *field = const_cast<Field *>(static_cast<const Field *>(m->pointer));
    return copyTypeName(state().api.field_get_type(field), utf8, capacity, required);
}
extern "C" EHRRuntimeStatus ehr_runtime_vector_class(EHRRuntimeToken token, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    RuntimeClass *element = klass(token);
    if (!element) return EHR_RUNTIME_INVALID_TOKEN;
    auto &api = state().api;
    if (!api.array_class_get) return EHR_RUNTIME_UNSUPPORTED;
    if (api.class_is_generic(element) && !api.class_is_inflated(element)) return EHR_RUNTIME_UNSUPPORTED;
    const Type *type = api.class_get_type(element);
    if (!type || api.type_is_byref(type)) return EHR_RUNTIME_UNSUPPORTED;
    const int kind = api.type_get_type(type);
    if (kind == 1 || kind == 0x0f || kind == 0x16 || kind == 0x1b) return EHR_RUNTIME_UNSUPPORTED;
    try {
        RuntimeClass *vector = api.array_class_get(element, 1);
        if (!vector) return EHR_RUNTIME_UNSUPPORTED;
        *result = metadata(MetadataKind::Klass, vector, vector);
        return EHR_RUNTIME_OK;
    } catch (...) {
        return EHR_RUNTIME_UNSUPPORTED;
    }
}
extern "C" EHRRuntimeStatus ehr_runtime_validate_native_method(EHRRuntimeToken token,
    uint64_t expected, uint64_t *observed) {
    if (!observed) return EHR_RUNTIME_BAD_ARGUMENT;
    *observed = 0;
    REQUIRE_READY();
    const Metadata *m = lookup(token, MetadataKind::Method);
    if (!m) return EHR_RUNTIME_INVALID_TOKEN;
    if (!expected || expected % 4) return EHR_RUNTIME_BAD_ARGUMENT;
    auto &api = state().api;
    if (!api.method_get_token || !api.method_is_inflated) return EHR_RUNTIME_UNSUPPORTED;
    const Method *method = static_cast<const Method *>(m->pointer);
    if (api.method_is_generic(method) || api.method_is_inflated(method) ||
        (api.class_is_generic(m->owner) && !api.class_is_inflated(m->owner))) return EHR_RUNTIME_UNSUPPORTED;
    const char *name = api.method_get_name(method);
    if (!text(name) || !*name) return EHR_RUNTIME_TYPE_MISMATCH;
    const ehr_pinned::MethodFacts facts{method, m->owner, api.method_get_declaring_type(method),
                                      name, api.method_get_token(method)};
    return ehr_pinned::validate(facts, expected, observed);
}
extern "C" EHRRuntimeStatus ehr_runtime_find_method(EHRRuntimeToken token, const char *name,
    const char *const *params, size_t count, const char *returns, int isStatic, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    RuntimeClass *c = klass(token);
    if (!c) return EHR_RUNTIME_INVALID_TOKEN;
    if (!text(name) || !text(returns) || count > kMaxArguments || (count && !params) || (isStatic != 0 && isStatic != 1)) return EHR_RUNTIME_BAD_ARGUMENT;
    for (size_t i = 0; i < count; ++i) if (!text(params[i])) return EHR_RUNTIME_BAD_ARGUMENT;
    auto &api = state().api;
    for (size_t depth = 0; c && depth < kMaxParents; ++depth, c = api.class_get_parent(c)) {
        void *iter = nullptr;
        const Method *found = nullptr;
        size_t visited = 0;
        for (; visited < kMaxMembers; ++visited) {
            const Method *m = api.class_get_methods(c, &iter);
            if (!m) break;
            const char *actual = api.method_get_name(m);
            uint32_t flags = 0;
            if (!actual || strcmp(actual, name) || api.method_get_param_count(m) != count ||
                !!(api.method_get_flags(m, &flags) & kStatic) != !!isStatic || !named(api.method_get_return_type(m), returns)) continue;
            bool match = true;
            for (size_t i = 0; i < count; ++i) match = match && named(api.method_get_param(m, static_cast<uint32_t>(i)), params[i]);
            if (!match) continue;
            if (found && found != m) return EHR_RUNTIME_AMBIGUOUS;
            found = m;
        }
        if (visited == kMaxMembers) return diagnosticLimit(ehr_diagnostics::MethodCount,visited,kMaxMembers);
        if (found) { *result = metadata(MetadataKind::Method, found, c); return EHR_RUNTIME_OK; }
    }
    return EHR_RUNTIME_NOT_FOUND;
}
extern "C" EHRRuntimeStatus ehr_runtime_find_field(EHRRuntimeToken token, const char *name, const char *type, int isStatic, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    RuntimeClass *c = klass(token);
    if (!c) return EHR_RUNTIME_INVALID_TOKEN;
    if (!text(name) || !text(type) || (isStatic != 0 && isStatic != 1)) return EHR_RUNTIME_BAD_ARGUMENT;
    auto &api = state().api;
    for (size_t depth = 0; c && depth < kMaxParents; ++depth, c = api.class_get_parent(c)) {
        void *iter = nullptr;
        for (size_t visited = 0; visited < kMaxMembers; ++visited) {
            Field *f = api.class_get_fields(c, &iter);
            if (!f) break;
            const char *actual = api.field_get_name(f);
            if (actual && !strcmp(actual, name) && !!(api.field_get_flags(f) & kStatic) == !!isStatic && named(api.field_get_type(f), type)) {
                *result = metadata(MetadataKind::Field, f, c); return EHR_RUNTIME_OK;
            }
            if (visited + 1 == kMaxMembers) return diagnosticLimit(ehr_diagnostics::FieldCount,visited+1,kMaxMembers);
        }
    }
    return EHR_RUNTIME_NOT_FOUND;
}
extern "C" EHRRuntimeStatus ehr_runtime_method_object(EHRRuntimeToken token, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    const Metadata *m = lookup(token, MetadataKind::Method);
    if (!m) return EHR_RUNTIME_INVALID_TOKEN;
    auto &api = state().api;
    if (!api.method_get_object) return EHR_RUNTIME_UNSUPPORTED;
    const Method *method = static_cast<const Method *>(m->pointer);
    const char *name = api.method_get_name(method);
    if (!name || !strcmp(name, ".ctor") || !strcmp(name, ".cctor")) return EHR_RUNTIME_UNSUPPORTED;
    try {
        return root(api.method_get_object(method, m->owner), result);
    } catch (...) {
        return EHR_RUNTIME_UNSUPPORTED;
    }
}
extern "C" EHRRuntimeStatus ehr_runtime_method_from_object(EHRRuntimeToken token, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    auto &api = state().api;
    if (!api.method_get_from_reflection || !api.method_get_object) return EHR_RUNTIME_UNSUPPORTED;
    Object *value = nullptr;
    auto status = object(token, &value);
    if (status != EHR_RUNTIME_OK) return status;
    if (!value) return EHR_RUNTIME_BAD_ARGUMENT;
    // Validate against an ordinary MethodInfo produced by this same runtime,
    // rather than trusting every user-defined MethodInfo subclass's layout.
    EHRRuntimeToken objectClass = 0, toString = 0;
    status = ehr_runtime_find_class("mscorlib.dll", "System", "Object", &objectClass);
    if (status != EHR_RUNTIME_OK) return status;
    status = ehr_runtime_find_method(objectClass, "ToString", nullptr, 0, "System.String", 0, &toString);
    if (status != EHR_RUNTIME_OK) return status;
    OwnedObjectToken canonicalMethod;
    status = ehr_runtime_method_object(toString, &canonicalMethod.value);
    if (status != EHR_RUNTIME_OK) return status;
    Object *canonical = nullptr;
    status = object(canonicalMethod.value, &canonical);
    if (status != EHR_RUNTIME_OK) return status;
    if (!canonical || api.object_get_class(value) != api.object_get_class(canonical)) return EHR_RUNTIME_TYPE_MISMATCH;
    try {
        const Method *method = api.method_get_from_reflection(value);
        if (!method) return EHR_RUNTIME_TYPE_MISMATCH;
        RuntimeClass *owner = api.method_get_declaring_type(method);
        if (!owner) return EHR_RUNTIME_TYPE_MISMATCH;
        *result = metadata(MetadataKind::Method, method, owner);
        return EHR_RUNTIME_OK;
    } catch (...) {
        return EHR_RUNTIME_UNSUPPORTED;
    }
}
extern "C" EHRRuntimeStatus ehr_runtime_invoke(EHRRuntimeToken token, EHRRuntimeToken instance,
    const EHRRuntimeArgument *arguments, size_t count, EHRRuntimeToken *result, EHRRuntimeToken *exception) {
    if (!result || !exception || result == exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = *exception = 0;
    REQUIRE_READY();
    const auto m = lookup(token, MetadataKind::Method);
    if (!m) return EHR_RUNTIME_INVALID_TOKEN;
    auto &api = state().api;
    const Method *method = static_cast<const Method *>(m->pointer);
    if (count > kMaxArguments || (count && !arguments) || count != api.method_get_param_count(method)) return EHR_RUNTIME_BAD_ARGUMENT;
    if (api.method_is_generic(method) && (!api.method_is_inflated || !api.method_is_inflated(method)))
        return EHR_RUNTIME_UNSUPPORTED;
    if (api.class_is_generic(m->owner) && !api.class_is_inflated(m->owner)) return EHR_RUNTIME_UNSUPPORTED;
    uint32_t impl = 0;
    const bool isStatic = (api.method_get_flags(method, &impl) & kStatic) != 0;
    Object *target = nullptr;
    auto status = receiver(*m, isStatic, instance, &target);
    if (status != EHR_RUNTIME_OK) return status;
    Prepared pinnedReceiver;
    const Method *dispatchMethod = nullptr;
    void *invokeThis = nullptr;
    status = prepareDispatchReceiver(method, target, pinnedReceiver, &dispatchMethod, &invokeThis);
    if (status != EHR_RUNTIME_OK) return status;
    const Type *returns = api.method_get_return_type(method);
    const int returnKind = returns ? api.type_get_type(returns) : 0;
    if (!returns || api.type_is_byref(returns) || returnKind == 0x0f || returnKind == 0x16 || returnKind == 0x1b) return EHR_RUNTIME_UNSUPPORTED;
    std::vector<Prepared> prepared(count);
    std::vector<void *> params(count);
    for (size_t i = 0; i < count; ++i) {
        status = prepare(api.method_get_param(method, static_cast<uint32_t>(i)), arguments[i], prepared[i]);
        if (status != EHR_RUNTIME_OK) return status;
        params[i] = prepared[i].argument;
    }
    Exception *raised = nullptr;
    Object *returned = invokeWithOriginalPermit(dispatchMethod, invokeThis, count ? params.data() : nullptr, &raised);
    if (raised) {
        status = root(reinterpret_cast<Object *>(raised), exception);
        return status == EHR_RUNTIME_OK ? EHR_RUNTIME_MANAGED_EXCEPTION : status;
    }
    return root(returned, result);
}
extern "C" EHRRuntimeStatus ehr_runtime_invoke_with_refs(EHRRuntimeToken token,
    EHRRuntimeToken instance, const EHRRuntimeArgument *arguments, size_t count,
    const EHRRuntimeByRefOutput *outputs, size_t outputCount,
    EHRRuntimeToken *result, EHRRuntimeToken *exception) {
    if (!result || !exception || result == exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = *exception = 0;
    REQUIRE_READY();
    const auto m = lookup(token, MetadataKind::Method);
    if (!m) return EHR_RUNTIME_INVALID_TOKEN;
    auto &api = state().api;
    const Method *method = static_cast<const Method *>(m->pointer);
    if (count > kMaxArguments || (count && !arguments) || count != api.method_get_param_count(method) ||
        outputCount > count || (outputCount && !outputs)) return EHR_RUNTIME_BAD_ARGUMENT;
    if ((api.method_is_generic(method) && (!api.method_is_inflated || !api.method_is_inflated(method))) ||
        (api.class_is_generic(m->owner) && !api.class_is_inflated(m->owner))) return EHR_RUNTIME_UNSUPPORTED;
    uint32_t impl = 0;
    const bool isStatic = (api.method_get_flags(method, &impl) & kStatic) != 0;
    Object *target = nullptr;
    auto status = receiver(*m, isStatic, instance, &target);
    if (status != EHR_RUNTIME_OK) return status;
    Prepared pinnedReceiver;
    const Method *dispatchMethod = nullptr;
    void *invokeThis = nullptr;
    status = prepareDispatchReceiver(method, target, pinnedReceiver, &dispatchMethod, &invokeThis);
    if (status != EHR_RUNTIME_OK) return status;
    const Type *returns = api.method_get_return_type(method);
    const int returnKind = returns ? api.type_get_type(returns) : 0;
    if (!returns || api.type_is_byref(returns) || returnKind == 0x0f || returnKind == 0x16 || returnKind == 0x1b) return EHR_RUNTIME_UNSUPPORTED;

    // Copy descriptors before managed execution. Output pointers are explicit
    // writable capabilities; the immutable argument bytes are never cast away.
    std::vector<EHRRuntimeByRefOutput> copies;
    copies.reserve(outputCount);
    std::vector<int> descriptorForIndex(count, -1);
    for (size_t i = 0; i < outputCount; ++i) {
        const EHRRuntimeByRefOutput descriptor = outputs[i];
        if (descriptor.reserved || descriptor.argument_index >= count ||
            descriptorForIndex[descriptor.argument_index] != -1) return EHR_RUNTIME_BAD_ARGUMENT;
        uintptr_t begin = 0, end = 0;
        if (!addressSpan(descriptor.bytes, descriptor.byte_count, begin, end) ||
            descriptor.byte_count > kMaxBytes ||
            overlaps(descriptor.bytes, descriptor.byte_count, result, sizeof(*result)) ||
            overlaps(descriptor.bytes, descriptor.byte_count, exception, sizeof(*exception))) return EHR_RUNTIME_BAD_ARGUMENT;
        for (const auto &prior : copies)
            if (overlaps(descriptor.bytes, descriptor.byte_count, prior.bytes, prior.byte_count)) return EHR_RUNTIME_BAD_ARGUMENT;
        descriptorForIndex[descriptor.argument_index] = static_cast<int>(copies.size());
        copies.push_back(descriptor);
    }
    std::vector<Prepared> prepared(count);
    std::vector<void *> params(count);
    std::vector<RefCopyback> copybacks;
    copybacks.reserve(outputCount);
    for (size_t i = 0; i < count; ++i) {
        const Type *type = api.method_get_param(method, static_cast<uint32_t>(i));
        const int descriptorIndex = descriptorForIndex[i];
        if (!type) return EHR_RUNTIME_UNSUPPORTED;
        if (!api.type_is_byref(type)) {
            if (descriptorIndex != -1) return EHR_RUNTIME_BAD_ARGUMENT;
            status = prepare(type, arguments[i], prepared[i]);
        } else {
            // The byref flag is separate from the element's type-kind in this
            // runtime. Do not alter an Il2CppType or invent a metadata layout.
            const int kind = api.type_get_type(type);
            if (kind == 0x01 || kind == 0x0f || kind == 0x10 || kind == 0x13 || kind == 0x16 || kind == 0x1b || kind == 0x1e)
                return EHR_RUNTIME_UNSUPPORTED;
            RuntimeClass *expected = api.class_from_type(type);
            if (!expected || !api.class_is_valuetype(expected)) return EHR_RUNTIME_UNSUPPORTED;
            if (descriptorIndex == -1) return EHR_RUNTIME_BAD_ARGUMENT;
            const auto &descriptor = copies[static_cast<size_t>(descriptorIndex)];
            if (klass(descriptor.value_class) != expected) return EHR_RUNTIME_TYPE_MISMATCH;
            status = prepareValue(expected, arguments[i], prepared[i]);
            if (status == EHR_RUNTIME_OK && descriptor.byte_count != arguments[i].byte_count) return EHR_RUNTIME_TYPE_MISMATCH;
            if (status == EHR_RUNTIME_OK) copybacks.push_back(RefCopyback{i, descriptor.bytes, descriptor.byte_count});
        }
        if (status != EHR_RUNTIME_OK) return status;
        params[i] = prepared[i].argument;
    }
    Exception *raised = nullptr;
    Object *returned = invokeWithOriginalPermit(dispatchMethod, invokeThis, count ? params.data() : nullptr, &raised);
    // Managed ref writes remain observable when the callee subsequently throws.
    // No copyback occurs for any preflight failure or unsupported signature.
    for (const auto &copyback : copybacks)
        memcpy(copyback.bytes, prepared[copyback.index].argument, copyback.byteCount);
    if (raised) {
        status = root(reinterpret_cast<Object *>(raised), exception);
        return status == EHR_RUNTIME_OK ? EHR_RUNTIME_MANAGED_EXCEPTION : status;
    }
    return root(returned, result);
}
extern "C" EHRRuntimeStatus ehr_runtime_read_field(EHRRuntimeToken token, EHRRuntimeToken instance, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    const auto m = lookup(token, MetadataKind::Field);
    if (!m) return EHR_RUNTIME_INVALID_TOKEN;
    Field *field = const_cast<Field *>(static_cast<const Field *>(m->pointer));
    auto &api = state().api;
    if (api.class_is_generic(m->owner) && !api.class_is_inflated(m->owner)) return EHR_RUNTIME_UNSUPPORTED;
    const Type *type = api.field_get_type(field);
    const int kind = type ? api.type_get_type(type) : 0;
    if (kind == 0x01 || kind == 0x0f || kind == 0x13 || kind == 0x16 || kind == 0x1b || kind == 0x1e) return EHR_RUNTIME_UNSUPPORTED;
    RuntimeClass *fieldClass = type ? api.class_from_type(type) : nullptr;
    if (!type || api.type_is_byref(type) || !fieldClass || (!referenceType(type) && !api.class_is_valuetype(fieldClass))) return EHR_RUNTIME_UNSUPPORTED;
    const bool isStatic = (api.field_get_flags(field) & kStatic) != 0;
    if (isStatic && !staticFieldSupported(m->owner)) return EHR_RUNTIME_UNSUPPORTED;
    Object *target = nullptr;
    auto status = receiver(*m, isStatic, instance, &target);
    if (status != EHR_RUNTIME_OK) return status;
    return root(api.field_get_value_object(field, target), result);
}
extern "C" EHRRuntimeStatus ehr_runtime_write_field(EHRRuntimeToken token, EHRRuntimeToken instance, const EHRRuntimeArgument *value) {
    REQUIRE_READY();
    if (!value) return EHR_RUNTIME_BAD_ARGUMENT;
    const auto m = lookup(token, MetadataKind::Field);
    if (!m) return EHR_RUNTIME_INVALID_TOKEN;
    Field *field = const_cast<Field *>(static_cast<const Field *>(m->pointer));
    auto &api = state().api;
    const int flags = api.field_get_flags(field);
    if (api.class_is_generic(m->owner) && !api.class_is_inflated(m->owner)) return EHR_RUNTIME_UNSUPPORTED;
    if (flags & (kLiteral | kInitOnly)) return EHR_RUNTIME_UNSUPPORTED;
    if ((flags & kStatic) && !staticFieldSupported(m->owner)) return EHR_RUNTIME_UNSUPPORTED;
    Object *target = nullptr;
    auto status = receiver(*m, (flags & kStatic) != 0, instance, &target);
    if (status != EHR_RUNTIME_OK) return status;
    Prepared p;
    status = prepare(api.field_get_type(field), *value, p);
    if (status != EHR_RUNTIME_OK) return status;
    // Pinned Unity 2022.3 setters take the reference DIRECTLY for reference
    // fields; passing &reference would corrupt the heap. The object helper
    // makes this explicit for instance fields. Runtime setters supply barriers.
    if (flags & kStatic) api.field_static_set_value(field, p.argument);
    else if (referenceType(api.field_get_type(field))) api.field_set_value_object(target, field, p.reference);
    else api.field_set_value(target, field, p.argument);
    return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_value_size(EHRRuntimeToken token, size_t *bytes) {
    if (!bytes) return EHR_RUNTIME_BAD_ARGUMENT;
    *bytes = 0;
    REQUIRE_READY();
    RuntimeClass *c = klass(token);
    return c ? valueSize(c, bytes) : EHR_RUNTIME_INVALID_TOKEN;
}
extern "C" EHRRuntimeStatus ehr_runtime_box(EHRRuntimeToken token, const void *bytes, size_t count, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    RuntimeClass *c = klass(token);
    if (!c) return EHR_RUNTIME_INVALID_TOKEN;
    size_t required = 0;
    auto status = valueSize(c, &required);
    if (status != EHR_RUNTIME_OK) return status;
    if (!bytes || count != required) return EHR_RUNTIME_TYPE_MISMATCH;
    std::vector<uint64_t> aligned((required + sizeof(uint64_t) - 1) / sizeof(uint64_t));
    memcpy(aligned.data(), bytes, required);
    return root(state().api.value_box(c, aligned.data()), result);
}
extern "C" EHRRuntimeStatus ehr_runtime_copy_value(EHRRuntimeToken token, void *bytes, size_t capacity, size_t *count) {
    if (!count) return EHR_RUNTIME_BAD_ARGUMENT;
    *count = 0;
    REQUIRE_READY();
    Object *value = nullptr;
    auto status = object(token, &value);
    if (status != EHR_RUNTIME_OK) return status;
    if (!value) return EHR_RUNTIME_BAD_ARGUMENT;
    status = valueSize(state().api.object_get_class(value), count);
    if (status != EHR_RUNTIME_OK) return status;
    if (!bytes || capacity < *count) {if(bytes||capacity)return diagnosticLimit(ehr_diagnostics::CopyValueCapacity,*count,capacity);return EHR_RUNTIME_LIMIT;}
    void *payload = state().api.object_unbox(value);
    if (!payload) return EHR_RUNTIME_TYPE_MISMATCH;
    memcpy(bytes, payload, *count);
    return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_string_create(const uint16_t *units, size_t count, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    if ((!units && count) || count > kMaxBytes / sizeof(uint16_t)) return EHR_RUNTIME_BAD_ARGUMENT;
    const uint16_t empty = 0;
    return root(reinterpret_cast<Object *>(state().api.string_new_utf16(units ?: &empty, static_cast<int32_t>(count))), result);
}
extern "C" EHRRuntimeStatus ehr_runtime_string_copy(EHRRuntimeToken token, uint16_t *units, size_t capacity, size_t *count) {
    if (!count) return EHR_RUNTIME_BAD_ARGUMENT;
    *count = 0;
    REQUIRE_READY();
    Object *value = nullptr;
    auto status = object(token, &value);
    if (status != EHR_RUNTIME_OK) return status;
    if (!value || state().api.type_get_type(state().api.class_get_type(state().api.object_get_class(value))) != 0x0e) return EHR_RUNTIME_TYPE_MISMATCH;
    String *string = reinterpret_cast<String *>(value);
    const int32_t length = state().api.string_length(string);
    if (length < 0 || static_cast<size_t>(length) > kMaxBytes / sizeof(uint16_t)) return diagnosticLimit(ehr_diagnostics::StringLength,length>0?uint64_t(length):0,kMaxBytes/sizeof(uint16_t));
    *count = static_cast<size_t>(length);
    if (capacity < *count || (!units && *count)) {if(units||capacity)return diagnosticLimit(ehr_diagnostics::StringCapacity,*count,capacity);return EHR_RUNTIME_LIMIT;}
    if (*count) memcpy(units, state().api.string_chars(string), *count * sizeof(uint16_t));
    return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_object_release(EHRRuntimeToken token) {
    REQUIRE_READY();
    if (!token) return EHR_RUNTIME_OK;
    auto &s = state();
    const auto found = s.roots.find(token);
    if (found == s.roots.end()) return EHR_RUNTIME_INVALID_TOKEN;
    const uint32_t handle = found->second;
    s.roots.erase(found);weakTokens().erase(token);
    s.api.gchandle_free(handle);
    return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_object_retain(EHRRuntimeToken token, EHRRuntimeToken *result) {
    if (!result) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = 0;
    REQUIRE_READY();
    Object *value = nullptr;
    const auto status = object(token, &value);
    return status == EHR_RUNTIME_OK ? root(value, result) : status;
}
extern "C" EHRRuntimeStatus ehr_runtime_object_root_count(size_t *count) {
    if (!count) return EHR_RUNTIME_BAD_ARGUMENT;
    *count = 0;
    if (![NSThread isMainThread]) return EHR_RUNTIME_WRONG_THREAD;
    if (!state().loaded) return EHR_RUNTIME_NOT_READY;
    *count = state().roots.size();
    return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_object_same(EHRRuntimeToken left,
    EHRRuntimeToken right, int32_t *same) {
    if (!same) return EHR_RUNTIME_BAD_ARGUMENT;
    *same = 0;
    REQUIRE_READY();
    Object *leftValue = nullptr, *rightValue = nullptr;
    auto status = object(left, &leftValue);
    if (status != EHR_RUNTIME_OK) return status;
    status = object(right, &rightValue);
    if (status != EHR_RUNTIME_OK) return status;
    *same = leftValue == rightValue ? 1 : 0;
    return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_object_identity_hash(EHRRuntimeToken token,
    int32_t *hash, EHRRuntimeToken *exception) {
    if (!hash || !exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *hash = 0; *exception = 0;
    REQUIRE_READY();
    Object *value = nullptr;
    auto status = object(token, &value);
    if (status != EHR_RUNTIME_OK || !value) return status;
    EHRRuntimeToken helpers = 0, method = 0;
    status = ehr_runtime_find_class("mscorlib.dll", "System.Runtime.CompilerServices", "RuntimeHelpers", &helpers);
    if (status != EHR_RUNTIME_OK) return status;
    const char *parameters[] = {"System.Object"};
    status = ehr_runtime_find_method(helpers, "GetHashCode", parameters, 1, "System.Int32", 1, &method);
    if (status != EHR_RUNTIME_OK) return status;
    const EHRRuntimeArgument argument{EHR_RUNTIME_REFERENCE, 0, token, nullptr, 0};
    OwnedObjectToken boxed;
    status = ehr_runtime_invoke(method, 0, &argument, 1, &boxed.value, exception);
    if (status != EHR_RUNTIME_OK) return status;
    size_t count = 0;
    status = ehr_runtime_copy_value(boxed.value, hash, sizeof(*hash), &count);
    return status == EHR_RUNTIME_OK && count != sizeof(*hash) ? EHR_RUNTIME_TYPE_MISMATCH : status;
}
extern "C" EHRRuntimeStatus ehr_runtime_object_release_deferred(EHRRuntimeToken token) {
    if (!token) return EHR_RUNTIME_OK;
    auto &s = state();
    bool full = false;
    {
        std::lock_guard<std::mutex> lock(s.deferredMutex);
        full = s.deferredCount == kMaxRoots;if(full)++s.deferredFull;
        if (!full) {
            const size_t tail = (s.deferredHead + s.deferredCount) % kMaxRoots;
            s.deferred[tail] = token;
            ++s.deferredCount;++s.deferredEnqueued;s.deferredHighWater=std::max(s.deferredHighWater,s.deferredCount);
        }
    }
    scheduleDeferredDrainIfNeeded();
    if(full){EHRRuntimeGatewayPublishDiagnosticSnapshot();EHRDiagnosticLimit(ehr_diagnostics::DeferredCapacity,kMaxRoots,kMaxRoots);}
    return full ? EHR_RUNTIME_LIMIT : EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_drain_deferred_releases(size_t *released) {
    if (!released) return EHR_RUNTIME_BAD_ARGUMENT;
    *released = 0;
    REQUIRE_READY();
    *released = drainDeferred(kMaxRoots);
    return EHR_RUNTIME_OK;
}

namespace {
struct EngineColor32 { uint8_t r,g,b,a; };
static_assert(sizeof(EngineColor32)==4 && alignof(EngineColor32)==1,"Color32 bridge ABI");
EHRRuntimeStatus verifyEngineColor32(RuntimeClass *color) {
    auto &api=state().api;
    size_t size=0;
    auto status=valueSize(color,&size);
    if(status!=EHR_RUNTIME_OK)return status;
    if(size!=sizeof(EngineColor32))return EHR_RUNTIME_TYPE_MISMATCH;
    // Validate payload order through actual managed field access. No assumed
    // object header size or Il2CppFieldInfo offset enters this check.
    const EngineColor32 sentinel{0x11,0x33,0x55,0x77};
    Prepared boxed;
    Object *value=api.value_box(color,const_cast<EngineColor32 *>(&sentinel));
    if(!value)return EHR_RUNTIME_NOT_READY;
    boxed.pinnedHandle=api.gchandle_new(value,true);
    if(!boxed.pinnedHandle)return EHR_RUNTIME_NOT_READY;
    boxed.reference=api.gchandle_get_target(boxed.pinnedHandle);
    if(!boxed.reference||api.object_get_class(boxed.reference)!=color)return EHR_RUNTIME_TYPE_MISMATCH;
    const char *names[]={"r","g","b","a"};
    const uint8_t expected[]={sentinel.r,sentinel.g,sentinel.b,sentinel.a};
    bool found[4]={};void *iterator=nullptr;
    for(size_t n=0;n<kMaxMembers;++n){
        Field *field=api.class_get_fields(color,&iterator);
        if(!field){for(bool present:found)if(!present)return EHR_RUNTIME_NOT_FOUND;return EHR_RUNTIME_OK;}
        if(api.field_get_flags(field)&kStatic)continue;
        const char *name=api.field_get_name(field);
        for(size_t i=0;i<4;++i)if(name&&!strcmp(name,names[i])){
            if(found[i]||!named(api.field_get_type(field),"System.Byte"))return EHR_RUNTIME_TYPE_MISMATCH;
            found[i]=true;
            Object *byteBox=api.field_get_value_object(field,boxed.reference);
            if(!byteBox)return EHR_RUNTIME_TYPE_MISMATCH;
            Prepared bytePin;bytePin.pinnedHandle=api.gchandle_new(byteBox,true);
            if(!bytePin.pinnedHandle)return EHR_RUNTIME_NOT_READY;
            Object *pinned=api.gchandle_get_target(bytePin.pinnedHandle);
            if(!pinned)return EHR_RUNTIME_INVALID_TOKEN;
            const void *payload=api.object_unbox(pinned);
            if(!payload||*static_cast<const uint8_t *>(payload)!=expected[i])return EHR_RUNTIME_TYPE_MISMATCH;
        }
    }
    return EHR_RUNTIME_LIMIT;
}
}
extern "C" EHRRuntimeStatus ehr_runtime_color_parse_html(EHRRuntimeToken textToken,int32_t *parsed,uint32_t *rgba) {
    if(!parsed||!rgba||reinterpret_cast<void *>(parsed)==reinterpret_cast<void *>(rgba))return EHR_RUNTIME_BAD_ARGUMENT;
    *parsed=0;*rgba=0;
    REQUIRE_READY();
    try {
        using Resolver=void *(*)(const char *);
        auto resolve=reinterpret_cast<Resolver>(symbol("il2cpp_resolve_icall"));
        if(!resolve)return EHR_RUNTIME_NOT_FOUND;
        auto status=ehr_pinned::validate_engine_entry(reinterpret_cast<const void *>(resolve));
        if(status!=EHR_RUNTIME_OK)return status;
        // Exact name is also present in the pinned source-interoperability DLL;
        // no untyped name scan, alias fallback, or direct native address guess.
        using Parse=bool (*)(String *,EngineColor32 *);
        auto parse=reinterpret_cast<Parse>(resolve("UnityEngine.ColorUtility::DoTryParseHtmlColor"));
        if(!parse)return EHR_RUNTIME_NOT_FOUND;
        status=ehr_pinned::validate_engine_entry(reinterpret_cast<const void *>(parse));
        if(status!=EHR_RUNTIME_OK)return status;
        EHRRuntimeToken colorClass=0,stringClass=0;
        status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","Color32",&colorClass);
        if(status!=EHR_RUNTIME_OK)return status==EHR_RUNTIME_NOT_FOUND?EHR_RUNTIME_UNSUPPORTED:status;
        status=verifyEngineColor32(klass(colorClass));if(status!=EHR_RUNTIME_OK)return status==EHR_RUNTIME_NOT_FOUND?EHR_RUNTIME_UNSUPPORTED:status;
        status=ehr_runtime_find_class("mscorlib.dll","System","String",&stringClass);
        if(status!=EHR_RUNTIME_OK)return status==EHR_RUNTIME_NOT_FOUND?EHR_RUNTIME_UNSUPPORTED:status;
        auto &api=state().api;
        Object *input=nullptr;status=object(textToken,&input);if(status!=EHR_RUNTIME_OK)return status;
        Prepared pinned;
        if(input){
            if(api.object_get_class(input)!=klass(stringClass))return EHR_RUNTIME_TYPE_MISMATCH;
            pinned.pinnedHandle=api.gchandle_new(input,true);
            if(!pinned.pinnedHandle)return EHR_RUNTIME_NOT_READY;
            pinned.reference=api.gchandle_get_target(pinned.pinnedHandle);
            if(!pinned.reference||api.object_get_class(pinned.reference)!=klass(stringClass))return EHR_RUNTIME_TYPE_MISMATCH;
        }
        EngineColor32 color{};
        const bool success=parse(reinterpret_cast<String *>(pinned.reference),&color);
        *rgba=(uint32_t(color.r)<<24)|(uint32_t(color.g)<<16)|(uint32_t(color.b)<<8)|color.a;
        *parsed=success?1:0;
        return EHR_RUNTIME_OK;
    } catch (...) { *parsed=0;*rgba=0;return EHR_RUNTIME_UNSUPPORTED; }
}
