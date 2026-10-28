#import "EHRNativeHooks.h"
#import "EHRLiveBridge.h"
#include "EHRRuntimeOriginal.h"
#include "EHRHookBinding.generated.h"

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#if EHR_HAS_MANAGED_RULES
#include "EHRManagedBridgeV1.h"
#endif

// This library is a normal dependency of the personal, pre-sign game copy.
// The build adds separate RX/RW segments to that copy and binds entry stubs to
// these exports. Prefixes honor skip-original; postfixes call the original first.
// No executable memory is allocated or written at runtime.
namespace {
std::atomic<uintptr_t> imageBase{0};
std::atomic<uint64_t> murderCalls{0};
std::atomic<uint64_t> versionCalls{0};
std::atomic<uint64_t> moddedVersionCalls{0};
std::atomic<uint64_t> cachedModeChecks{0};
std::atomic<uint64_t> skippedModeChecks{0};
std::atomic<uint64_t> managedVersionCalls{0};
std::atomic<uint64_t> managedVersionErrors{0};
std::atomic<uint64_t> moddedPredicateCalls{0};
std::atomic<uint64_t> moddedPredicateOriginalCalls{0};
std::atomic<uint64_t> managedPredicatePrefixCalls{0};
std::atomic<uint64_t> managedPredicatePrefixErrors{0};

uintptr_t checkedImageBase() {
    uintptr_t cached = imageBase.load(std::memory_order_acquire);
    if (cached) return cached;
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *name = _dyld_get_image_name(i);
        if (!name || !strstr(name, "/UnityFramework.framework/UnityFramework")) continue;
        const auto *header = reinterpret_cast<const mach_header_64 *>(_dyld_get_image_header(i));
        if (!header || header->magic != MH_MAGIC_64 || header->ncmds > 4096 || header->sizeofcmds > 1024 * 1024) continue;
        const uint8_t *cursor = reinterpret_cast<const uint8_t *>(header + 1);
        const uint8_t *end = cursor + header->sizeofcmds;
        bool match = false;
        for (uint32_t c = 0; c < header->ncmds; ++c) {
            if (size_t(end - cursor) < sizeof(load_command)) break;
            const auto *command = reinterpret_cast<const load_command *>(cursor);
            if (command->cmdsize < sizeof(load_command) || command->cmdsize > size_t(end - cursor)) break;
            if (command->cmd == LC_UUID && command->cmdsize == sizeof(uuid_command)) {
                const auto *uuid = reinterpret_cast<const uuid_command *>(cursor);
                match = memcmp(uuid->uuid, EHRHookImageUUID, sizeof(uuid->uuid)) == 0;
            }
            cursor += command->cmdsize;
        }
        if (match) {
            cached = reinterpret_cast<uintptr_t>(header);
            imageBase.store(cached, std::memory_order_release);
            return cached;
        }
    }
    // An intercepted game method must always execute its original body. A
    // mismatched binding is a build error; continuing would corrupt gameplay.
    NSLog(@"EHR: pinned UnityFramework UUID was not found; refusing an invalid trampoline");
    abort();
}

bool onlineGame() {
    static thread_local bool sampling = false;
    if (sampling) {
        skippedModeChecks.fetch_add(1, std::memory_order_relaxed);
        return false;
    }
    struct SamplingGuard {
        bool &value;
        explicit SamplingGuard(bool &flag) : value(flag) { value = true; }
        ~SamplingGuard() { value = false; }
    } guard(sampling);
    // The bridge never exposes managed pointers. A fresh main-thread sample is
    // safe here; worker calls use its last immutable sample without blocking.
    @try {
        if (!NSThread.isMainThread) cachedModeChecks.fetch_add(1, std::memory_order_relaxed);
        NSDictionary *snapshot = NSThread.isMainThread ? EHRLiveBridgeSampleNow() : EHRLiveBridgeCopySnapshot();
        id client = snapshot[@"client"];
        if (![client isKindOfClass:NSDictionary.class]) return false;
        id mode = client[@"networkMode"];
        if (![mode isKindOfClass:NSDictionary.class]) return false;
        return [mode[@"name"] isKindOfClass:NSString.class] && [mode[@"name"] isEqualToString:@"OnlineGame"];
    } @catch (__unused NSException *exception) {
        skippedModeChecks.fetch_add(1, std::memory_order_relaxed);
        return false;
    }
}
}

extern "C" __attribute__((visibility("default")))
uintptr_t EHRNativeHooksImageBaseForDiagnostics(void) { return checkedImageBase(); }

extern "C" __attribute__((visibility("default")))
void ehr_native_murder_hook(void *killer, void *victim, uint32_t resultFlags, const void *methodInfo) {
    using Original = void (*)(void *, void *, uint32_t, const void *);
    auto original = reinterpret_cast<Original>(checkedImageBase() + EHRMurderTrampolineRVA);
    original(killer, victim, resultFlags, methodInfo);
    murderCalls.fetch_add(1, std::memory_order_relaxed);
    EHRLiveBridgeOnConfirmedMurder(killer, victim, resultFlags);
}

#if EHR_HAS_VERSION_HOOK
extern "C" __attribute__((visibility("default")))
int32_t ehr_native_broadcast_version_hook(const void *methodInfo) {
    using Original = int32_t (*)(const void *);
    auto original = reinterpret_cast<Original>(checkedImageBase() + EHRVersionTrampolineRVA);
    if (EHRTryConsumeOriginalInvocation(EHR_ORIGINAL_TARGET_BROADCAST_VERSION, methodInfo)) return original(methodInfo);
    int32_t result = original(methodInfo);
    versionCalls.fetch_add(1, std::memory_order_relaxed);
    const bool online = onlineGame();
#if EHR_HAS_MANAGED_RULES
    // Exact unchanged upstream source, compiled before signing by NativeAOT.
    // This postfix receives an observed mode and never re-enters the getter.
    int32_t modified = result;
    if (ehr_managed_server_version_postfix(result, online ? 1 : 0, 0, &modified) == 0) {
        managedVersionCalls.fetch_add(1, std::memory_order_relaxed);
        if (modified != result) moddedVersionCalls.fetch_add(1, std::memory_order_relaxed);
        return modified;
    }
    managedVersionErrors.fetch_add(1, std::memory_order_relaxed);
#endif
    // Native-only builds retain the previously tested modulo-50 behavior.
    if (online && result >= 0 && result % 50 < 25 && result <= INT32_MAX - 25) {
        result += 25;
        moddedVersionCalls.fetch_add(1, std::memory_order_relaxed);
    }
    return result;
}
#endif

#if EHR_HAS_IS_MODDED_HOOK
extern "C" __attribute__((visibility("default")))
bool ehr_native_is_version_modded_hook(const void *methodInfo) {
    using Original = bool (*)(const void *);
    auto original = reinterpret_cast<Original>(checkedImageBase() + EHRIsModdedTrampolineRVA);
    if (EHRTryConsumeOriginalInvocation(EHR_ORIGINAL_TARGET_IS_VERSION_MODDED, methodInfo)) return original(methodInfo);
    moddedPredicateCalls.fetch_add(1, std::memory_order_relaxed);
#if EHR_HAS_MANAGED_RULES
    int32_t result = 0, runOriginal = 1;
    const int32_t status = ehr_managed_is_version_modded_prefix(&result, &runOriginal);
    if (status == 0 && (result == 0 || result == 1) && (runOriginal == 0 || runOriginal == 1)) {
        managedPredicatePrefixCalls.fetch_add(1, std::memory_order_relaxed);
        if (!runOriginal) return result != 0;
    } else managedPredicatePrefixErrors.fetch_add(1, std::memory_order_relaxed);
#endif
    moddedPredicateOriginalCalls.fetch_add(1, std::memory_order_relaxed);
    return original(methodInfo);
}
#endif

NSDictionary<NSString *, id> *EHRNativeHooksCopyStatus(void) {
    return @{
        @"entryInterceptorsBuilt": @YES,
        @"pinnedImageObserved": @(imageBase.load(std::memory_order_acquire) != 0),
        @"murderCallbacks": @(murderCalls.load(std::memory_order_relaxed)),
        @"broadcastVersionCallbacks": @(versionCalls.load(std::memory_order_relaxed)),
        @"broadcastOriginalBypasses": @(EHROriginalInvocationBypassCount()),
#if EHR_HAS_VERSION_HOOK
        @"broadcastVersionOriginalRVA": @(EHRVersionMethodRVA),
#endif
        @"moddedBroadcastVersions": @(moddedVersionCalls.load(std::memory_order_relaxed)),
        @"broadcastChecksUsingCachedMode": @(cachedModeChecks.load(std::memory_order_relaxed)),
        @"broadcastChecksSkipped": @(skippedModeChecks.load(std::memory_order_relaxed)),
        @"managedVersionPostfixCalls": @(managedVersionCalls.load(std::memory_order_relaxed)),
        @"managedVersionPostfixErrors": @(managedVersionErrors.load(std::memory_order_relaxed)),
        @"isVersionModdedCallbacks": @(moddedPredicateCalls.load(std::memory_order_relaxed)),
        @"isVersionModdedOriginalCalls": @(moddedPredicateOriginalCalls.load(std::memory_order_relaxed)),
        @"managedIsVersionModdedPrefixes": @(managedPredicatePrefixCalls.load(std::memory_order_relaxed)),
        @"managedIsVersionModdedPrefixErrors": @(managedPredicatePrefixErrors.load(std::memory_order_relaxed)),
        @"runtimeExecutableWrites": @NO,
        @"fullEHRAvailable": @NO
    };
}

#include "EHRManagedIteratorHooks.inc"
#include "EHRStaticClassHooks.inc"
