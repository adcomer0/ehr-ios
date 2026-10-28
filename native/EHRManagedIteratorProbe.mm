#import "EHRManagedIteratorProbe.h"
#include "EHRManagedIteratorAdapter.h"
#include "EHRRuntimeReflection.h"
#include <vector>

NSDictionary<NSString *, id> *EHRManagedIteratorSelfTest(void) {
#if EHR_HAS_MANAGED_RULES
    if (!NSThread.isMainThread) return @{ @"success": @NO, @"status": @(EHR_RUNTIME_WRONG_THREAD) };
    EHRManagedIteratorHostV1 table{}; EHRManagedIteratorMakeTable(&table);
    EHRManagedIteratorCallbacksV1 callbacks{};
    const int32_t bound = ehr_iterator_bind_gateway(&table, sizeof(table), &callbacks, sizeof(callbacks));
    const auto routed = bound == 0 ? EHRManagedIteratorSetCallbacks(&callbacks) : EHR_RUNTIME_NOT_READY;
    const auto before = EHRManagedIteratorRegistrationCount();
    const auto currentBefore = EHRManagedIteratorCurrentRootCount();
    std::vector<EHRRuntimeToken> roots;
    auto keep = [&](EHRRuntimeToken token) { if (token) roots.push_back(token); };
    EHRRuntimeToken listClass = 0, list = 0, exception = 0, getEnumerator = 0, carrier = 0, ordinary = 0;
    auto status = routed;
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_class("mscorlib.dll", "System.Collections", "ArrayList", &listClass);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_construct(listClass, nullptr, 0, &list, &exception);
    keep(list); keep(exception);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_method(listClass, "GetEnumerator", nullptr, 0, "System.Collections.IEnumerator", 0, &getEnumerator);
    exception = 0;
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_invoke(getEnumerator, list, nullptr, 0, &carrier, &exception);
    keep(carrier); keep(exception); exception = 0;
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_invoke(getEnumerator, list, nullptr, 0, &ordinary, &exception);
    keep(ordinary); keep(exception);
    EHRManagedIteratorProofV1 proof{};
    const int32_t managed = status == EHR_RUNTIME_OK ? ehr_iterator_self_test(carrier, ordinary, &proof, sizeof(proof)) : status;
    bool released = true;
    for (const auto token : roots) released = ehr_runtime_object_release(token) == EHR_RUNTIME_OK && released;
    const auto after = EHRManagedIteratorRegistrationCount(), currentAfter = EHRManagedIteratorCurrentRootCount();
    const bool success = bound == 0 && routed == EHR_RUNTIME_OK && status == EHR_RUNTIME_OK && managed == 0 &&
        proof.abi_version == 1 && proof.byte_size == sizeof(proof) && proof.pass == 1 && released && before == after && currentBefore == currentAfter;
    return @{ @"success": @(success), @"bindStatus": @(bound), @"routeStatus": @(routed), @"setupStatus": @(status), @"managedStatus": @(managed),
        @"sourceSideEffects": @(proof.side_effects), @"sourceDisposedOnce": @(proof.disposed_once), @"nullYield": @(proof.null_yield),
        @"actualNativeStringYield": @(proof.string_yield), @"repeatedCurrentSameIdentity": @(proof.repeated_current_identity),
        @"resetCaughtNotSupportedException": @(proof.reset_exception), @"beforeCurrentCaughtInvalidOperationException": @(proof.before_current_exception),
        @"afterCurrentCaughtInvalidOperationException": @(proof.after_current_exception), @"ordinaryEmptyEnumeratorUnchanged": @(proof.unregistered_fallback),
        @"completionRemainsFalse": @(proof.completed_false), @"registrationClosed": @(proof.registrations_closed),
        @"registrationsBefore": @(before), @"registrationsAfter": @(after), @"currentRootsBefore": @(currentBefore), @"currentRootsAfter": @(currentAfter),
        @"externalRootsReleased": @(released), @"hostTableBytes": @(sizeof(table)), @"callbacksBytes": @(sizeof(callbacks)),
        @"manualRuntimeInvokeOnly": @YES, @"unityStartCoroutineTested": @NO, @"nativePointersExposed": @NO,
        @"gameplayMutationPerformed": @NO, @"fullEHRAvailable": @NO };
#else
    return @{ @"success": @NO, @"status": @"managed_rules_not_built", @"unityStartCoroutineTested": @NO };
#endif
}
