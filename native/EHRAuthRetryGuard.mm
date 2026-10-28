#include "EHRAuthRetryGuard.h"
#include "EHRAuthRetryScope.hpp"
#include "EHRAuthRetryBinding.generated.h"
#include "EHRNativeHooks.h"
#include "EHRRuntimeGateway.h"
#include "EHRRuntimeMetadataPrivate.h"
#include "EHRRuntimePinnedAssociation.h"
#include "EHRRuntimeActionPrivate.h"
#include "EHRRuntimeIteratorPrivate.h"
#include <atomic>
#include <cstring>
#include <dlfcn.h>

namespace {
using Method = void (*)(void *, const void *);
struct API {
    const void *(*class_get_parent)(const void *);
    const void *(*class_get_methods)(const void *, void **);
    const char *(*method_get_name)(const void *);
    const void *(*class_get_type)(const void *);
    char *(*type_get_name)(const void *);
    void (*runtime_free)(void *);
    void *(*class_get_fields)(const void *, void **);
    const char *(*field_get_name)(void *);
    uint32_t (*field_get_flags)(void *);
    const void *(*field_get_type)(void *);
    const void *(*class_from_type)(const void *);
    bool (*class_is_inited)(const void *);
    void (*field_static_get_value)(void *, void *);
    void (*field_get_value)(void *, void *, void *);
    const void *(*object_get_class)(void *);
};
API api{};
const void *accountClass = nullptr, *eosClass = nullptr, *parentClass = nullptr, *failureMetadata = nullptr;
void *instanceField = nullptr, *tryingField = nullptr;
std::atomic<int32_t> prepared{EHR_RUNTIME_NOT_READY};
std::atomic<bool> enabled{false};
std::atomic<bool> startupRequested{false};
std::atomic<int32_t> startupPrepareStatus{EHR_RUNTIME_NOT_READY}, startupEnableStatus{EHR_RUNTIME_NOT_READY};
std::atomic<uint64_t> failureEntries{0}, completed{0}, forwarded{0}, unavailable{0};
std::atomic<int32_t> lastStatus{EHR_RUNTIME_NOT_READY};
constexpr uint64_t retryRVA = 0x1b0fd70, failureRVA = 0x1b06374;
using Resolver = void *(*)(const char *);
void *publicSymbol(const char *name) { return dlsym(RTLD_DEFAULT, name); }
template<class T> bool load(T &field, Resolver resolve, const char *name) {
    auto value = resolve(name);
    if (!value || ehr_pinned::validate_engine_entry(value) != EHR_RUNTIME_OK) return false;
    field = reinterpret_cast<T>(value); return true;
}
bool typeName(const void *type, const char *expected) {
    char *name = type ? api.type_get_name(type) : nullptr;
    const bool equal = name && !strcmp(name, expected);
    if (name) api.runtime_free(name);
    return equal;
}
bool hasNoClassConstructor(const void *klass) {
    void *iterator=nullptr;
    for (size_t count=0;count<4096;++count) {
        const void *method=api.class_get_methods(klass,&iterator);
        if (!method) return true;
        const char *name=api.method_get_name(method);
        if (!name || !strcmp(name,".cctor")) return false;
    }
    return false;
}
void *exactField(const void *owner, const char *name, const char *type, bool isStatic) {
    void *iterator = nullptr, *found = nullptr;
    for (size_t count = 0; count < 4096; ++count) {
        void *field = api.class_get_fields(owner, &iterator);
        if (!field) return found;
        const char *actual = api.field_get_name(field);
        if (!actual || strcmp(name, actual)) continue;
        if (found || bool(api.field_get_flags(field) & 16) != isStatic ||
            !typeName(api.field_get_type(field), type)) return nullptr;
        found = field;
    }
    return nullptr;
}
int32_t prepare(Resolver resolve) {
    if (!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    if (prepared.load(std::memory_order_acquire) == EHR_RUNTIME_OK) return EHR_RUNTIME_OK;
#define LOAD(field, symbol) if (!load(api.field, resolve, symbol)) return EHR_RUNTIME_NOT_READY
    LOAD(class_get_parent,"il2cpp_class_get_parent"); LOAD(class_get_type,"il2cpp_class_get_type");
    LOAD(class_get_methods,"il2cpp_class_get_methods"); LOAD(method_get_name,"il2cpp_method_get_name");
    LOAD(type_get_name,"il2cpp_type_get_name"); LOAD(runtime_free,"il2cpp_free");
    LOAD(class_get_fields,"il2cpp_class_get_fields"); LOAD(field_get_name,"il2cpp_field_get_name");
    LOAD(field_get_flags,"il2cpp_field_get_flags"); LOAD(field_get_type,"il2cpp_field_get_type");
    LOAD(class_from_type,"il2cpp_class_from_type"); LOAD(class_is_inited,"il2cpp_class_is_inited");
    LOAD(field_static_get_value,"il2cpp_field_static_get_value"); LOAD(field_get_value,"il2cpp_field_get_value");
    LOAD(object_get_class,"il2cpp_object_get_class");
#undef LOAD
    EHRRuntimeToken account = 0, eos = 0, failure = 0, retry = 0;
    auto status = ehr_runtime_find_class("Assembly-CSharp.dll","","AccountManager",&account);
    if (!status) status = ehr_runtime_find_class("Assembly-CSharp.dll","","EOSManager",&eos);
    if (!status) status = ehr_runtime_find_method(account,"PlatformSignInFail",nullptr,0,"System.Void",0,&failure);
    if (!status) status = ehr_runtime_find_method(eos,"LoginWithCorrectPlatform",nullptr,0,"System.Void",0,&retry);
    uint64_t observed = 0;
    if (!status) status = ehr_runtime_validate_native_method(failure,failureRVA,&observed);
    if (!status) status = ehr_runtime_validate_native_method(retry,retryRVA,&observed);
    const void *declaring = nullptr;
    if (!status) status = EHRRuntimeBorrowMethod(failure,&failureMetadata,&declaring);
    if (!status) status = EHRRuntimeBorrowClass(account,&accountClass);
    if (!status) status = EHRRuntimeBorrowClass(eos,&eosClass);
    if (!status && (!failureMetadata || declaring != accountClass)) status = EHR_RUNTIME_TYPE_MISMATCH;
    if (!status) {
        parentClass = api.class_get_parent(accountClass);
        if (!parentClass || !typeName(api.class_get_type(parentClass),"DestroyableSingleton<AccountManager>"))
            status = EHR_RUNTIME_TYPE_MISMATCH;
        else if (!hasNoClassConstructor(parentClass)) status = EHR_RUNTIME_UNSUPPORTED;
    }
    if (!status) {
        instanceField = exactField(parentClass,"_instance","AccountManager",true);
        tryingField = exactField(eosClass,"tryingToLogin","System.Boolean",false);
        if (!instanceField || !tryingField || api.class_from_type(api.field_get_type(instanceField)) != accountClass)
            status = EHR_RUNTIME_TYPE_MISMATCH;
    }
    prepared.store(status,std::memory_order_release); lastStatus.store(status,std::memory_order_relaxed);
    return status;
}
struct Root { EHRRuntimeToken token=0; ~Root(){if(token)ehr_runtime_object_release(token);} };
struct PreparedFailure { Root receiver, receiverPin, strong, pin; void *object=nullptr; Method method=nullptr; const void *metadata=nullptr; };
int32_t prepareFailure(void *self, PreparedFailure &call) {
    if (!NSThread.isMainThread || prepared.load(std::memory_order_acquire)) return EHR_RUNTIME_NOT_READY;
    // The validated invocation frame supplies self. Enter the gateway first:
    // its ready/domain check must precede every direct public-API read below.
    auto status=EHRRuntimeActionRootBorrowed(self,&call.receiver.token);
    void *receiver=nullptr;
    if (!status) status=EHRRuntimeIteratorPin(call.receiver.token,&call.receiverPin.token,&receiver);
    if (status) return status;
    if (!receiver || api.object_get_class(receiver) != eosClass) return EHR_RUNTIME_TYPE_MISMATCH;
    uint8_t trying = 1;
    api.field_get_value(receiver,tryingField,&trying);
    if (trying != 0) return EHR_RUNTIME_NOT_READY;
    // Static get is allowed only for existing initialized storage: no getter,
    // constructor, class initializer or new Unity object can be triggered here.
    if (!api.class_is_inited(parentClass)) return EHR_RUNTIME_NOT_READY;
    void *account = nullptr;
    api.field_static_get_value(instanceField,&account);
    if (!account) return EHR_RUNTIME_NOT_READY;
    if (api.object_get_class(account) != accountClass) return EHR_RUNTIME_TYPE_MISMATCH;
    status=EHRRuntimeActionRootBorrowed(account,&call.strong.token);
    if (!status) status=EHRRuntimeIteratorPin(call.strong.token,&call.pin.token,&call.object);
    if (status) return status;
    call.method=reinterpret_cast<Method>(EHRNativeHooksImageBaseForDiagnostics()+failureRVA);
    call.metadata=failureMetadata;
    return EHR_RUNTIME_OK;
}
}

extern "C" int32_t EHRAuthRetryGuardPrepare(void) {
    @try { try { return prepare(publicSymbol); } catch (...) { return EHR_RUNTIME_LIMIT; } }
    @catch (__unused NSException *exception) { return EHR_RUNTIME_NOT_READY; }
}
extern "C" int32_t EHRAuthRetryGuardSetEnabled(int32_t value) {
    if (!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    if (value != 0 && value != 1) return EHR_RUNTIME_BAD_ARGUMENT;
    if (value && prepared.load(std::memory_order_acquire)) return EHR_RUNTIME_NOT_READY;
    enabled.store(value != 0,std::memory_order_release); return EHR_RUNTIME_OK;
}
extern "C" int32_t EHRAuthRetryGuardStart(int32_t requested) {
    if (!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    if (requested != 0 && requested != 1) return EHR_RUNTIME_BAD_ARGUMENT;
    startupRequested.store(requested != 0,std::memory_order_release);
    if (!requested) return EHR_RUNTIME_OK;
    const auto status=EHRAuthRetryGuardPrepare();
    startupPrepareStatus.store(status,std::memory_order_release);
    if (status != EHR_RUNTIME_OK) return status;
    const auto activated=EHRAuthRetryGuardSetEnabled(1);
    startupEnableStatus.store(activated,std::memory_order_release);
    return activated;
}
extern "C" NSDictionary<NSString *, id> *EHRAuthRetryGuardCopyStatus(void) {
    return @{ @"preparedStatus":@(prepared.load()), @"enabled":@(enabled.load()),
        @"startupRequested":@(startupRequested.load()), @"startupPrepareStatus":@(startupPrepareStatus.load()),
        @"startupEnableStatus":@(startupEnableStatus.load()),
        @"failureHandlerEntries":@(failureEntries.load()), @"failureHandlerCompleted":@(completed.load()),
        @"originalRetryForwards":@(forwarded.load()), @"unavailablePreflight":@(unavailable.load()),
        @"lastStatus":@(lastStatus.load()) };
}
extern "C" __attribute__((visibility("default")))
void ehr_native_eos_platform_retry_guard(void *self, const void *methodInfo) {
    const auto original=reinterpret_cast<Method>(EHRNativeHooksImageBaseForDiagnostics()+EHRAuthRetryTrampolineRVA);
    PreparedFailure failure;
    int32_t status=EHR_RUNTIME_NOT_READY;
    if (enabled.load(std::memory_order_acquire) && ehr_auth_retry::eligible(self,NSThread.isMainThread)) {
        @try { try { status=prepareFailure(self,failure); } catch (...) { status=EHR_RUNTIME_LIMIT; } }
        @catch (__unused NSException *exception) { status=EHR_RUNTIME_NOT_READY; }
        lastStatus.store(status,std::memory_order_relaxed);
        if (status == EHR_RUNTIME_OK) {
            // Original normal7000 callback already performed credential cleanup,
            // native checks and tryingToLogin=false before this nested call.
            // Only substitute its automatic retry with the real native failure
            // UI route. Never catch/retry after entering that handler.
            ehr_auth_retry::consume(); failureEntries.fetch_add(1);
            failure.method(failure.object,failure.metadata);
            completed.fetch_add(1); return;
        }
        unavailable.fetch_add(1);
    }
    forwarded.fetch_add(1); original(self,methodInfo);
}
