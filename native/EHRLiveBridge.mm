#import "EHRLiveBridge.h"
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>
#include <chrono>
#include <limits>
#include "EHRHostCore.h"

// Native IL2CPP runtime API handles are deliberately opaque. No Unity or game
// object layout, method address, instance offset, or vtable layout is assumed.
struct Il2CppDomain;
struct Il2CppAssembly;
struct Il2CppImage;
struct Il2CppClass;
struct Il2CppType;
struct Il2CppObject;
struct Il2CppString;
struct Il2CppException;
struct FieldInfo;
struct MethodInfo;

NSString *const EHRLiveBridgeSnapshotNotification = @"EHRLiveBridgeSnapshot";

namespace {

constexpr uint32_t kStatic = 0x10;
constexpr uint32_t kLiteral = 0x40;
constexpr size_t kMaxAssemblies = 512;
constexpr size_t kMaxMembers = 2048;
constexpr size_t kMaxParents = 24;
constexpr int32_t kMaxPlayers = 32;
constexpr int32_t kMaxStringUnits = 128;
constexpr NSUInteger kMaxErrors = 64;

// Type codes are the public ECMA/IL2CPP type-kind enumeration, not offsets.
enum TypeKind : int {
    Boolean = 0x02, Character = 0x03, I1 = 0x04, U1 = 0x05,
    I2 = 0x06, U2 = 0x07, I4 = 0x08, U4 = 0x09,
    I8 = 0x0a, U8 = 0x0b, R4 = 0x0c, R8 = 0x0d, String = 0x0e,
};

struct RuntimeAPI {
    Il2CppDomain *(*domain_get)() = nullptr;
    const Il2CppAssembly **(*domain_get_assemblies)(const Il2CppDomain *, size_t *) = nullptr;
    const Il2CppImage *(*assembly_get_image)(const Il2CppAssembly *) = nullptr;
    const char *(*image_get_name)(const Il2CppImage *) = nullptr;
    Il2CppClass *(*class_from_name)(const Il2CppImage *, const char *, const char *) = nullptr;
    Il2CppClass *(*class_get_parent)(Il2CppClass *) = nullptr;
    const char *(*class_get_name)(Il2CppClass *) = nullptr;
    const char *(*class_get_namespace)(Il2CppClass *) = nullptr;
    FieldInfo *(*class_get_fields)(Il2CppClass *, void **) = nullptr;
    const MethodInfo *(*class_get_methods)(Il2CppClass *, void **) = nullptr;
    bool (*class_is_enum)(const Il2CppClass *) = nullptr;
    const Il2CppType *(*class_enum_basetype)(Il2CppClass *) = nullptr;
    const char *(*field_get_name)(FieldInfo *) = nullptr;
    int (*field_get_flags)(FieldInfo *) = nullptr;
    const Il2CppType *(*field_get_type)(FieldInfo *) = nullptr;
    Il2CppObject *(*field_get_value_object)(FieldInfo *, Il2CppObject *) = nullptr;
    const char *(*method_get_name)(const MethodInfo *) = nullptr;
    uint32_t (*method_get_flags)(const MethodInfo *, uint32_t *) = nullptr;
    uint32_t (*method_get_param_count)(const MethodInfo *) = nullptr;
    const Il2CppType *(*method_get_param)(const MethodInfo *, uint32_t) = nullptr;
    const Il2CppType *(*method_get_return_type)(const MethodInfo *) = nullptr;
    int (*type_get_type)(const Il2CppType *) = nullptr;
    char *(*type_get_name)(const Il2CppType *) = nullptr;
    void (*runtime_free)(void *) = nullptr;
    Il2CppClass *(*object_get_class)(Il2CppObject *) = nullptr;
    void *(*object_unbox)(Il2CppObject *) = nullptr;
    Il2CppObject *(*runtime_invoke)(const MethodInfo *, void *, void **, Il2CppException **) = nullptr;
    int32_t (*string_length)(Il2CppString *) = nullptr;
    const uint16_t *(*string_chars)(Il2CppString *) = nullptr;
    void *(*thread_current)() = nullptr;
    void *(*thread_attach)(Il2CppDomain *) = nullptr;
    void (*format_exception)(Il2CppException *, char *, int) = nullptr;
    Il2CppClass *(*class_from_type)(const Il2CppType *) = nullptr;
    bool (*class_is_assignable_from)(Il2CppClass *, Il2CppClass *) = nullptr;
    bool (*type_is_byref)(const Il2CppType *) = nullptr;
    // Opaque register-sized transport preserves both legacy 32-bit handles
    // (actual Unity 2022 build) and pointer-sized API variants on ARM64. Handles
    // are never dereferenced, offset, or otherwise interpreted by this bridge.
    uintptr_t (*gchandle_new)(Il2CppObject *, bool) = nullptr;
    Il2CppObject *(*gchandle_get_target)(uintptr_t) = nullptr;
    void (*gchandle_free)(uintptr_t) = nullptr;
};

struct Binding {
    FieldInfo *field = nullptr;
    const MethodInfo *method = nullptr;
    const Il2CppType *type = nullptr;
    Il2CppClass *declaringClass = nullptr;
    bool found() const { return field || method; }
};

struct ReadResult {
    Il2CppObject *value = nullptr;
    const Il2CppType *type = nullptr;
    bool read = false;
};

struct PendingBait {
    uintptr_t killer = 0;
    uintptr_t victim = 0;
    uintptr_t victimData = 0;
    uint64_t round = 0;
    uint8_t killerId = 255;
    uint8_t victimId = 255;
};

struct BaitState {
    EHRHostCore *core = nullptr;
    EHRBaitConfig config{0, 0, 0, 0};
    int selectedPlayerId = -1;
    dispatch_source_t timer = nil;
    bool running = false;
    uint64_t round = 0;
    uintptr_t roundAnchorHandle = 0;
    bool wasStarted = false;
    bool activeTasks = false;
    bool isHost = false;
    bool callbackObserved = false;
    bool reportSignatureAvailable = false;
    bool callbackSignatureAvailable = false;
    bool gcAvailable = false;
    uint64_t callbackCount = 0;
    uint64_t confirmedCount = 0;
    uint64_t reportsAttempted = 0;
    uint64_t reportCallsCompleted = 0;
    std::unordered_map<uint64_t, PendingBait> pending;
    NSDictionary *lastEvent = nil;
};

struct SharedState {
    RuntimeAPI api;
    dispatch_source_t timer = nil; // Accessed only on the main queue.
    std::mutex snapshotMutex;
    NSDictionary<NSString *, id> *snapshot = nil;
    // Metadata is retained; live managed game objects are NEVER cached between
    // samples. Sources remain game-owned/rooted while this main-thread read runs.
    std::unordered_map<std::string, Binding> bindings;
    // Handles only to ALREADY loaded UnityFramework images. RTLD_NOLOAD avoids
    // loading another copy of the game framework while inspecting its exports.
    std::unordered_map<std::string, void *> frameworkHandles;
    BaitState bait;
    NSDictionary *baitSnapshot = nil; // Protected by snapshotMutex.
};

SharedState &shared() {
    static SharedState value;
    return value;
}

NSString *bounded(NSString *text) {
    if (!text) return @"";
    if (text.length <= kMaxStringUnits) return text;
    NSUInteger length = kMaxStringUnits;
    const unichar last = [text characterAtIndex:length - 1];
    if (last >= 0xd800 && last <= 0xdbff) --length;
    return [text substringToIndex:length];
}

NSString *nativeText(const char *text) {
    if (!text) return @"";
    const size_t length = strnlen(text, 4096);
    NSString *value = [[NSString alloc] initWithBytes:text length:length encoding:NSUTF8StringEncoding];
    return bounded(value ?: @"<invalid UTF-8>");
}

struct Sample {
    RuntimeAPI &api;
    NSMutableDictionary<NSString *, id> *root;
    NSMutableDictionary<NSString *, id> *runtime;
    NSMutableDictionary<NSString *, id> *members;
    NSMutableArray<NSString *> *errors;
    const Il2CppImage *gameImage = nullptr;
    Il2CppClass *unityObjectClass = nullptr;
    const MethodInfo *unityObjectImplicit = nullptr;

    Sample() : api(shared().api), root([NSMutableDictionary dictionary]),
        runtime([NSMutableDictionary dictionary]), members([NSMutableDictionary dictionary]),
        errors([NSMutableArray array]) {
        root[@"schema"] = @"ehr.live-runtime.v1";
        root[@"source"] = @"IL2CPP runtime in this process";
        root[@"sampledAtUnixSeconds"] = @([[NSDate date] timeIntervalSince1970]);
        root[@"onMainThread"] = @([NSThread isMainThread]);
        root[@"runtime"] = runtime;
        root[@"members"] = members;
        root[@"errors"] = errors;
        root[@"status"] = @"runtime_unavailable";
        root[@"gameplayMutationPerformed"] = @NO;
        root[@"automaticBaitAvailable"] = @NO;
        root[@"client"] = @{};
        root[@"players"] = @[];
        root[@"localPlayer"] = [NSNull null];
        root[@"meetingActive"] = [NSNull null];
        root[@"exileActive"] = [NSNull null];
    }

    void error(NSString *message) {
        if (errors.count < kMaxErrors) [errors addObject:bounded(message)];
    }

    NSString *className(Il2CppClass *klass) {
        if (!klass) return @"";
        NSString *name = nativeText(api.class_get_name(klass));
        NSString *space = nativeText(api.class_get_namespace(klass));
        return bounded(space.length ? [space stringByAppendingFormat:@".%@", name] : name);
    }

    NSString *typeName(const Il2CppType *type) {
        if (!type) return @"";
        char *name = api.type_get_name(type);
        NSString *result = nativeText(name);
        if (name) api.runtime_free(name);
        return result;
    }

    Binding resolve(Il2CppClass *klass, const char *logicalName, bool isStatic) {
        const std::string key = std::to_string(reinterpret_cast<uintptr_t>(klass)) +
            (isStatic ? ":static:" : ":instance:") + logicalName;
        const auto cached = shared().bindings.find(key);
        if (cached != shared().bindings.end()) return cached->second;
        Binding result;
        const std::string getter = std::string("get_") + logicalName;
        const std::string backing = std::string("<") + logicalName + ">k__BackingField";
        const bool singletonStorageOnly = isStatic && std::strcmp(logicalName, "Instance") == 0;
        Il2CppClass *cursor = klass;
        for (size_t depth = 0; cursor && depth < kMaxParents; ++depth) {
            void *iter = nullptr;
            for (size_t count = 0; count < kMaxMembers; ++count) {
                const MethodInfo *method = api.class_get_methods(cursor, &iter);
                if (!method) break;
                // Unity singleton Instance getters can create game objects.
                // This read-only probe reads existing storage only.
                if (singletonStorageOnly) continue;
                const char *name = api.method_get_name(method);
                if (!name || getter != name || api.method_get_param_count(method) != 0) continue;
                uint32_t implementationFlags = 0;
                const bool methodStatic = (api.method_get_flags(method, &implementationFlags) & kStatic) != 0;
                if (methodStatic != isStatic) continue;
                result.method = method;
                result.type = api.method_get_return_type(method);
                result.declaringClass = cursor;
                break;
            }
            if (result.found()) break;
            iter = nullptr;
            for (size_t count = 0; count < kMaxMembers; ++count) {
                FieldInfo *field = api.class_get_fields(cursor, &iter);
                if (!field) break;
                const char *name = api.field_get_name(field);
                if (!name || (std::string(name) != logicalName && std::string(name) != backing &&
                    !(singletonStorageOnly && (std::string(name) == "_instance" || std::string(name) == "instance")))) continue;
                if (((api.field_get_flags(field) & kStatic) != 0) != isStatic) continue;
                result.field = field;
                result.type = api.field_get_type(field);
                result.declaringClass = cursor;
                break;
            }
            if (result.found()) break;
            cursor = api.class_get_parent(cursor);
        }
        shared().bindings.emplace(key, result);
        return result;
    }

    const MethodInfo *method(Il2CppClass *klass, const char *name, uint32_t parameterCount,
                             bool isStatic, bool integerParameter = false) {
        for (size_t depth = 0; klass && depth < kMaxParents; ++depth) {
            void *iter = nullptr;
            for (size_t count = 0; count < kMaxMembers; ++count) {
                const MethodInfo *candidate = api.class_get_methods(klass, &iter);
                if (!candidate) break;
                const char *candidateName = api.method_get_name(candidate);
                if (!candidateName || std::strcmp(candidateName, name) ||
                    api.method_get_param_count(candidate) != parameterCount) continue;
                uint32_t flags = 0;
                if (((api.method_get_flags(candidate, &flags) & kStatic) != 0) != isStatic) continue;
                if (integerParameter && api.type_get_type(api.method_get_param(candidate, 0)) != I4) continue;
                return candidate;
            }
            klass = api.class_get_parent(klass);
        }
        return nullptr;
    }

    void describe(NSString *key, const Binding &binding) {
        if (members[key]) return;
        NSMutableDictionary *description = [NSMutableDictionary dictionaryWithObject:@(binding.found()) forKey:@"found"];
        if (binding.found()) {
            description[@"kind"] = binding.method ? @"getter" : @"field";
            description[@"declaringClass"] = className(binding.declaringClass);
            description[@"member"] = nativeText(binding.method ? api.method_get_name(binding.method) : api.field_get_name(binding.field));
            description[@"type"] = typeName(binding.type);
        }
        members[key] = description;
    }

    Il2CppObject *invoke(const MethodInfo *target, Il2CppObject *object, void **arguments,
                         NSString *context, bool *succeeded = nullptr) {
        if (succeeded) *succeeded = false;
        if (!target) return nullptr;
        Il2CppException *exception = nullptr;
        Il2CppObject *value = api.runtime_invoke(target, object, arguments, &exception);
        if (exception) {
            if (api.format_exception) {
                char message[1024] = {};
                api.format_exception(exception, message, static_cast<int>(sizeof(message)));
                message[sizeof(message) - 1] = 0;
                error([context stringByAppendingFormat:@": %@", nativeText(message)]);
            } else {
                error([context stringByAppendingString:@": managed exception"]);
            }
            return nullptr;
        }
        if (succeeded) *succeeded = true;
        return value;
    }

    ReadResult read(Il2CppClass *klass, Il2CppObject *object, const char *name,
                    bool isStatic, NSString *key) {
        const Binding binding = resolve(klass, name, isStatic);
        describe(key, binding);
        if (!binding.found()) return {};
        ReadResult result;
        result.type = binding.type;
        if (binding.method) {
            result.value = invoke(binding.method, object, nullptr, key, &result.read);
        } else {
            // This runtime API boxes value types and returns references directly.
            // Passing null is correct for a static field; no storage size or field
            // offset is guessed. FieldInfo was supplied by the runtime itself.
            result.value = api.field_get_value_object(binding.field, isStatic ? nullptr : object);
            result.read = true;
        }
        return result;
    }

    template <typename T> NSNumber *number(void *storage) {
        T value{};
        std::memcpy(&value, storage, sizeof(value));
        return @(value);
    }

    NSNumber *numericValue(Il2CppObject *object, const Il2CppType *declaredType) {
        if (!object || !declaredType) return nil;
        const Il2CppType *type = declaredType;
        Il2CppClass *boxedClass = api.object_get_class(object);
        if (boxedClass && api.class_is_enum(boxedClass)) type = api.class_enum_basetype(boxedClass);
        if (!type) return nil;
        const int kind = api.type_get_type(type);
        switch (kind) {
            case Boolean: case Character: case I1: case U1: case I2: case U2:
            case I4: case U4: case I8: case U8: case R4: case R8: break;
            default: return nil;
        }
        void *storage = api.object_unbox(object);
        if (!storage) return nil;
        switch (kind) {
            case Boolean: return @(*static_cast<const uint8_t *>(storage) != 0);
            case Character: return number<uint16_t>(storage);
            case I1: return number<int8_t>(storage);
            case U1: return number<uint8_t>(storage);
            case I2: return number<int16_t>(storage);
            case U2: return number<uint16_t>(storage);
            case I4: return number<int32_t>(storage);
            case U4: return number<uint32_t>(storage);
            case I8: return number<int64_t>(storage);
            case U8: return number<uint64_t>(storage);
            case R4: return number<float>(storage);
            case R8: return number<double>(storage);
            default: return nil;
        }
    }

    id scalar(const ReadResult &result) {
        if (!result.read || !result.value || !result.type) return [NSNull null];
        if (api.type_get_type(result.type) == String) {
            auto string = reinterpret_cast<Il2CppString *>(result.value);
            const int32_t length = api.string_length(string);
            const uint16_t *characters = api.string_chars(string);
            if (length < 0 || !characters) return [NSNull null];
            int32_t boundedLength = std::min(length, kMaxStringUnits);
            if (boundedLength < length && boundedLength > 0 &&
                characters[boundedLength - 1] >= 0xd800 && characters[boundedLength - 1] <= 0xdbff)
                --boundedLength;
            return [[NSString alloc] initWithCharacters:characters length:static_cast<NSUInteger>(boundedLength)];
        }
        NSNumber *number = numericValue(result.value, result.type);
        if (!number) return [NSNull null];
        Il2CppClass *klass = api.object_get_class(result.value);
        if (klass && api.class_is_enum(klass)) {
            NSString *enumName = nil;
            void *iter = nullptr;
            for (size_t i = 0; i < kMaxMembers; ++i) {
                FieldInfo *field = api.class_get_fields(klass, &iter);
                if (!field) break;
                const int flags = api.field_get_flags(field);
                if (!(flags & kStatic) || !(flags & kLiteral)) continue;
                Il2CppObject *boxed = api.field_get_value_object(field, nullptr);
                NSNumber *candidate = numericValue(boxed, api.field_get_type(field));
                if (candidate && [candidate isEqualToNumber:number]) {
                    enumName = nativeText(api.field_get_name(field));
                    break;
                }
            }
            return @{ @"value": number, @"name": enumName ?: (id)[NSNull null], @"type": className(klass) };
        }
        return number;
    }

    // Unity's destroyed-object semantics are checked through its own operator.
    // Unknown validity is represented as null, never silently treated as alive.
    id unityAlive(Il2CppObject *object) {
        if (!object) return @NO;
        if (!unityObjectImplicit) return [NSNull null];
        void *arguments[] = {object};
        bool succeeded = false;
        Il2CppObject *boxed = invoke(unityObjectImplicit, nullptr, arguments, @"UnityEngine.Object.op_Implicit", &succeeded);
        if (!succeeded || !boxed) return [NSNull null];
        NSNumber *number = numericValue(boxed, api.method_get_return_type(unityObjectImplicit));
        return number ?: (id)[NSNull null];
    }

    NSDictionary *player(Il2CppObject *object, Il2CppObject *localPlayer) {
        if (!object) return @{};
        id aliveObject = unityAlive(object);
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:@{
            @"objectAlive": aliveObject, @"isLocal": @(object == localPlayer)
        }];
        if ([aliveObject isEqual:@NO]) return result;
        Il2CppClass *klass = api.object_get_class(object);
        if (!klass) return result;
        result[@"runtimeClass"] = className(klass);
        result[@"playerId"] = scalar(read(klass, object, "PlayerId", false, @"PlayerControl.PlayerId"));
        result[@"ownerId"] = scalar(read(klass, object, "OwnerId", false, @"PlayerControl.OwnerId"));
        const ReadResult data = read(klass, object, "Data", false, @"PlayerControl.Data");
        result[@"dataAvailable"] = @(data.read && data.value);
        result[@"name"] = [NSNull null];
        result[@"isDead"] = [NSNull null];
        if (data.read && data.value) {
            Il2CppClass *dataClass = api.object_get_class(data.value);
            if (dataClass) {
                result[@"dataClass"] = className(dataClass);
                result[@"name"] = scalar(read(dataClass, data.value, "PlayerName", false, @"NetworkedPlayerInfo.PlayerName"));
                result[@"isDead"] = scalar(read(dataClass, data.value, "IsDead", false, @"NetworkedPlayerInfo.IsDead"));
            }
        }
        return result;
    }
};

void *exportAddress(const char *name) {
    if (void *address = dlsym(RTLD_DEFAULT, name)) return address;
    // A bootstrap may load UnityFramework RTLD_LOCAL. Its public runtime API
    // remains discoverable through its existing image even if RTLD_DEFAULT
    // cannot see those symbols. This does not open a new image from disk.
    for (const auto &entry : shared().frameworkHandles)
        if (void *address = dlsym(entry.second, name)) return address;
    const uint32_t imageCount = std::min<uint32_t>(_dyld_image_count(), 4096);
    for (uint32_t i = 0; i < imageCount; ++i) {
        const char *path = _dyld_get_image_name(i);
        if (!path || !std::strstr(path, "/UnityFramework.framework/UnityFramework")) continue;
        if (shared().frameworkHandles.find(path) != shared().frameworkHandles.end()) continue;
        void *handle = dlopen(path, RTLD_LAZY | RTLD_NOLOAD);
        if (!handle) continue;
        shared().frameworkHandles.emplace(path, handle);
        if (void *address = dlsym(handle, name)) return address;
    }
    return nullptr;
}

bool loadExports(Sample &sample) {
    RuntimeAPI &api = sample.api;
    NSMutableDictionary *exports = [NSMutableDictionary dictionary];
    NSMutableArray *missing = [NSMutableArray array];
#define EHR_REQUIRED(field, symbol) \
    api.field = reinterpret_cast<decltype(api.field)>(exportAddress(symbol)); \
    exports[@symbol] = @(api.field != nullptr); \
    if (!api.field) [missing addObject:@symbol]
    EHR_REQUIRED(domain_get, "il2cpp_domain_get");
    EHR_REQUIRED(domain_get_assemblies, "il2cpp_domain_get_assemblies");
    EHR_REQUIRED(assembly_get_image, "il2cpp_assembly_get_image");
    EHR_REQUIRED(image_get_name, "il2cpp_image_get_name");
    EHR_REQUIRED(class_from_name, "il2cpp_class_from_name");
    EHR_REQUIRED(class_get_parent, "il2cpp_class_get_parent");
    EHR_REQUIRED(class_get_name, "il2cpp_class_get_name");
    EHR_REQUIRED(class_get_namespace, "il2cpp_class_get_namespace");
    EHR_REQUIRED(class_get_fields, "il2cpp_class_get_fields");
    EHR_REQUIRED(class_get_methods, "il2cpp_class_get_methods");
    EHR_REQUIRED(class_is_enum, "il2cpp_class_is_enum");
    EHR_REQUIRED(class_enum_basetype, "il2cpp_class_enum_basetype");
    EHR_REQUIRED(field_get_name, "il2cpp_field_get_name");
    EHR_REQUIRED(field_get_flags, "il2cpp_field_get_flags");
    EHR_REQUIRED(field_get_type, "il2cpp_field_get_type");
    EHR_REQUIRED(field_get_value_object, "il2cpp_field_get_value_object");
    EHR_REQUIRED(method_get_name, "il2cpp_method_get_name");
    EHR_REQUIRED(method_get_flags, "il2cpp_method_get_flags");
    EHR_REQUIRED(method_get_param_count, "il2cpp_method_get_param_count");
    EHR_REQUIRED(method_get_param, "il2cpp_method_get_param");
    EHR_REQUIRED(method_get_return_type, "il2cpp_method_get_return_type");
    EHR_REQUIRED(type_get_type, "il2cpp_type_get_type");
    EHR_REQUIRED(type_get_name, "il2cpp_type_get_name");
    EHR_REQUIRED(runtime_free, "il2cpp_free");
    EHR_REQUIRED(object_get_class, "il2cpp_object_get_class");
    EHR_REQUIRED(object_unbox, "il2cpp_object_unbox");
    EHR_REQUIRED(runtime_invoke, "il2cpp_runtime_invoke");
    EHR_REQUIRED(string_length, "il2cpp_string_length");
    EHR_REQUIRED(string_chars, "il2cpp_string_chars");
    EHR_REQUIRED(thread_current, "il2cpp_thread_current");
    EHR_REQUIRED(thread_attach, "il2cpp_thread_attach");
#undef EHR_REQUIRED
    api.format_exception = reinterpret_cast<decltype(api.format_exception)>(exportAddress("il2cpp_format_exception"));
    exports[@"il2cpp_format_exception"] = @(api.format_exception != nullptr);
    // Optional for diagnostics; all are mandatory before the Bait adapter arms.
    api.class_from_type = reinterpret_cast<decltype(api.class_from_type)>(exportAddress("il2cpp_class_from_type"));
    if (!api.class_from_type)
        api.class_from_type = reinterpret_cast<decltype(api.class_from_type)>(exportAddress("il2cpp_class_from_il2cpp_type"));
    api.class_is_assignable_from = reinterpret_cast<decltype(api.class_is_assignable_from)>(exportAddress("il2cpp_class_is_assignable_from"));
    api.type_is_byref = reinterpret_cast<decltype(api.type_is_byref)>(exportAddress("il2cpp_type_is_byref"));
    api.gchandle_new = reinterpret_cast<decltype(api.gchandle_new)>(exportAddress("il2cpp_gchandle_new"));
    api.gchandle_get_target = reinterpret_cast<decltype(api.gchandle_get_target)>(exportAddress("il2cpp_gchandle_get_target"));
    api.gchandle_free = reinterpret_cast<decltype(api.gchandle_free)>(exportAddress("il2cpp_gchandle_free"));
    exports[@"il2cpp_class_from_type_or_alias"] = @(api.class_from_type != nullptr);
    exports[@"il2cpp_class_is_assignable_from"] = @(api.class_is_assignable_from != nullptr);
    exports[@"il2cpp_type_is_byref"] = @(api.type_is_byref != nullptr);
    exports[@"il2cpp_gchandle_new"] = @(api.gchandle_new != nullptr);
    exports[@"il2cpp_gchandle_get_target"] = @(api.gchandle_get_target != nullptr);
    exports[@"il2cpp_gchandle_free"] = @(api.gchandle_free != nullptr);
    sample.runtime[@"exports"] = exports;
    sample.runtime[@"missingRequiredExports"] = missing;
    sample.runtime[@"exportsAvailable"] = @(missing.count == 0);
    return missing.count == 0;
}

void populateSample(Sample &sample) {
    if (![NSThread isMainThread]) {
        sample.error(@"Sampling rejected: not on the main thread");
        return;
    }
    if (!loadExports(sample)) return;
    RuntimeAPI &api = sample.api;
    Il2CppDomain *domain = api.domain_get();
    sample.runtime[@"domainAvailable"] = @(domain != nullptr);
    if (!domain) return;
    void *thread = api.thread_current();
    const bool alreadyAttached = thread != nullptr;
    if (!thread) thread = api.thread_attach(domain);
    sample.runtime[@"threadWasAttached"] = @(alreadyAttached);
    sample.runtime[@"threadAttached"] = @(thread != nullptr);
    if (!thread) {
        sample.error(@"IL2CPP main-thread attachment failed");
        return;
    }

    size_t assemblyCount = 0;
    const Il2CppAssembly **assemblies = api.domain_get_assemblies(domain, &assemblyCount);
    sample.runtime[@"assemblyCount"] = @(assemblyCount);
    if (!assemblies && assemblyCount) {
        sample.error(@"Runtime returned no assembly array");
        return;
    }
    NSMutableArray *assemblyNames = [NSMutableArray array];
    std::vector<const Il2CppImage *> images;
    const size_t boundedAssemblyCount = std::min(assemblyCount, kMaxAssemblies);
    for (size_t i = 0; i < boundedAssemblyCount; ++i) {
        if (!assemblies[i]) continue;
        const Il2CppImage *image = api.assembly_get_image(assemblies[i]);
        if (!image) continue;
        images.push_back(image);
        NSString *name = nativeText(api.image_get_name(image));
        [assemblyNames addObject:name];
        if ([name isEqualToString:@"Assembly-CSharp.dll"] || [name isEqualToString:@"Assembly-CSharp"])
            sample.gameImage = image;
        if (!sample.unityObjectClass) sample.unityObjectClass = api.class_from_name(image, "UnityEngine", "Object");
    }
    sample.runtime[@"assemblyNames"] = assemblyNames;
    sample.runtime[@"assembliesTruncated"] = @(assemblyCount > boundedAssemblyCount);
    sample.runtime[@"gameAssemblyFound"] = @(sample.gameImage != nullptr);
    if (!sample.gameImage) {
        sample.root[@"status"] = @"game_bindings_unavailable";
        return;
    }
    if (sample.unityObjectClass)
        sample.unityObjectImplicit = sample.method(sample.unityObjectClass, "op_Implicit", 1, true);
    sample.runtime[@"unityObjectValidityAvailable"] = @(sample.unityObjectImplicit != nullptr);

    Il2CppClass *playerClass = api.class_from_name(sample.gameImage, "", "PlayerControl");
    Il2CppClass *clientClass = api.class_from_name(sample.gameImage, "", "AmongUsClient");
    Il2CppClass *meetingClass = api.class_from_name(sample.gameImage, "", "MeetingHud");
    Il2CppClass *exileClass = api.class_from_name(sample.gameImage, "", "ExileController");
    sample.runtime[@"classes"] = @{ @"PlayerControl": @(playerClass != nullptr),
        @"AmongUsClient": @(clientClass != nullptr), @"MeetingHud": @(meetingClass != nullptr),
        @"ExileController": @(exileClass != nullptr) };
    if (!playerClass || !clientClass) {
        sample.root[@"status"] = @"game_bindings_unavailable";
        return;
    }
    sample.root[@"status"] = @"live_sample";

    const ReadResult client = sample.read(clientClass, nullptr, "Instance", true, @"AmongUsClient.Instance");
    NSMutableDictionary *clientSnapshot = [NSMutableDictionary dictionaryWithDictionary:@{
        @"instanceAvailable": @(client.read && client.value), @"amHost": [NSNull null],
        @"hostId": [NSNull null], @"gameState": [NSNull null],
        @"isGameStarted": [NSNull null], @"networkMode": [NSNull null]
    }];
    if (client.read && client.value) {
        id alive = sample.unityAlive(client.value);
        clientSnapshot[@"objectAlive"] = alive;
        if (![alive isEqual:@NO]) {
            Il2CppClass *actualClass = api.object_get_class(client.value);
            clientSnapshot[@"amHost"] = sample.scalar(sample.read(actualClass, client.value, "AmHost", false, @"AmongUsClient.AmHost"));
            clientSnapshot[@"hostId"] = sample.scalar(sample.read(actualClass, client.value, "HostId", false, @"AmongUsClient.HostId"));
            clientSnapshot[@"gameState"] = sample.scalar(sample.read(actualClass, client.value, "GameState", false, @"AmongUsClient.GameState"));
            clientSnapshot[@"isGameStarted"] = sample.scalar(sample.read(actualClass, client.value, "IsGameStarted", false, @"AmongUsClient.IsGameStarted"));
            clientSnapshot[@"networkMode"] = sample.scalar(sample.read(actualClass, client.value, "NetworkMode", false, @"AmongUsClient.NetworkMode"));
        }
    }
    sample.root[@"client"] = clientSnapshot;

    const ReadResult local = sample.read(playerClass, nullptr, "LocalPlayer", true, @"PlayerControl.LocalPlayer");
    if (local.read && local.value) sample.root[@"localPlayer"] = sample.player(local.value, local.value);
    const ReadResult list = sample.read(playerClass, nullptr, "AllPlayerControls", true, @"PlayerControl.AllPlayerControls");
    NSMutableArray *players = [NSMutableArray array];
    sample.root[@"playersReportedCount"] = [NSNull null];
    sample.root[@"playersTruncated"] = @NO;
    if (list.read && list.value) {
        Il2CppClass *listClass = api.object_get_class(list.value);
        const ReadResult count = sample.read(listClass, list.value, "Count", false, @"PlayerControl.AllPlayerControls.Count");
        NSNumber *countValue = sample.numericValue(count.value, count.type);
        const MethodInfo *item = sample.method(listClass, "get_Item", 1, false, true);
        sample.members[@"PlayerControl.AllPlayerControls.Item"] = @{ @"found": @(item != nullptr),
            @"kind": @"getter", @"declaringClass": sample.className(listClass),
            @"member": @"get_Item(System.Int32)" };
        if (count.read && countValue && item) {
            const long long reportedCount = countValue.longLongValue;
            sample.root[@"playersReportedCount"] = countValue;
            sample.root[@"playersTruncated"] = @(reportedCount > kMaxPlayers);
            if (reportedCount < 0) {
                sample.error(@"Player list returned a negative count");
            } else {
                const int32_t limit = static_cast<int32_t>(std::min<long long>(reportedCount, kMaxPlayers));
                for (int32_t index = 0; index < limit; ++index) {
                    void *arguments[] = {&index};
                    bool succeeded = false;
                    Il2CppObject *object = sample.invoke(item, list.value, arguments, @"PlayerControl.AllPlayerControls.get_Item", &succeeded);
                    if (!succeeded) break;
                    if (object) [players addObject:sample.player(object, local.value)];
                }
            }
        }
    }
    sample.root[@"players"] = players;
    for (const auto &entry : std::vector<std::pair<Il2CppClass *, NSString *>>{
        {meetingClass, @"meetingActive"}, {exileClass, @"exileActive"}}) {
        if (!entry.first) continue;
        NSString *key = [sample.className(entry.first) stringByAppendingString:@".Instance"];
        const ReadResult instance = sample.read(entry.first, nullptr, "Instance", true, key);
        if (instance.read) sample.root[entry.second] = sample.unityAlive(instance.value);
    }
    return;
}

uint64_t monotonicMilliseconds() {
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}

void releasePending(PendingBait &pending) {
    auto freeHandle = shared().api.gchandle_free;
    if (freeHandle) {
        if (pending.killer) freeHandle(pending.killer);
        if (pending.victim) freeHandle(pending.victim);
        if (pending.victimData) freeHandle(pending.victimData);
    }
    pending.killer = pending.victim = pending.victimData = 0;
}

struct PendingReleaseGuard {
    PendingBait *pending;
    ~PendingReleaseGuard() { if (pending) releasePending(*pending); }
    void disarm() { pending = nullptr; }
};

void releaseRoundAnchor() {
    BaitState &bait = shared().bait;
    if (bait.roundAnchorHandle && shared().api.gchandle_free)
        shared().api.gchandle_free(bait.roundAnchorHandle);
    bait.roundAnchorHandle = 0;
}

void clearPending() {
    for (auto &entry : shared().bait.pending) releasePending(entry.second);
    shared().bait.pending.clear();
}

void lastEvent(NSString *outcome, NSString *reason, uint64_t eventId = 0,
               int killerId = -1, int victimId = -1, uint32_t flags = 0) {
    shared().bait.lastEvent = @{ @"eventId": @(eventId), @"outcome": bounded(outcome),
        @"reason": bounded(reason), @"killerId": @(killerId), @"victimId": @(victimId),
        @"flags": @(flags), @"monotonicMs": @(monotonicMilliseconds()) };
}

bool booleanValue(id value, bool &result) {
    if (![value isKindOfClass:[NSNumber class]]) return false;
    result = [value boolValue];
    return true;
}

bool exactBoolean(id value, bool expected) {
    bool result = false;
    return booleanValue(value, result) && result == expected;
}

Il2CppClass *gameClass(Sample &sample, const char *name) {
    return sample.gameImage ? sample.api.class_from_name(sample.gameImage, "", name) : nullptr;
}

bool objectIsClass(Sample &sample, Il2CppObject *object, Il2CppClass *expected) {
    if (!object || !expected || !sample.api.class_is_assignable_from) return false;
    Il2CppClass *actual = sample.api.object_get_class(object);
    return actual && sample.api.class_is_assignable_from(expected, actual);
}

bool memberBoolean(Sample &sample, Il2CppObject *object, const char *name,
                    NSString *key, bool &value) {
    if (!object) return false;
    ReadResult result = sample.read(sample.api.object_get_class(object), object, name, false, key);
    // Only accept an actual managed Boolean, never a reference/enum coerced to it.
    if (!result.read || !result.type || sample.api.type_get_type(result.type) != Boolean) return false;
    return booleanValue(sample.scalar(result), value);
}

bool playerId(Sample &sample, Il2CppObject *object, uint8_t &value) {
    if (!object) return false;
    ReadResult result = sample.read(sample.api.object_get_class(object), object, "PlayerId", false, @"PlayerControl.PlayerId");
    if (!result.read) return false;
    NSNumber *number = sample.numericValue(result.value, result.type);
    if (!number || number.longLongValue < 0 || number.longLongValue >= 254) return false;
    value = number.unsignedCharValue;
    return true;
}

Il2CppObject *playerData(Sample &sample, Il2CppObject *player) {
    if (!player) return nullptr;
    ReadResult result = sample.read(sample.api.object_get_class(player), player, "Data", false, @"PlayerControl.Data");
    return result.read && objectIsClass(sample, result.value, gameClass(sample, "NetworkedPlayerInfo")) ? result.value : nullptr;
}

const MethodInfo *reportMethod(Sample &sample) {
    Il2CppClass *player = gameClass(sample, "PlayerControl");
    Il2CppClass *networked = gameClass(sample, "NetworkedPlayerInfo");
    if (!player || !networked || !sample.api.class_from_type || !sample.api.type_is_byref) return nullptr;
    const MethodInfo *method = sample.method(player, "CmdReportDeadBody", 1, false);
    const Il2CppType *returnType = method ? sample.api.method_get_return_type(method) : nullptr;
    if (!returnType || sample.api.type_get_type(returnType) != 0x01) return nullptr;
    const Il2CppType *parameter = sample.api.method_get_param(method, 0);
    // The actual installed build must provide this exact managed reference type.
    if (!parameter || sample.api.type_is_byref(parameter) || sample.api.type_get_type(parameter) != 0x12 ||
        sample.api.class_from_type(parameter) != networked) return nullptr;
    return method;
}

bool murderFailureMask(Sample &sample, uint32_t &mask) {
    Il2CppClass *player = gameClass(sample, "PlayerControl");
    if (!player || !sample.api.class_from_type || !sample.api.type_is_byref) return false;
    const MethodInfo *method = sample.method(player, "MurderPlayer", 2, false);
    const Il2CppType *returnType = method ? sample.api.method_get_return_type(method) : nullptr;
    if (!returnType || sample.api.type_get_type(returnType) != 0x01) return false;
    const Il2CppType *targetType = sample.api.method_get_param(method, 0);
    const Il2CppType *flagsType = sample.api.method_get_param(method, 1);
    if (!targetType || !flagsType || sample.api.type_is_byref(targetType) || sample.api.type_is_byref(flagsType) ||
        sample.api.type_get_type(targetType) != 0x12 || sample.api.class_from_type(targetType) != player) return false;
    Il2CppClass *flagsClass = sample.api.class_from_type(flagsType);
    if (!flagsClass || !sample.api.class_is_enum(flagsClass) ||
        ![nativeText(sample.api.class_get_name(flagsClass)) isEqualToString:@"MurderResultFlags"]) return false;
    const Il2CppType *underlyingType = sample.api.class_enum_basetype(flagsClass);
    if (!underlyingType) return false;
    const int underlyingKind = sample.api.type_get_type(underlyingType);
    if (underlyingKind != I4 && underlyingKind != U4) return false;
    bool protectedFound = false, failedFound = false;
    mask = 0;
    void *iter = nullptr;
    for (size_t i = 0; i < kMaxMembers; ++i) {
        FieldInfo *field = sample.api.class_get_fields(flagsClass, &iter);
        if (!field) break;
        if (!(sample.api.field_get_flags(field) & kLiteral)) continue;
        const char *name = sample.api.field_get_name(field);
        if (!name) continue;
        const bool protectedFlag = std::strcmp(name, "FailedProtected") == 0;
        const bool failedFlag = std::strcmp(name, "FailedError") == 0;
        if (!protectedFlag && !failedFlag) continue;
        Il2CppObject *boxed = sample.api.field_get_value_object(field, nullptr);
        NSNumber *number = sample.numericValue(boxed, sample.api.field_get_type(field));
        if (!number || number.unsignedLongLongValue > std::numeric_limits<uint32_t>::max() || number.unsignedIntValue == 0) return false;
        mask |= number.unsignedIntValue;
        protectedFound |= protectedFlag;
        failedFound |= failedFlag;
    }
    return protectedFound && failedFound;
}

struct Session {
    bool known = false;
    bool started = false;
    bool host = false;
    bool tasks = false;
    uintptr_t anchor = 0;
    Il2CppObject *anchorObject = nullptr;
};

Session sessionFromSample(Sample &sample) {
    Session result;
    if (![sample.root[@"status"] isEqual:@"live_sample"]) return result;
    NSDictionary *client = sample.root[@"client"];
    NSDictionary *state = [client[@"gameState"] isKindOfClass:[NSDictionary class]] ? client[@"gameState"] : nil;
    NSString *stateName = [state[@"name"] isKindOfClass:[NSString class]] ? state[@"name"] : nil;
    bool isHost = false;
    if (!stateName || !booleanValue(client[@"amHost"], isHost) || !exactBoolean(client[@"objectAlive"], true)) return result;
    result.known = true;
    result.host = isHost;
    result.started = [stateName isEqualToString:@"Started"] && exactBoolean(client[@"isGameStarted"], true);
    if (!result.started) return result;
    Il2CppClass *shipClass = gameClass(sample, "ShipStatus");
    if (!shipClass) return result;
    ReadResult ship = sample.read(shipClass, nullptr, "Instance", true, @"ShipStatus.Instance");
    if (!ship.read || !ship.value || !exactBoolean(sample.unityAlive(ship.value), true)) return result;
    result.anchor = reinterpret_cast<uintptr_t>(ship.value);
    result.anchorObject = ship.value;
    NSDictionary *networkMode = [client[@"networkMode"] isKindOfClass:[NSDictionary class]] ? client[@"networkMode"] : nil;
    NSString *mode = [networkMode[@"name"] isKindOfClass:[NSString class]] ? networkMode[@"name"] : nil;
    const bool supportedMode = [mode isEqualToString:@"OnlineGame"] || [mode isEqualToString:@"LocalGame"];
    result.tasks = result.host && supportedMode && exactBoolean(sample.root[@"meetingActive"], false) &&
        exactBoolean(sample.root[@"exileActive"], false);
    return result;
}

void syncBaitLifecycle(Sample &sample) {
    BaitState &bait = shared().bait;
    if (!bait.core) {
        bait.core = ehr_core_create(static_cast<uint32_t>(monotonicMilliseconds()));
        if (bait.core) ehr_core_configure(bait.core, bait.config);
    }
    bait.gcAvailable = sample.api.gchandle_new && sample.api.gchandle_get_target && sample.api.gchandle_free &&
        sample.api.class_from_type && sample.api.class_is_assignable_from && sample.api.type_is_byref;
    bait.reportSignatureAvailable = sample.gameImage && reportMethod(sample);
    uint32_t ignoredMask = 0;
    bait.callbackSignatureAvailable = sample.gameImage && murderFailureMask(sample, ignoredMask);
    Session session = sessionFromSample(sample);
    if (!bait.running) {
        clearPending();
        releaseRoundAnchor();
        bait.wasStarted = false;
        bait.activeTasks = false;
        bait.isHost = session.known && session.host;
        if (bait.core) ehr_core_set_phase(bait.core, EHR_LOBBY);
        return;
    }
    Il2CppObject *previousAnchor = bait.roundAnchorHandle && sample.api.gchandle_get_target ?
        sample.api.gchandle_get_target(bait.roundAnchorHandle) : nullptr;
    const bool newRound = bait.gcAvailable && session.known && session.started && session.anchor &&
        (!bait.wasStarted || previousAnchor != session.anchorObject);
    if (newRound) {
        clearPending();
        uintptr_t newAnchor = sample.api.gchandle_new(session.anchorObject, false);
        releaseRoundAnchor();
        bait.roundAnchorHandle = newAnchor;
        bait.wasStarted = newAnchor != 0;
        if (newAnchor) {
            ++bait.round;
            if (bait.core) ehr_core_begin_round(bait.core, bait.round, session.host);
        }
    }
    if (session.known && !session.started) {
        bait.wasStarted = false;
        releaseRoundAnchor();
    }
    bait.isHost = session.known && session.host;
    bait.activeTasks = bait.running && bait.roundAnchorHandle && session.known && session.started && session.anchor && session.tasks;
    if (bait.core) {
        ehr_core_set_host(bait.core, bait.isHost);
        ehr_core_set_phase(bait.core, bait.activeTasks ? EHR_TASKS : EHR_LOBBY);
    }
    if (!bait.activeTasks || !bait.config.enabled) clearPending();
}

NSDictionary *baitStatus() {
    const BaitState &bait = shared().bait;
    return @{ @"ruleSubset": @"Bait auto-report with manually selected player; normal reporting only",
        @"running": @(bait.running),
        @"enabled": @(bait.config.enabled != 0), @"selectedPlayerId": @(bait.selectedPlayerId),
        @"delayMinSeconds": @(bait.config.delay_min_seconds), @"delayMaxSeconds": @(bait.config.delay_max_seconds),
        @"callbackObserved": @(bait.callbackObserved), @"callbackCount": @(bait.callbackCount),
        @"confirmedMurderCallbacks": @(bait.confirmedCount), @"callbackSignatureAvailable": @(bait.callbackSignatureAvailable),
        @"reportSignatureAvailable": @(bait.reportSignatureAvailable), @"gcHandlesAvailable": @(bait.gcAvailable),
        @"adapterAvailable": @(bait.callbackObserved && bait.callbackSignatureAvailable && bait.reportSignatureAvailable && bait.gcAvailable),
        @"armed": @(bait.config.enabled && bait.selectedPlayerId >= 0 && bait.activeTasks && bait.isHost &&
            bait.callbackObserved && bait.callbackSignatureAvailable && bait.reportSignatureAvailable && bait.gcAvailable),
        @"roundGeneration": @(bait.round), @"host": @(bait.isHost), @"activeTasks": @(bait.activeTasks),
        @"pendingReports": @(bait.pending.size()), @"reportCallsAttempted": @(bait.reportsAttempted),
        @"reportCallsCompleted": @(bait.reportCallsCompleted),
        @"lastEvent": bait.lastEvent ?: (id)[NSNull null] };
}

void publishBaitStatus() {
    NSDictionary *status = baitStatus();
    std::lock_guard<std::mutex> lock(shared().snapshotMutex);
    shared().baitSnapshot = status;
}

void appendBaitStatus(Sample &sample) {
    NSDictionary *status = baitStatus();
    sample.root[@"bait"] = status;
    sample.root[@"EHRGameCallbackLastEvent"] = shared().bait.lastEvent ?: (id)[NSNull null];
    sample.root[@"automaticBaitAvailable"] = status[@"adapterAvailable"];
    sample.root[@"gameplayMutationPerformed"] = @(shared().bait.reportsAttempted > 0);
    publishBaitStatus();
}

bool pendingObjectsValid(Sample &sample, const PendingBait &pending,
                          Il2CppObject *&killer, Il2CppObject *&data) {
    if (!shared().bait.gcAvailable) return false;
    killer = sample.api.gchandle_get_target(pending.killer);
    Il2CppObject *victim = sample.api.gchandle_get_target(pending.victim);
    data = sample.api.gchandle_get_target(pending.victimData);
    Il2CppClass *playerClass = gameClass(sample, "PlayerControl");
    if (!objectIsClass(sample, killer, playerClass) || !objectIsClass(sample, victim, playerClass) ||
        !exactBoolean(sample.unityAlive(killer), true) || !exactBoolean(sample.unityAlive(victim), true)) return false;
    uint8_t killerId = 255, victimId = 255;
    if (!playerId(sample, killer, killerId) || !playerId(sample, victim, victimId) ||
        killerId != pending.killerId || victimId != pending.victimId || killerId == victimId) return false;
    Il2CppObject *killerData = playerData(sample, killer);
    if (!killerData || playerData(sample, victim) != data) return false;
    bool killerDead = true, victimDead = false, killerDisconnected = true, victimDisconnected = true;
    return memberBoolean(sample, killerData, "IsDead", @"NetworkedPlayerInfo.IsDead", killerDead) && !killerDead &&
        memberBoolean(sample, data, "IsDead", @"NetworkedPlayerInfo.IsDead", victimDead) && victimDead &&
        memberBoolean(sample, killerData, "Disconnected", @"NetworkedPlayerInfo.Disconnected", killerDisconnected) && !killerDisconnected &&
        memberBoolean(sample, data, "Disconnected", @"NetworkedPlayerInfo.Disconnected", victimDisconnected) && !victimDisconnected;
}

void pollBait() {
    BaitState &bait = shared().bait;
    if (!bait.core || bait.pending.empty()) return;
    EHRAction action{};
    if (!ehr_core_poll(bait.core, monotonicMilliseconds(), &action)) return;
    // Remove it before invoking game code: the call can cause reentrant callbacks.
    auto entry = bait.pending.find(action.event_id);
    if (entry == bait.pending.end()) return;
    PendingBait pending = entry->second;
    PendingReleaseGuard guard{&pending};
    bait.pending.erase(entry);
    Sample sample;
    populateSample(sample);
    syncBaitLifecycle(sample); // Fresh host/round/meeting check at dispatch time.
    Il2CppObject *killer = nullptr, *data = nullptr;
    if (bait.config.enabled && bait.activeTasks && bait.isHost && pending.round == bait.round &&
        action.round_id == bait.round && action.kind == EHR_REPORT_BODY &&
        pending.victimId == bait.selectedPlayerId && pendingObjectsValid(sample, pending, killer, data)) {
        const MethodInfo *method = reportMethod(sample);
        if (method) {
            ++bait.reportsAttempted;
            bool succeeded = false;
            // Managed reference parameter: direct object pointer, NOT &data.
            void *arguments[] = {data};
            sample.invoke(method, killer, arguments, @"PlayerControl.CmdReportDeadBody", &succeeded);
            if (succeeded) ++bait.reportCallsCompleted;
            lastEvent(succeeded ? @"report_call_completed" : @"report_call_failed",
                succeeded ? @"Managed report call returned; meeting/network result remains game-owned" :
                (sample.errors.lastObject ?: @"Managed exception or unavailable report method"), action.event_id, pending.killerId, pending.victimId);
        } else {
            lastEvent(@"cancelled", @"Report method signature unavailable at dispatch", action.event_id, pending.killerId, pending.victimId);
        }
    } else {
        lastEvent(@"cancelled", @"Host/round/phase/player/body validation failed at dispatch", action.event_id, pending.killerId, pending.victimId);
    }
    // The report call may already have created a meeting. Refresh only on the
    // next normal sample; never emit more than one gameplay call per timer tick.
    appendBaitStatus(sample);
}

void confirmedMurder(Il2CppObject *killer, Il2CppObject *victim, uint32_t flags) {
    BaitState &bait = shared().bait;
    const uint64_t eventId = ++bait.callbackCount;
    if (!bait.running) {
        lastEvent(@"ignored", @"Bridge stopped; raw callback pointers were not dereferenced", eventId, -1, -1, flags);
        publishBaitStatus();
        return;
    }
    Sample sample;
    populateSample(sample);
    syncBaitLifecycle(sample);
    uint32_t failureMask = 0;
    Il2CppClass *player = gameClass(sample, "PlayerControl");
    uint8_t killerId = 255, victimId = 255;
    if (!bait.gcAvailable || !bait.callbackSignatureAvailable || !objectIsClass(sample, killer, player) ||
        !objectIsClass(sample, victim, player) || !exactBoolean(sample.unityAlive(killer), true) ||
        !exactBoolean(sample.unityAlive(victim), true) || !playerId(sample, killer, killerId) ||
        !playerId(sample, victim, victimId) || !murderFailureMask(sample, failureMask)) {
        lastEvent(@"rejected", @"Runtime signature, GC handles, or callback player validation unavailable", eventId, killerId, victimId, flags);
        publishBaitStatus();
        return;
    }
    Il2CppObject *data = playerData(sample, victim);
    bool dead = false;
    if ((flags & failureMask) || !data || !memberBoolean(sample, data, "IsDead", @"NetworkedPlayerInfo.IsDead", dead) || !dead) {
        lastEvent(@"ignored", @"Protected/failed attempt or victim is not confirmed dead after original call", eventId, killerId, victimId, flags);
        publishBaitStatus();
        return;
    }
    bait.callbackObserved = true;
    ++bait.confirmedCount;
    if (!bait.core || !bait.config.enabled || !bait.activeTasks || !bait.isHost ||
        victimId != bait.selectedPlayerId || killerId == victimId || !bait.reportSignatureAvailable) {
        lastEvent(@"observed", @"Actual confirmed callback; selected Bait/host/phase/config gates not all satisfied", eventId, killerId, victimId, flags);
        publishBaitStatus();
        return;
    }
    PendingBait pending;
    PendingReleaseGuard guard{&pending};
    pending.killer = sample.api.gchandle_new(killer, false);
    pending.victim = sample.api.gchandle_new(victim, false);
    pending.victimData = sample.api.gchandle_new(data, false);
    pending.round = bait.round;
    pending.killerId = killerId;
    pending.victimId = victimId;
    if (!pending.killer || !pending.victim || !pending.victimData) {
        lastEvent(@"rejected", @"Could not root all pending managed objects", eventId, killerId, victimId, flags);
        publishBaitStatus();
        return;
    }
    // Round the event timestamp upward by one millisecond. Polling uses floor
    // milliseconds, so the core's 150 ms minimum can never fire a fraction of a
    // millisecond early because of integer timestamp truncation.
    EHRMurderEvent event{eventId, bait.round, monotonicMilliseconds() + 1, killerId, victimId, 1, 0};
    EHRStatus status = ehr_core_confirmed_murder(bait.core, event);
    if (status == EHR_SCHEDULED && bait.pending.size() < 32) {
        bait.pending.emplace(eventId, pending);
        guard.disarm();
        lastEvent(@"scheduled", @"Confirmed selected Bait death; managed objects rooted until validated dispatch", eventId, killerId, victimId, flags);
    } else {
        lastEvent(@"ignored", status == EHR_DUPLICATE ? @"Duplicate victim in this round" : @"Core rejected or pending capacity reached", eventId, killerId, victimId, flags);
    }
    publishBaitStatus();
}

NSDictionary *sampleRuntime() {
    Sample sample;
    populateSample(sample);
    syncBaitLifecycle(sample);
    appendBaitStatus(sample);
    return sample.root;
}

NSDictionary<NSString *, id> *publishSample() {
    NSDictionary *snapshot = nil;
    @try {
        // Deep immutable Foundation copy, without retaining any runtime objects.
        NSDictionary *mutableSnapshot = sampleRuntime();
        NSError *serializationError = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:mutableSnapshot options:0 error:&serializationError];
        if (data) snapshot = [NSJSONSerialization JSONObjectWithData:data options:0 error:&serializationError];
        if (!snapshot) snapshot = @{ @"schema": @"ehr.live-runtime.v1", @"status": @"snapshot_serialization_failed",
            @"errors": @[bounded(serializationError.localizedDescription ?: @"Unknown serialization error")],
            @"gameplayMutationPerformed": @NO, @"automaticBaitAvailable": @NO };
    } @catch (NSException *exception) {
        // Objective-C exceptions are reported; native/IL2CPP faults cannot be
        // safely caught here and are not disguised as successful samples.
        snapshot = @{ @"schema": @"ehr.live-runtime.v1", @"status": @"bridge_exception",
            @"errors": @[bounded(exception.reason ?: exception.name)],
            @"gameplayMutationPerformed": @NO, @"automaticBaitAvailable": @NO };
    }
    {
        std::lock_guard<std::mutex> lock(shared().snapshotMutex);
        shared().snapshot = snapshot;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:EHRLiveBridgeSnapshotNotification object:snapshot];
    return snapshot;
}

} // namespace

void EHRLiveBridgeStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (shared().timer) return;
        shared().bait.running = true;
        shared().timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(shared().timer, dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                                 500 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(shared().timer, ^{
            @autoreleasepool { publishSample(); }
        });
        dispatch_resume(shared().timer);
        shared().bait.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(shared().bait.timer, dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                                 50 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(shared().bait.timer, ^{
            @autoreleasepool {
                @try { pollBait(); }
                @catch (NSException *exception) {
                    clearPending();
                    if (shared().bait.core) ehr_core_set_phase(shared().bait.core, EHR_LOBBY);
                    lastEvent(@"dispatch_exception", bounded(exception.reason ?: exception.name));
                    publishBaitStatus();
                }
            }
        });
        dispatch_resume(shared().bait.timer);
        publishBaitStatus();
    });
}

void EHRLiveBridgeStop(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (shared().timer) {
            dispatch_source_cancel(shared().timer);
            shared().timer = nil;
        }
        if (shared().bait.timer) {
            dispatch_source_cancel(shared().bait.timer);
            shared().bait.timer = nil;
        }
        shared().bait.running = false;
        shared().bait.activeTasks = false;
        clearPending();
        releaseRoundAnchor();
        shared().bait.wasStarted = false;
        if (shared().bait.core) ehr_core_set_phase(shared().bait.core, EHR_LOBBY);
        publishBaitStatus();
    });
}

NSDictionary<NSString *, id> *EHRLiveBridgeCopySnapshot(void) {
    std::lock_guard<std::mutex> lock(shared().snapshotMutex);
    return shared().snapshot ?: @{ @"schema": @"ehr.live-runtime.v1", @"status": @"not_sampled",
        @"gameplayMutationPerformed": @NO, @"automaticBaitAvailable": @NO };
}

NSDictionary<NSString *, id> *EHRLiveBridgeSampleNow(void) {
    if ([NSThread isMainThread]) return publishSample();
    __block NSDictionary *snapshot = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ @autoreleasepool { snapshot = publishSample(); } });
    return snapshot;
}

int EHRLiveBridgeConfigureBait(int enabled, int selectedPlayerId, int minimum, int maximum) {
    if ((enabled != 0 && enabled != 1) || selectedPlayerId < -1 || selectedPlayerId >= 254 ||
        (enabled && selectedPlayerId < 0) || minimum < 0 || maximum < 0 || minimum > 90 || maximum > 90) return 0;
    void (^apply)(void) = ^{
        BaitState &bait = shared().bait;
        const bool changed = bait.config.enabled != enabled || bait.selectedPlayerId != selectedPlayerId ||
            bait.config.delay_min_seconds != minimum || bait.config.delay_max_seconds != maximum;
        if (changed) {
            clearPending();
            if (bait.core) ehr_core_set_phase(bait.core, EHR_LOBBY);
        }
        bait.config = {enabled, minimum, maximum, 0};
        bait.selectedPlayerId = selectedPlayerId;
        if (bait.core) {
            ehr_core_configure(bait.core, bait.config);
            ehr_core_set_phase(bait.core, bait.activeTasks ? EHR_TASKS : EHR_LOBBY);
        }
        if (changed) lastEvent(@"configuration_changed", @"Manual Bait selection/settings updated; pending reports cancelled");
        publishBaitStatus();
    };
    if ([NSThread isMainThread]) apply();
    else dispatch_sync(dispatch_get_main_queue(), apply);
    return 1;
}

NSDictionary<NSString *, id> *EHRLiveBridgeCopyBaitStatus(void) {
    std::lock_guard<std::mutex> lock(shared().snapshotMutex);
    return shared().baitSnapshot ?: @{ @"enabled": @NO, @"selectedPlayerId": @(-1),
        @"adapterAvailable": @NO, @"callbackObserved": @NO, @"armed": @NO, @"status": @"not_sampled" };
}

void EHRLiveBridgeOnConfirmedMurder(void *killer, void *victim, uint32_t flags) {
    if (![NSThread isMainThread]) {
        // Never queue these raw managed pointers across threads or retain them
        // without a runtime handle on the owning Unity thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            lastEvent(@"rejected", @"Post-MurderPlayer callback was not on Unity main thread", 0, -1, -1, flags);
            publishBaitStatus();
        });
        return;
    }
    @autoreleasepool {
        @try { confirmedMurder(static_cast<Il2CppObject *>(killer), static_cast<Il2CppObject *>(victim), flags); }
        @catch (NSException *exception) {
            lastEvent(@"callback_exception", bounded(exception.reason ?: exception.name));
            publishBaitStatus();
        }
    }
}

#ifndef EHR_LIVE_BRIDGE_AUTOSTART
#define EHR_LIVE_BRIDGE_AUTOSTART 1
#endif
#if EHR_LIVE_BRIDGE_AUTOSTART
__attribute__((constructor)) static void EHRLiveBridgeLoaded(void) {
    EHRLiveBridgeStart();
}
#endif
