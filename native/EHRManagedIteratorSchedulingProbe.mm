#import "EHRManagedIteratorSchedulingProbe.h"
#include "EHRManagedIteratorSchedulingV1.h"
#include "EHRManagedIteratorAdapter.h"
#include "EHRRuntimeReflection.h"
#include "EHRRuntimeCollections.h"
#include <vector>

namespace {
struct Session {
    NSMutableDictionary<NSString *, id> *proof = nil;
    NSTimer *timer = nil;
    std::vector<EHRRuntimeToken> roots;
    EHRRuntimeToken owner = 0, start = 0, stop = 0, getEnumerator = 0, listClass = 0;
    EHRRuntimeToken normalCoroutine = 0, cancelCoroutine = 0;
    uint64_t normalSource = 0, cancelSource = 0, registrationsBefore = 0, currentBefore = 0;
    CFAbsoluteTime deadline = 0;
    unsigned phase = 0;
    bool running = false, stopSucceeded = false;
};
// Main-thread-only process state. All native roots are explicitly released by
// finish; no static destructor frees IL2CPP handles after runtime shutdown.
Session &session() { static Session *value = new Session; return *value; }
void keep(EHRRuntimeToken token) { if (token) session().roots.push_back(token); }
EHRRuntimeStatus call(EHRRuntimeToken method, EHRRuntimeToken receiver,
    const EHRRuntimeArgument *arguments, size_t count, EHRRuntimeToken *result) {
    EHRRuntimeToken exception = 0;
    const auto status = ehr_runtime_invoke(method, receiver, arguments, count, result, &exception);
    keep(*result); keep(exception);
    if (exception) session().proof[@"caughtNativeException"] = @YES;
    return status;
}
EHRRuntimeStatus stop(EHRRuntimeToken coroutine) {
    if (!coroutine) return EHR_RUNTIME_OK;
    auto &s = session(); EHRRuntimeToken result = 0;
    const EHRRuntimeArgument argument{EHR_RUNTIME_REFERENCE, 0, coroutine, nullptr, 0};
    return call(s.stop, s.owner, &argument, 1, &result);
}
bool closeSource(uint64_t &source, const char *prefix) {
    if (!source) return true;
    EHRManagedIteratorScheduleStateV1 value{};
    const int32_t status = ehr_iterator_schedule_close(source, &value, sizeof(value));
    auto &proof = session().proof;
    proof[[NSString stringWithFormat:@"%sCloseStatus", prefix]] = @(status);
    proof[[NSString stringWithFormat:@"%sFinalSteps", prefix]] = @(value.steps);
    proof[[NSString stringWithFormat:@"%sFinallyCount", prefix]] = @(value.finally_count);
    if (status == 0) source = 0;
    return status == 0 && value.abi_version == 1 && value.byte_size == sizeof(value);
}
void finish(NSString *state, bool success, int32_t status) {
    auto &s = session();
    [s.timer invalidate]; s.timer = nil;
    // Engine stop precedes dropping any carrier/current/owner roots. On normal
    // completion normalSource is already closed and no extra stop is needed.
    bool stopped = true;
    if (s.normalSource && s.normalCoroutine) stopped = stop(s.normalCoroutine) == EHR_RUNTIME_OK;
    if (s.cancelSource && s.cancelCoroutine && !s.stopSucceeded) stopped = stop(s.cancelCoroutine) == EHR_RUNTIME_OK && stopped;
    bool closed = false;
    if (stopped) {
        const bool normalClosed = closeSource(s.normalSource, "normal");
        const bool cancelClosed = closeSource(s.cancelSource, "cancel");
        closed = normalClosed && cancelClosed;
    }
    bool released = true;
    if (stopped && closed) {
        for (const auto token : s.roots) released = ehr_runtime_object_release(token) == EHR_RUNTIME_OK && released;
        s.roots.clear();
    } else {
        // Failed native stop/close keeps explicit ownership. Never abandon a
        // possible engine user merely to turn the root counter green.
        released = false;
    }
    const auto registrations = EHRManagedIteratorRegistrationCount(), current = EHRManagedIteratorCurrentRootCount();
    s.proof[@"state"] = state; s.proof[@"status"] = @(status);
    s.proof[@"engineStopCleanupSucceeded"] = @(stopped); s.proof[@"sourcesClosed"] = @(closed);
    s.proof[@"rootsReleased"] = @(released); s.proof[@"registrationsAfter"] = @(registrations); s.proof[@"currentRootsAfter"] = @(current);
    s.proof[@"complete"] = @YES;
    s.proof[@"success"] = @(success && stopped && closed && released && registrations == s.registrationsBefore && current == s.currentBefore);
    s.running = false;
}
EHRRuntimeStatus createWait(float seconds, EHRRuntimeToken *wait) {
    EHRRuntimeToken single = 0, waitClass = 0, boxed = 0, exception = 0;
    auto status = ehr_runtime_find_class("mscorlib.dll", "System", "Single", &single);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_box(single, &seconds, sizeof(seconds), &boxed);
    keep(boxed);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_class("UnityEngine.CoreModule.dll", "UnityEngine", "WaitForSecondsRealtime", &waitClass);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_construct(waitClass, &boxed, 1, wait, &exception);
    if (status == EHR_RUNTIME_OK) {
        EHRRuntimeToken actual = 0;
        status = ehr_runtime_object_class(*wait, &actual);
        if (status == EHR_RUNTIME_OK && actual != waitClass) status = EHR_RUNTIME_TYPE_MISMATCH;
    }
    keep(*wait); keep(exception); return status;
}
EHRRuntimeStatus launch(float seconds, uint64_t *source, EHRRuntimeToken *coroutine) {
    auto &s = session();
    EHRRuntimeToken list = 0, exception = 0, carrier = 0, wait = 0, result = 0;
    auto status = ehr_runtime_construct(s.listClass, nullptr, 0, &list, &exception); keep(list); keep(exception);
    if (status == EHR_RUNTIME_OK) status = call(s.getEnumerator, list, nullptr, 0, &carrier);
    if (status == EHR_RUNTIME_OK) status = createWait(seconds, &wait);
    if (status == EHR_RUNTIME_OK) status = static_cast<EHRRuntimeStatus>(ehr_iterator_schedule_create(carrier, wait, source));
    if (status == EHR_RUNTIME_OK && !*source) status = EHR_RUNTIME_BAD_ARGUMENT;
    const EHRRuntimeArgument argument{EHR_RUNTIME_REFERENCE, 0, carrier, nullptr, 0};
    if (status == EHR_RUNTIME_OK) status = call(s.start, s.owner, &argument, 1, &result);
    *coroutine = result;
    if (status == EHR_RUNTIME_OK && !result) return EHR_RUNTIME_NOT_FOUND;
    return status;
}
void tick() {
    auto &s = session(); if (!s.running) return;
    if (CFAbsoluteTimeGetCurrent() > s.deadline) { finish(@"timed_out", false, EHR_RUNTIME_LIMIT); return; }
    EHRManagedIteratorScheduleStateV1 value{};
    const uint64_t source = s.phase == 1 ? s.normalSource : s.cancelSource;
    const int32_t sampled = ehr_iterator_schedule_snapshot(source, &value, sizeof(value));
    if (sampled != 0 || value.abi_version != 1 || value.byte_size != sizeof(value)) {
        finish(@"source_snapshot_failed", false, sampled != 0 ? sampled : EHR_RUNTIME_TYPE_MISMATCH); return;
    }
    s.proof[@"observedSteps"] = @(value.steps);
    if (s.phase == 1 && value.steps == 3 && value.finally_count == 1) {
        s.proof[@"unityDroveNormalSourceToCompletion"] = @YES;
        if (!closeSource(s.normalSource, "normal")) { finish(@"normal_close_failed", false, EHR_RUNTIME_BAD_ARGUMENT); return; }
        const auto status = launch(5.0f, &s.cancelSource, &s.cancelCoroutine);
        if (status != EHR_RUNTIME_OK) { finish(@"cancel_source_start_failed", false, status); return; }
        s.phase = 2; s.proof[@"state"] = @"waiting_to_stop_second_source";
    } else if (s.phase == 2 && value.steps == 2 && value.finally_count == 0) {
        const auto status = stop(s.cancelCoroutine);
        s.stopSucceeded = status == EHR_RUNTIME_OK;
        s.proof[@"actualStopCoroutineSucceeded"] = @(s.stopSucceeded);
        if (!s.stopSucceeded) { finish(@"stop_coroutine_failed", false, status); return; }
        if (!closeSource(s.cancelSource, "cancel")) { finish(@"cancel_close_failed", false, EHR_RUNTIME_BAD_ARGUMENT); return; }
        const bool expected = [s.proof[@"normalFinalSteps"] unsignedIntValue] == 3 && [s.proof[@"normalFinallyCount"] unsignedIntValue] == 1 &&
            [s.proof[@"cancelFinalSteps"] unsignedIntValue] == 2 && [s.proof[@"cancelFinallyCount"] unsignedIntValue] == 1;
        finish(@"completed", expected, expected ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH);
    }
}
EHRRuntimeStatus setupOwner() {
    auto &s = session();
    EHRRuntimeToken ownerClass = 0, ownerType = 0, unityObject = 0, find = 0, behaviour = 0, active = 0, mono = 0;
    auto status = ehr_runtime_find_class("Assembly-CSharp.dll", "", "AmongUsClient", &ownerClass);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_class_type_object(ownerClass, &ownerType);
    keep(ownerType);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_class("UnityEngine.CoreModule.dll", "UnityEngine", "Object", &unityObject);
    const char *findTypes[] = {"System.Type"};
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_method(unityObject, "FindObjectOfType", findTypes, 1, "UnityEngine.Object", 1, &find);
    const EHRRuntimeArgument typeArgument{EHR_RUNTIME_REFERENCE, 0, ownerType, nullptr, 0};
    if (status == EHR_RUNTIME_OK) {
        status = call(find, 0, &typeArgument, 1, &s.owner);
        if (status == EHR_RUNTIME_OK) s.proof[@"existingOwnerSearchCompleted"] = @YES;
    }
    if (status != EHR_RUNTIME_OK) return status;
    s.proof[@"amongUsClientPresent"] = @(s.owner != 0);
    if (!s.owner) {
        // The networking singleton is normally absent before entering a lobby.
        // Only the inherited MonoBehaviour coroutine API is under test: select
        // an already existing active script without constructing a component.
        EHRRuntimeToken monoClass = 0, monoType = 0, findAll = 0, objects = 0;
        status = ehr_runtime_find_class("UnityEngine.CoreModule.dll", "UnityEngine", "MonoBehaviour", &monoClass);
        if (status == EHR_RUNTIME_OK) status = ehr_runtime_class_type_object(monoClass, &monoType);
        keep(monoType);
        if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_method(unityObject, "FindObjectsOfType", findTypes, 1, "UnityEngine.Object[]", 1, &findAll);
        const EHRRuntimeArgument argument{EHR_RUNTIME_REFERENCE, 0, monoType, nullptr, 0};
        if (status == EHR_RUNTIME_OK) status = call(findAll, 0, &argument, 1, &objects);
        int32_t length = 0; EHRRuntimeToken exception = 0;
        if (status == EHR_RUNTIME_OK) status = ehr_runtime_array_length(objects, &length, &exception);
        keep(exception);
        if (status == EHR_RUNTIME_OK && (length < 0 || length > 4096)) return EHR_RUNTIME_LIMIT;
        s.proof[@"existingMonoBehaviourCount"] = @(length);
        if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_class("UnityEngine.CoreModule.dll", "UnityEngine", "Behaviour", &behaviour);
        if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_method(behaviour, "get_isActiveAndEnabled", nullptr, 0, "System.Boolean", 0, &active);
        const int32_t bound = length < 256 ? length : 256;
        for (int32_t index = 0; status == EHR_RUNTIME_OK && !s.owner && index < bound; ++index) {
            EHRRuntimeToken candidate = 0, boxedActive = 0;
            exception = 0;
            status = ehr_runtime_array_get(objects, index, &candidate, &exception);
            keep(candidate); keep(exception);
            if (status != EHR_RUNTIME_OK || !candidate) continue;
            status = call(active, candidate, nullptr, 0, &boxedActive);
            uint8_t enabled = 0; size_t bytes = 0;
            if (status == EHR_RUNTIME_OK) status = ehr_runtime_copy_value(boxedActive, &enabled, sizeof(enabled), &bytes);
            if (status == EHR_RUNTIME_OK && bytes == 1 && enabled == 1) s.owner = candidate;
        }
        s.proof[@"ownerSelection"] = @"existing_active_MonoBehaviour";
        if (status != EHR_RUNTIME_OK) return status;
    }
    if (!s.owner) {
        s.proof[@"existingActiveOwnerSearchEmpty"] = @YES;
        return EHR_RUNTIME_NOT_FOUND;
    }
    s.proof[@"existingOwnerFound"] = @YES;
    EHRRuntimeToken actualOwner = 0;
    if (ehr_runtime_object_class(s.owner, &actualOwner) == EHR_RUNTIME_OK) {
        char name[1024]{}; size_t required = 0;
        if (ehr_runtime_class_type_name(actualOwner, name, sizeof(name), &required) == EHR_RUNTIME_OK)
            s.proof[@"actualOwnerType"] = [NSString stringWithUTF8String:name];
    }
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_class("UnityEngine.CoreModule.dll", "UnityEngine", "Behaviour", &behaviour);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_method(behaviour, "get_isActiveAndEnabled", nullptr, 0, "System.Boolean", 0, &active);
    EHRRuntimeToken boxed = 0; uint8_t enabled = 0; size_t size = 0;
    if (status == EHR_RUNTIME_OK) status = call(active, s.owner, nullptr, 0, &boxed);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_copy_value(boxed, &enabled, sizeof(enabled), &size);
    if (status != EHR_RUNTIME_OK) return status;
    if (size != 1 || enabled != 1) { s.proof[@"ownerActiveAndEnabled"] = @NO; return EHR_RUNTIME_NOT_READY; }
    s.proof[@"ownerActiveAndEnabled"] = @YES;
    status = ehr_runtime_find_class("UnityEngine.CoreModule.dll", "UnityEngine", "MonoBehaviour", &mono);
    const char *startTypes[] = {"System.Collections.IEnumerator"};
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_method(mono, "StartCoroutine", startTypes, 1, "UnityEngine.Coroutine", 0, &s.start);
    const char *stopTypes[] = {"UnityEngine.Coroutine"};
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_method(mono, "StopCoroutine", stopTypes, 1, "System.Void", 0, &s.stop);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_class("mscorlib.dll", "System.Collections", "ArrayList", &s.listClass);
    if (status == EHR_RUNTIME_OK) status = ehr_runtime_find_method(s.listClass, "GetEnumerator", nullptr, 0, "System.Collections.IEnumerator", 0, &s.getEnumerator);
    return status;
}
}

NSDictionary<NSString *, id> *EHRManagedIteratorSchedulingCopyStatus(void) {
    if (!NSThread.isMainThread) return @{ @"complete": @YES, @"success": @NO, @"status": @(EHR_RUNTIME_WRONG_THREAD) };
    return session().proof ? [session().proof copy] : @{ @"complete": @NO, @"success": @NO, @"state": @"not_started" };
}
NSDictionary<NSString *, id> *EHRManagedIteratorSchedulingBegin(void) {
    if (!NSThread.isMainThread) return @{ @"complete": @YES, @"success": @NO, @"status": @(EHR_RUNTIME_WRONG_THREAD) };
    auto &s = session(); if (s.proof) return EHRManagedIteratorSchedulingCopyStatus();
    s.proof = [@{ @"complete": @NO, @"success": @NO, @"state": @"resolving_existing_owner", @"existingOwnerFound": @NO, @"existingOwnerSearchCompleted": @NO,
        @"manualMoveNextInvoked": @NO, @"customComponentCreated": @NO, @"singletonGetterInvoked": @NO,
        @"termsAccepted": @NO, @"gameplayMutationPerformed": @NO, @"fullEHRAvailable": @NO } mutableCopy];
    s.registrationsBefore = EHRManagedIteratorRegistrationCount(); s.currentBefore = EHRManagedIteratorCurrentRootCount();
    s.proof[@"registrationsBefore"] = @(s.registrationsBefore); s.proof[@"currentRootsBefore"] = @(s.currentBefore);
    EHRManagedIteratorHostV1 host{}; EHRManagedIteratorMakeTable(&host); EHRManagedIteratorCallbacksV1 callbacks{};
    const int32_t bound = ehr_iterator_bind_gateway(&host, sizeof(host), &callbacks, sizeof(callbacks));
    auto status = bound == 0 ? EHRManagedIteratorSetCallbacks(&callbacks) : static_cast<EHRRuntimeStatus>(bound);
    if (status == EHR_RUNTIME_OK) status = setupOwner();
    if (status != EHR_RUNTIME_OK) {
        NSString *state = [s.proof[@"existingActiveOwnerSearchEmpty"] boolValue] ? @"existing_owner_absent" : @"owner_or_required_runtime_api_unavailable";
        finish(state, false, status); return EHRManagedIteratorSchedulingCopyStatus();
    }
    status = launch(0.1f, &s.normalSource, &s.normalCoroutine);
    if (status != EHR_RUNTIME_OK) { finish(@"normal_source_start_failed", false, status); return EHRManagedIteratorSchedulingCopyStatus(); }
    s.phase = 1; s.running = true; s.deadline = CFAbsoluteTimeGetCurrent() + 15.0;
    s.proof[@"actualStartCoroutineReturnedHandle"] = @YES; s.proof[@"state"] = @"waiting_for_unity_frames";
    s.timer = [NSTimer scheduledTimerWithTimeInterval:0.025 repeats:YES block:^(__unused NSTimer *timer) { tick(); }];
    return EHRManagedIteratorSchedulingCopyStatus();
}
NSDictionary<NSString *, id> *EHRManagedIteratorSchedulingCancel(void) {
    if (!NSThread.isMainThread) return @{ @"complete": @YES, @"success": @NO, @"status": @(EHR_RUNTIME_WRONG_THREAD) };
    if (session().running || !session().roots.empty()) finish(@"explicitly_cancelled", false, EHR_RUNTIME_BAD_ARGUMENT);
    return EHRManagedIteratorSchedulingCopyStatus();
}
