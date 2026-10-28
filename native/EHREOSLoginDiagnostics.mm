#include "EHREOSLoginDiagnostics.h"
#include "EHREOSLoginBinding.generated.h"
#include "EHRNativeHooks.h"
#include "EHRRuntimeGateway.h"
#include "EHRRuntimeMetadataPrivate.h"
#include "EHRRuntimeDiagnostics.h"
#include <atomic>

namespace {
using Getter = int32_t (*)(const void *, const void *);
using Callback = void (*)(void *, void *, const void *);
constexpr uint64_t getterRVA = 0x1aae088;
constexpr uint64_t normalRVA = 0x1b10078;
constexpr uint64_t silentRVA = 0x1b137d0;
constexpr uint64_t limit = 1000000;
std::atomic<Getter> getter{nullptr};
std::atomic<const void *> getterMetadata{nullptr};
std::atomic<int32_t> prepareStatus{EHR_RUNTIME_NOT_READY};
std::atomic<uint64_t> observations[2]{};

uint64_t increment(std::atomic<uint64_t> &value) noexcept {
    auto current = value.load(std::memory_order_relaxed);
    while (current < limit && !value.compare_exchange_weak(current, current + 1,
        std::memory_order_relaxed)) {}
    return current < limit ? current + 1 : limit;
}
EHRRuntimeStatus method(EHRRuntimeToken klass, const char *name,
    const char *const *parameters, size_t count, const char *returns,
    uint64_t expectedRVA, EHRRuntimeToken *token) {
    auto status = ehr_runtime_find_method(klass, name, parameters, count, returns, 0, token);
    if (status != EHR_RUNTIME_OK) return status;
    uint64_t observed = 0;
    return ehr_runtime_validate_native_method(*token, expectedRVA, &observed);
}
void observe(uint32_t phase, void *info) noexcept {
    // Never inspect/copy this mixed-reference struct, ClientData, IDs, credentials
    // or strings. Only call its exact pinned public ResultCode getter.
    @try {
        try {
            const auto count = increment(observations[phase - 1]);
            int32_t status = prepareStatus.load(std::memory_order_acquire);
            int32_t result = 0;
            const auto read = getter.load(std::memory_order_acquire);
            const auto metadata = getterMetadata.load(std::memory_order_acquire);
            if (!info) status = EHR_RUNTIME_BAD_ARGUMENT;
            else if (status == EHR_RUNTIME_OK && read && metadata) result = read(info, metadata);
            else if (status == EHR_RUNTIME_OK) status = EHR_RUNTIME_NOT_READY;
            EHRRuntimeDiagnosticsRecordEOSLogin(phase, result, status, count);
        } catch (...) { /* Optional observer failure must not change login. */ }
    } @catch (__unused NSException *exception) { /* Original still runs. */ }
}
}

extern "C" int32_t EHREOSLoginDiagnosticsPrepare(void) {
    if (!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    if (prepareStatus.load(std::memory_order_acquire) == EHR_RUNTIME_OK) return EHR_RUNTIME_OK;
    EHRRuntimeToken owner = 0, info = 0, callback = 0, resultGetter = 0;
    auto status = ehr_runtime_find_class("Assembly-CSharp.dll", "", "EOSManager", &owner);
    const char *parameters[] = {"Epic.OnlineServices.Connect.LoginCallbackInfo&"};
    if (status == EHR_RUNTIME_OK) status = method(owner, "EOSConnectPlatformLoginCallback", parameters,
        1, "System.Void", normalRVA, &callback);
    if (status == EHR_RUNTIME_OK) status = method(owner, "EOSConnectPlatformSilentLoginCallback", parameters,
        1, "System.Void", silentRVA, &callback);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_class("Assembly-CSharp-firstpass.dll",
        "Epic.OnlineServices.Connect", "LoginCallbackInfo", &info);
    if (status == EHR_RUNTIME_OK) status = method(info, "get_ResultCode", nullptr,
        0, "Epic.OnlineServices.Result", getterRVA, &resultGetter);
    const void *metadata = nullptr, *declaringClass = nullptr;
    if (status == EHR_RUNTIME_OK) status = EHRRuntimeBorrowMethod(resultGetter, &metadata, &declaringClass);
    if (status == EHR_RUNTIME_OK && (!metadata || !declaringClass)) status = EHR_RUNTIME_NOT_READY;
    if (status == EHR_RUNTIME_OK) {
        // validate_native_method has checked source allowlist, loaded UUID,
        // signed framework hash, public metadata facts and executable bounds.
        // This is a native-only immutable metadata borrow, never a C# pointer.
        const auto base = EHRNativeHooksImageBaseForDiagnostics();
        getterMetadata.store(metadata, std::memory_order_release);
        getter.store(reinterpret_cast<Getter>(base + getterRVA), std::memory_order_release);
    }
    prepareStatus.store(status, std::memory_order_release);
    return status;
}

extern "C" __attribute__((visibility("default")))
void ehr_native_eos_platform_login_observer(void *self, void *info, const void *methodInfo) {
    auto original = reinterpret_cast<Callback>(EHRNativeHooksImageBaseForDiagnostics() + EHREOSPlatformLoginTrampolineRVA);
    observe(1, info);
    original(self, info, methodInfo);
}
extern "C" __attribute__((visibility("default")))
void ehr_native_eos_silent_login_observer(void *self, void *info, const void *methodInfo) {
    auto original = reinterpret_cast<Callback>(EHRNativeHooksImageBaseForDiagnostics() + EHREOSPlatformSilentLoginTrampolineRVA);
    observe(2, info);
    original(self, info, methodInfo);
}
