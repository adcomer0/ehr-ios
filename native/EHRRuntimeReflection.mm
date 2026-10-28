#include "EHRRuntimeReflection.h"
#include "EHRRuntimeCollections.h"

namespace {
constexpr size_t kMaxArguments = 128;
struct Owned {
    EHRRuntimeToken token = 0;
    Owned() = default;
    Owned(const Owned &) = delete;
    Owned &operator=(const Owned &) = delete;
    ~Owned() { if (token) ehr_runtime_object_release(token); }
};
EHRRuntimeStatus coreClass(const char *space, const char *name, EHRRuntimeToken *result) {
    return ehr_runtime_find_class("mscorlib.dll", space, name, result);
}
}

extern "C" EHRRuntimeStatus ehr_runtime_make_generic_class(EHRRuntimeToken openClass,
    const EHRRuntimeToken *arguments, size_t count,
    EHRRuntimeToken *result, EHRRuntimeToken *exception) {
    if (!result || !exception || result == exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = *exception = 0;
    if (count > kMaxArguments) return EHR_RUNTIME_LIMIT;
    if (count && !arguments) return EHR_RUNTIME_BAD_ARGUMENT;
    auto status = ehr_runtime_initialize();
    if (status != EHR_RUNTIME_OK) return status;
    Owned openType, typeArray, closedType;
    status = ehr_runtime_class_type_object(openClass, &openType.token);
    if (status != EHR_RUNTIME_OK) return status;
    EHRRuntimeToken typeClass = 0, makeGeneric = 0;
    status = coreClass("System", "Type", &typeClass);
    if (status != EHR_RUNTIME_OK) return status;
    status = ehr_runtime_array_create(typeClass, static_cast<int32_t>(count), &typeArray.token, exception);
    if (status != EHR_RUNTIME_OK) return status;
    for (size_t i = 0; i < count; ++i) {
        Owned argumentType;
        status = ehr_runtime_class_type_object(arguments[i], &argumentType.token);
        if (status != EHR_RUNTIME_OK) return status;
        status = ehr_runtime_array_set(typeArray.token, static_cast<int32_t>(i), argumentType.token, exception);
        if (status != EHR_RUNTIME_OK) return status;
    }
    const char *parameterTypes[] = {"System.Type[]"};
    status = ehr_runtime_find_method(typeClass, "MakeGenericType", parameterTypes, 1,
                                     "System.Type", 0, &makeGeneric);
    if (status != EHR_RUNTIME_OK) return status;
    const EHRRuntimeArgument argument{EHR_RUNTIME_REFERENCE, 0, typeArray.token, nullptr, 0};
    status = ehr_runtime_invoke(makeGeneric, openType.token, &argument, 1, &closedType.token, exception);
    if (status != EHR_RUNTIME_OK) return status;
    if (!closedType.token) return EHR_RUNTIME_TYPE_MISMATCH;
    return ehr_runtime_class_from_type_object(closedType.token, result);
}

extern "C" EHRRuntimeStatus ehr_runtime_make_generic_method(EHRRuntimeToken openMethod,
    const EHRRuntimeToken *arguments, size_t count,
    EHRRuntimeToken *result, EHRRuntimeToken *exception) {
    if (!result || !exception || result == exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = *exception = 0;
    if (count > kMaxArguments) return EHR_RUNTIME_LIMIT;
    if (count && !arguments) return EHR_RUNTIME_BAD_ARGUMENT;
    auto status = ehr_runtime_initialize();
    if (status != EHR_RUNTIME_OK) return status;
    Owned reflection, typeArray, closedReflection;
    status = ehr_runtime_method_object(openMethod, &reflection.token);
    if (status != EHR_RUNTIME_OK) return status;
    EHRRuntimeToken typeClass = 0, methodInfo = 0, makeGeneric = 0;
    status = coreClass("System", "Type", &typeClass);
    if (status != EHR_RUNTIME_OK) return status;
    status = ehr_runtime_array_create(typeClass, static_cast<int32_t>(count), &typeArray.token, exception);
    if (status != EHR_RUNTIME_OK) return status;
    for (size_t i = 0; i < count; ++i) {
        Owned argumentType;
        status = ehr_runtime_class_type_object(arguments[i], &argumentType.token);
        if (status != EHR_RUNTIME_OK) return status;
        status = ehr_runtime_array_set(typeArray.token, static_cast<int32_t>(i), argumentType.token, exception);
        if (status != EHR_RUNTIME_OK) return status;
    }
    status = coreClass("System.Reflection", "MethodInfo", &methodInfo);
    if (status != EHR_RUNTIME_OK) return status;
    const char *parameterTypes[] = {"System.Type[]"};
    status = ehr_runtime_find_method(methodInfo, "MakeGenericMethod", parameterTypes, 1,
                                     "System.Reflection.MethodInfo", 0, &makeGeneric);
    if (status != EHR_RUNTIME_OK) return status;
    const EHRRuntimeArgument argument{EHR_RUNTIME_REFERENCE, 0, typeArray.token, nullptr, 0};
    status = ehr_runtime_invoke(makeGeneric, reflection.token, &argument, 1, &closedReflection.token, exception);
    if (status != EHR_RUNTIME_OK) return status;
    return ehr_runtime_method_from_object(closedReflection.token, result);
}

extern "C" EHRRuntimeStatus ehr_runtime_method_function_pointer(EHRRuntimeToken method,
    EHRRuntimeToken *result, EHRRuntimeToken *exception) {
    if (!result || !exception || result == exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = *exception = 0;
    auto status = ehr_runtime_initialize();
    if (status != EHR_RUNTIME_OK) return status;
    Owned reflection, handle;
    status = ehr_runtime_method_object(method, &reflection.token);
    if (status != EHR_RUNTIME_OK) return status;
    EHRRuntimeToken methodBase = 0, handleClass = 0, getHandle = 0, getPointer = 0;
    status = coreClass("System.Reflection", "MethodBase", &methodBase);
    if (status != EHR_RUNTIME_OK) return status;
    status = ehr_runtime_find_method(methodBase, "get_MethodHandle", nullptr, 0,
                                     "System.RuntimeMethodHandle", 0, &getHandle);
    if (status != EHR_RUNTIME_OK) return status;
    status = ehr_runtime_invoke(getHandle, reflection.token, nullptr, 0, &handle.token, exception);
    if (status != EHR_RUNTIME_OK) return status;
    status = coreClass("System", "RuntimeMethodHandle", &handleClass);
    if (status != EHR_RUNTIME_OK) return status;
    status = ehr_runtime_find_method(handleClass, "GetFunctionPointer", nullptr, 0,
                                     "System.IntPtr", 0, &getPointer);
    if (status != EHR_RUNTIME_OK) return status;
    return ehr_runtime_invoke(getPointer, handle.token, nullptr, 0, result, exception);
}

extern "C" EHRRuntimeStatus ehr_runtime_construct(EHRRuntimeToken klass,
    const EHRRuntimeToken *arguments, size_t count,
    EHRRuntimeToken *result, EHRRuntimeToken *exception) {
    if (!result || !exception || result == exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = *exception = 0;
    if (count > kMaxArguments) return EHR_RUNTIME_LIMIT;
    if (count && !arguments) return EHR_RUNTIME_BAD_ARGUMENT;
    auto status = ehr_runtime_initialize();
    if (status != EHR_RUNTIME_OK) return status;
    Owned type, argumentArray;
    status = ehr_runtime_class_type_object(klass, &type.token);
    if (status != EHR_RUNTIME_OK) return status;
    EHRRuntimeToken objectClass = 0, activator = 0, createInstance = 0;
    status = coreClass("System", "Object", &objectClass);
    if (status != EHR_RUNTIME_OK) return status;
    status = ehr_runtime_array_create(objectClass, static_cast<int32_t>(count), &argumentArray.token, exception);
    if (status != EHR_RUNTIME_OK) return status;
    for (size_t i = 0; i < count; ++i) {
        status = ehr_runtime_array_set(argumentArray.token, static_cast<int32_t>(i), arguments[i], exception);
        if (status != EHR_RUNTIME_OK) return status;
    }
    status = coreClass("System", "Activator", &activator);
    if (status != EHR_RUNTIME_OK) return status;
    const char *parameterTypes[] = {"System.Type", "System.Object[]"};
    status = ehr_runtime_find_method(activator, "CreateInstance", parameterTypes, 2,
                                     "System.Object", 1, &createInstance);
    if (status != EHR_RUNTIME_OK) return status;
    const EHRRuntimeArgument invokeArguments[] = {
        {EHR_RUNTIME_REFERENCE, 0, type.token, nullptr, 0},
        {EHR_RUNTIME_REFERENCE, 0, argumentArray.token, nullptr, 0}
    };
    return ehr_runtime_invoke(createInstance, 0, invokeArguments, 2, result, exception);
}
