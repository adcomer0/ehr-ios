// Include in EHRNativeHooks.mm, where checkedImageBase() validates the UUID.
// The builder must supply all three exact private entry/trampoline constants.
#include "EHRStaticComponents.h"
#ifndef EHR_HAS_STATIC_CLASS_HOOKS
#define EHR_HAS_STATIC_CLASS_HOOKS 0
#endif
#if EHR_HAS_STATIC_CLASS_HOOKS
static_assert(EHRClassFromTypeMethodRVA == 0x19c1970);
static_assert(EHRClassFromNameMethodRVA == 0x19b7bf0);
static_assert(EHRClassFromDefinitionIndexMethodRVA == 0x19ad6a0);
extern "C" __attribute__((visibility("default")))
const void *ehr_native_class_from_type_hook(const void *type, bool throwOnError) {
    EHRStaticComponentsRecordHook(0);
    const void *resolved = nullptr;
    if (EHRStaticComponentsType(type, &resolved)) return resolved;
    using Original = const void *(*)(const void *, bool);
    const auto original = reinterpret_cast<Original>(checkedImageBase() + EHRClassFromTypeTrampolineRVA);
    return original(type, throwOnError);
}
extern "C" __attribute__((visibility("default")))
const void *ehr_native_class_from_name_hook(const void *image, const char *space, const char *name) {
    EHRStaticComponentsRecordHook(1);
    using Original = const void *(*)(const void *, const char *, const char *);
    const auto original = reinterpret_cast<Original>(checkedImageBase() + EHRClassFromNameTrampolineRVA);
    const void *result = original(image, space, name); // Original lookup has precedence.
    if (result) return result;
    return EHRStaticComponentsName(image, space, name, &result) ? result : nullptr;
}
extern "C" __attribute__((visibility("default")))
const void *ehr_native_class_from_definition_index_hook(int32_t index) {
    EHRStaticComponentsRecordHook(2);
    const void *resolved = nullptr;
    if (EHRStaticComponentsIndex(index, &resolved)) return resolved;
    using Original = const void *(*)(int32_t);
    const auto original = reinterpret_cast<Original>(checkedImageBase() + EHRClassFromDefinitionIndexTrampolineRVA);
    return original(index);
}
#endif
