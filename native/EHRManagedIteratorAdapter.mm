#import <Foundation/Foundation.h>
#include "EHRManagedIteratorAdapter.h"
#include "EHRManagedIteratorProduction.h"
#include "EHRRuntimeIteratorPrivate.h"
#include <array>
#include <memory>
#include <mutex>
#include <unordered_map>

namespace {
struct Entry {
    uint64_t registration = 0, source = 0;
    EHRRuntimeToken carrier = 0, current = 0;
    void *identity = nullptr;
    bool executing = false, terminal = false, hasCurrent = false, cancelRequested = false, sourceCancelled = false;
};
struct Registry {
    EHRManagedIteratorCallbacksV1 callbacks{};
    bool bound = false;
    uint64_t next = UINT64_C(0x4954455200000001);
    std::mutex mutex;
    std::unordered_map<uint64_t, std::shared_ptr<Entry>> entries;
    std::unordered_map<void *, std::shared_ptr<Entry>> identities;
};
Registry &registry() { static Registry value; return value; }
int32_t cancelSource(Entry &entry) {
    if (entry.sourceCancelled) return 0;
    entry.sourceCancelled = true;
    return registry().callbacks.cancel(entry.source);
}
std::shared_ptr<Entry> lookup(void *identity) {
    auto &r = registry(); std::lock_guard<std::mutex> lock(r.mutex);
    const auto found = r.identities.find(identity);
    return found == r.identities.end() ? nullptr : found->second;
}
void releaseCurrent(Entry &entry) {
    if (entry.current) {
        if (ehr_runtime_object_release(entry.current) != EHR_RUNTIME_OK) abort();
        entry.current = 0;
    }
    entry.hasCurrent = false;
}
EHRRuntimeStatus validate(EHRRuntimeToken carrier) {
    EHRRuntimeToken expected = 0, actual = 0;
    auto status = ehr_runtime_find_class("mscorlib.dll", "System.Collections", "ArrayList+ArrayListEnumeratorSimple", &expected);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_object_class(carrier, &actual);
    if (status != EHR_RUNTIME_OK) return status;
    if (actual != expected) return EHR_RUNTIME_TYPE_MISMATCH;
    struct MethodSpec { const char *name, *result; uint64_t rva; };
    constexpr std::array<MethodSpec, 3> methods{{
        {"MoveNext", "System.Boolean", UINT64_C(0x367ade0)},
        {"get_Current", "System.Object", UINT64_C(0x367afe4)},
        {"Reset", "System.Void", UINT64_C(0x367b0dc)}}};
    for (const auto &method : methods) {
        EHRRuntimeToken token = 0; uint64_t observed = 0;
        status = ehr_runtime_find_method(expected, method.name, nullptr, 0, method.result, 0, &token);
        if (status == EHR_RUNTIME_OK) status = ehr_runtime_validate_native_method(token, method.rva, &observed);
        if (status != EHR_RUNTIME_OK) return status;
    }
    return EHR_RUNTIME_OK;
}
int32_t registerCarrier(EHRRuntimeToken carrier, uint64_t source, uint64_t *registration) {
    if (!registration) return EHR_RUNTIME_BAD_ARGUMENT;
    *registration = 0;
    if (!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    auto &r = registry();
    if (!r.bound || !source) return EHR_RUNTIME_BAD_ARGUMENT;
    auto status = validate(carrier); if (status != EHR_RUNTIME_OK) return status;
    try {
        auto entry = std::make_shared<Entry>();
        status = EHRRuntimeIteratorPin(carrier, &entry->carrier, &entry->identity);
        if (status != EHR_RUNTIME_OK) return status;
        if (EHRProductionIteratorOwnsIdentity(entry->identity)) { ehr_runtime_object_release(entry->carrier); return EHR_RUNTIME_BAD_ARGUMENT; }
        std::lock_guard<std::mutex> lock(r.mutex);
        if (r.entries.size() >= 256 || r.next == UINT64_MAX || r.identities.count(entry->identity)) {
            ehr_runtime_object_release(entry->carrier); return EHR_RUNTIME_BAD_ARGUMENT;
        }
        entry->source = source; entry->registration = r.next++;
        try { r.entries.emplace(entry->registration, entry); r.identities.emplace(entry->identity, entry); }
        catch (...) { r.entries.erase(entry->registration); r.identities.erase(entry->identity); ehr_runtime_object_release(entry->carrier); throw; }
        *registration = entry->registration; return EHR_RUNTIME_OK;
    } catch (...) { return EHR_RUNTIME_LIMIT; }
}
int32_t releaseCarrier(uint64_t token) {
    if (!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    auto &r = registry(); std::shared_ptr<Entry> entry;
    {
        std::lock_guard<std::mutex> lock(r.mutex);
        const auto found = r.entries.find(token);
        if (found == r.entries.end()) return EHR_RUNTIME_INVALID_TOKEN;
        entry = found->second;
        if (entry->executing) return EHR_RUNTIME_BAD_ARGUMENT;
        r.entries.erase(found); r.identities.erase(entry->identity);
    }
    // Remove native routing before disposing source. Reentry cannot find it.
    const int32_t cancelled = cancelSource(*entry);
    releaseCurrent(*entry);
    const auto released = ehr_runtime_object_release(entry->carrier); entry->carrier = 0;
    return cancelled != 0 ? cancelled : released;
}
struct Executing {
    Entry &entry;
    explicit Executing(Entry &value) : entry(value) { entry.executing = true; }
    ~Executing() { entry.executing = false; }
};
}
void EHRManagedIteratorMakeTable(EHRManagedIteratorHostV1 *table) {
    if (table) *table = {1, sizeof(*table), registerCarrier, releaseCarrier,
        [](EHRRuntimeToken a, EHRRuntimeToken b, int32_t *same) -> int32_t { return ehr_runtime_object_same(a, b, same); },
        [](EHRRuntimeToken object, EHRRuntimeToken *klass) -> int32_t { return ehr_runtime_object_class(object, klass); }};
}
EHRRuntimeStatus EHRManagedIteratorSetCallbacks(const EHRManagedIteratorCallbacksV1 *table) {
    if (!NSThread.isMainThread) return EHR_RUNTIME_WRONG_THREAD;
    if (!table || table->abi_version != 1 || table->byte_size != sizeof(*table) || !table->step || !table->reset || !table->cancel) return EHR_RUNTIME_BAD_ARGUMENT;
    auto &r = registry();
    if (r.bound && (r.callbacks.step != table->step || r.callbacks.reset != table->reset || r.callbacks.cancel != table->cancel)) return EHR_RUNTIME_BAD_ARGUMENT;
    r.callbacks = *table; r.bound = true; return EHR_RUNTIME_OK;
}
uint64_t EHRManagedIteratorRegistrationCount(void) {
    auto &r = registry(); std::lock_guard<std::mutex> lock(r.mutex); return r.entries.size();
}
uint64_t EHRManagedIteratorCurrentRootCount(void) {
    if (!NSThread.isMainThread) return UINT64_MAX;
    auto &r = registry(); std::lock_guard<std::mutex> lock(r.mutex);
    uint64_t count = 0; for (const auto &item : r.entries) count += item.second->current ? 1 : 0; return count;
}
bool EHRManagedIteratorOwnsIdentity(void *identity) { return lookup(identity) != nullptr; }
bool EHRManagedIteratorMoveNext(void *identity, bool *result) {
    if (EHRProductionIteratorMoveNext(identity, result)) return true;
    auto entry = lookup(identity); if (!entry) return false;
    if (!result) abort(); *result = false;
    // Unexpected worker drive is contained without executing source/runtime.
    if (!NSThread.isMainThread) return true;
    if (entry->executing) { entry->cancelRequested = true; EHRRuntimeIteratorRaise(EHR_RUNTIME_BAD_ARGUMENT); }
    if (entry->terminal) return true;
    releaseCurrent(*entry);
    int32_t next = 0; EHRRuntimeToken current = 0; int32_t status;
    { Executing guard(*entry); status = registry().callbacks.step(entry->source, &next, &current); }
    if (status != 0 || entry->cancelRequested || (next != 0 && next != 1) || (!next && current)) {
        if (current) ehr_runtime_object_release(current);
        entry->terminal = true; cancelSource(*entry);
        EHRRuntimeIteratorRaise(status == EHR_RUNTIME_UNSUPPORTED ? EHR_RUNTIME_UNSUPPORTED : EHR_RUNTIME_BAD_ARGUMENT);
    }
    if (current) {
        void *value = nullptr;
        if (EHRRuntimeIteratorBorrow(current, &value) != EHR_RUNTIME_OK || !value) {
            ehr_runtime_object_release(current); entry->terminal = true; cancelSource(*entry);
            EHRRuntimeIteratorRaise(EHR_RUNTIME_INVALID_TOKEN);
        }
    }
    entry->current = current; entry->hasCurrent = next != 0; entry->terminal = next == 0;
    *result = next != 0; return true;
}
bool EHRManagedIteratorCurrent(void *identity, void **result) {
    if (EHRProductionIteratorCurrent(identity, result)) return true;
    auto entry = lookup(identity); if (!entry) return false;
    if (!result) abort(); *result = nullptr;
    if (!NSThread.isMainThread) return true;
    if (entry->executing) { entry->cancelRequested = true; EHRRuntimeIteratorRaise(EHR_RUNTIME_BAD_ARGUMENT); }
    if (!entry->hasCurrent) EHRRuntimeIteratorRaise(EHR_RUNTIME_BAD_ARGUMENT);
    if (EHRRuntimeIteratorBorrow(entry->current, result) != EHR_RUNTIME_OK) EHRRuntimeIteratorRaise(EHR_RUNTIME_INVALID_TOKEN);
    return true;
}
bool EHRManagedIteratorReset(void *identity) {
    if (EHRProductionIteratorReset(identity)) return true;
    auto entry = lookup(identity); if (!entry) return false;
    if (!NSThread.isMainThread) return true;
    if (entry->executing) { entry->cancelRequested = true; EHRRuntimeIteratorRaise(EHR_RUNTIME_BAD_ARGUMENT); }
    int32_t status;
    { Executing guard(*entry); status = registry().callbacks.reset(entry->source); }
    if (entry->cancelRequested) {
        entry->terminal = true; cancelSource(*entry); releaseCurrent(*entry);
        EHRRuntimeIteratorRaise(EHR_RUNTIME_BAD_ARGUMENT);
    }
    if (status != 0) EHRRuntimeIteratorRaise(static_cast<EHRRuntimeStatus>(status));
    releaseCurrent(*entry); entry->terminal = false; return true;
}
