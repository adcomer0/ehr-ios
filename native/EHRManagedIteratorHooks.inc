// Append once to EHRNativeHooks.mm, sharing its UUID-checked image base. The
// builder must emit exact pinned trampolines for these three instance methods.
#include "EHRManagedIteratorAdapter.h"
#if defined(EHR_HAS_ITERATOR_HOOKS) && EHR_HAS_ITERATOR_HOOKS
extern "C" __attribute__((visibility("default")))
bool ehr_native_iterator_move_next_hook(void *instance, const void *methodInfo) {
    bool result = false;
    if (EHRManagedIteratorMoveNext(instance, &result)) return result;
    using Original = bool (*)(void *, const void *);
    return reinterpret_cast<Original>(checkedImageBase() + EHRIteratorMoveTrampolineRVA)(instance, methodInfo);
}
extern "C" __attribute__((visibility("default")))
void *ehr_native_iterator_current_hook(void *instance, const void *methodInfo) {
    void *result = nullptr;
    if (EHRManagedIteratorCurrent(instance, &result)) return result;
    using Original = void *(*)(void *, const void *);
    return reinterpret_cast<Original>(checkedImageBase() + EHRIteratorCurrentTrampolineRVA)(instance, methodInfo);
}
extern "C" __attribute__((visibility("default")))
void ehr_native_iterator_reset_hook(void *instance, const void *methodInfo) {
    if (EHRManagedIteratorReset(instance)) return;
    using Original = void (*)(void *, const void *);
    reinterpret_cast<Original>(checkedImageBase() + EHRIteratorResetTrampolineRVA)(instance, methodInfo);
}
#endif
