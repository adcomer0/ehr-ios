#import "EHRAppleAuthDiagnostics.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include "EHRRuntimePinnedAssociation.h"
#include "EHRRuntimeDiagnostics.h"
#if EHR_HAS_AUTH_HANDOFF
#include "EHRAuthHandoffDiagnostics.h"
#endif
#include <atomic>
#include <cstring>
#include <dlfcn.h>
#include <limits>

namespace {
using Request = void (*)(id, SEL, id, uint32_t);
using Completion = void (*)(id, SEL, id, id);
constexpr uint64_t limit = 1000000;
std::atomic<uint64_t> requests{0}, successes{0}, errors{0}, overlaps{0}, observerFaults{0};
std::atomic<uint32_t> lastDomain{0};
std::atomic<int32_t> lastCode{0}, installStatus{-1};
std::atomic<IMP> originals[3];
bool installed = false; // Main-thread installation only.

uint64_t increment(std::atomic<uint64_t> &value) {
    auto current = value.load(std::memory_order_relaxed);
    while (current < limit && !value.compare_exchange_weak(current, current + 1,
            std::memory_order_relaxed)) {}
    return current < limit ? current + 1 : limit;
}
void publishCounters() {
    EHRRuntimeDiagnosticsRecordAuthCounters(requests.load(std::memory_order_relaxed),
        successes.load(std::memory_order_relaxed), errors.load(std::memory_order_relaxed),
        overlaps.load(std::memory_order_relaxed));
}
NSObject *lockObject() {
    static NSObject *object = [NSObject new];
    return object;
}
NSHashTable *controllers() {
    static NSHashTable *table = [NSHashTable hashTableWithOptions:
        NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
    return table;
}
void observeRequest(id controller) {
    increment(requests);
    @synchronized (lockObject()) {
        auto table = controllers();
        if (table.count) increment(overlaps);
        if (controller && table.count < 64) [table addObject:controller];
    }
}
void observeCompletion(id controller) {
    @synchronized (lockObject()) {
        if (controller) [controllers() removeObject:controller];
    }
}
void request(id self, SEL cmd, id controller, uint32_t requestID) {
    @try { observeRequest(controller); publishCounters(); }
    @catch (__unused NSException *exception) { increment(observerFaults); }
    auto original = reinterpret_cast<Request>(originals[0].load(std::memory_order_acquire));
    original(self, cmd, controller, requestID);
}
void success(id self, SEL cmd, id controller, id authorization) {
    @try { observeCompletion(controller); increment(successes);
#if EHR_HAS_AUTH_HANDOFF
        EHRAuthHandoffDiagnosticsRecordAppleSuccess();
#endif
        publishCounters(); }
    @catch (__unused NSException *exception) { increment(observerFaults); }
    auto original = reinterpret_cast<Completion>(originals[1].load(std::memory_order_acquire));
    original(self, cmd, controller, authorization);
}
void error(id self, SEL cmd, id controller, id suppliedError) {
    @try {
        observeCompletion(controller);
        uint32_t domain = 0;
        int32_t code = 0;
        if ([suppliedError isKindOfClass:NSError.class]) {
            NSError *nativeError = suppliedError;
            // No arbitrary string is retained or passed to the writer. Never
            // read localizedDescription, userInfo, underlying errors or tokens.
            if ([nativeError.domain isEqualToString:@"com.apple.AuthenticationServices.AuthorizationError"]) domain = 1;
            else if ([nativeError.domain isEqualToString:NSOSStatusErrorDomain]) domain = 2;
            else if ([nativeError.domain isEqualToString:NSCocoaErrorDomain]) domain = 3;
            else if ([nativeError.domain isEqualToString:NSURLErrorDomain]) domain = 4;
            auto raw = nativeError.code;
            if (raw >= INT32_MIN && raw <= INT32_MAX) code = static_cast<int32_t>(raw);
        }
        lastDomain.store(domain, std::memory_order_relaxed);
        lastCode.store(code, std::memory_order_relaxed);
        const auto count = increment(errors);
        publishCounters();
        EHRRuntimeDiagnosticsRecordAuth(domain, code, count);
    } @catch (__unused NSException *exception) { increment(observerFaults); }
    auto original = reinterpret_cast<Completion>(originals[2].load(std::memory_order_acquire));
    original(self, cmd, controller, suppliedError);
}
struct Entry {
    const char *selector;
    const char *encoding;
    uint64_t rva;
    IMP replacement;
};
const Entry entries[] = {
    {"performAuthorizationRequestsForController:withRequestId:", "v28@0:8@16I24", 0x23568, reinterpret_cast<IMP>(request)},
    {"authorizationController:didCompleteWithAuthorization:", "v32@0:8@16@24", 0x23640, reinterpret_cast<IMP>(success)},
    {"authorizationController:didCompleteWithError:", "v32@0:8@16@24", 0x23858, reinterpret_cast<IMP>(error)},
};
Method ownMethod(Class klass, SEL selector) {
    unsigned count = 0;
    Method *methods = class_copyMethodList(klass, &count);
    Method found = nullptr;
    for (unsigned i = 0; i < count; ++i)
        if (method_getName(methods[i]) == selector) found = methods[i];
    free(methods);
    return found;
}
bool validate(IMP imp, uint64_t expectedRVA) {
    const auto pointer = reinterpret_cast<const void *>(imp);
    if (ehr_pinned::validate_engine_entry(pointer) != EHR_RUNTIME_OK) return false;
    Dl_info image{};
    if (!dladdr(pointer, &image) || !image.dli_fbase) return false;
    const auto base = reinterpret_cast<uintptr_t>(image.dli_fbase);
    const auto address = reinterpret_cast<uintptr_t>(pointer);
    return address >= base && address - base == expectedRVA;
}
using Validator = bool (*)(IMP, uint64_t);
int32_t install(Class klass, Validator validator) {
    if (!NSThread.isMainThread) return 1;
    if (!klass) return 3;
    Method methods[3]{};
    IMP actual[3]{};
    for (size_t i = 0; i < 3; ++i) {
        methods[i] = ownMethod(klass, sel_registerName(entries[i].selector));
        if (!methods[i] || method_getNumberOfArguments(methods[i]) != 4 ||
                !method_getTypeEncoding(methods[i]) ||
                std::strcmp(method_getTypeEncoding(methods[i]), entries[i].encoding)) return 4;
        actual[i] = method_getImplementation(methods[i]);
        if (installed) {
            if (actual[i] != entries[i].replacement || !originals[i].load()) return 4;
        } else if (!actual[i] || !validator(actual[i], entries[i].rva)) return 2;
    }
    if (installed) return 0;
    // All selectors/types/whole-image pins are checked before any mutation.
    // Originals are published before any forwarding IMP can run.
    for (size_t i = 0; i < 3; ++i) originals[i].store(actual[i], std::memory_order_release);
    for (size_t i = 0; i < 3; ++i) method_setImplementation(methods[i], entries[i].replacement);
    installed = true;
    return 0;
}
}

int32_t EHRAppleAuthDiagnosticsInstall(void) {
    int32_t result = 4;
    @try { result = install(NSClassFromString(@"AppleAuthManager"), validate); }
    @catch (__unused NSException *exception) { increment(observerFaults); }
    installStatus.store(result, std::memory_order_relaxed);
    @try { publishCounters(); }
    @catch (__unused NSException *exception) { increment(observerFaults); }
    return result;
}
NSDictionary *EHRAppleAuthDiagnosticsCopyStatus(void) {
    uint64_t active = 0;
    @try { @synchronized (lockObject()) { active = controllers().count; } }
    @catch (__unused NSException *exception) { increment(observerFaults); }
    return @{@"install": @(installStatus.load()), @"requests": @(requests.load()),
        @"successCallbacks": @(successes.load()), @"errorCallbacks": @(errors.load()),
        @"overlapObservations": @(overlaps.load()), @"activeObserved": @(active),
        @"lastDomain": @(lastDomain.load()), @"lastCode": @(lastCode.load()),
        @"observerFaults": @(observerFaults.load()), @"authSuppressed": @0};
}

#ifdef EHR_APPLE_AUTH_OBSERVER_FIXTURE
// Standalone own-source test only. Production has no configurable class/pin.
int32_t EHRAppleAuthDiagnosticsInstallForFixture(Class klass, Validator validator) {
    return install(klass, validator);
}
#endif
