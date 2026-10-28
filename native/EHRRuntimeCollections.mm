#include "EHRRuntimeCollections.h"

namespace {
struct Owned {
    EHRRuntimeToken token = 0;
    ~Owned() { if (token) ehr_runtime_object_release(token); }
};
struct ArrayAPI {
    EHRRuntimeToken arrayClass = 0;
    EHRRuntimeToken intClass = 0;
    EHRRuntimeStatus resolve() {
        auto status = ehr_runtime_initialize();
        if (status != EHR_RUNTIME_OK) return status;
        status = ehr_runtime_find_class("mscorlib.dll", "System", "Array", &arrayClass);
        if (status != EHR_RUNTIME_OK) return status;
        return ehr_runtime_find_class("mscorlib.dll", "System", "Int32", &intClass);
    }
    EHRRuntimeStatus method(const char *name, const char *const *parameters,
                            size_t count, const char *returns, bool isStatic,
                            EHRRuntimeToken *result) const {
        return ehr_runtime_find_method(arrayClass, name, parameters, count, returns, isStatic ? 1 : 0, result);
    }
    EHRRuntimeArgument integer(const int32_t *value) const {
        return {EHR_RUNTIME_VALUE, 0, intClass, value, sizeof(*value)};
    }
};
constexpr int32_t kMaxElements = 65536;
}

extern "C" EHRRuntimeStatus ehr_runtime_array_create(EHRRuntimeToken elementClass, int32_t length,
    EHRRuntimeToken *result, EHRRuntimeToken *exception) {
    if (!result || !exception || result == exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = *exception = 0;
    if (length < 0 || length > kMaxElements) return EHR_RUNTIME_LIMIT;
    ArrayAPI api;
    auto status = api.resolve();
    if (status != EHR_RUNTIME_OK) return status;
    Owned type;
    status = ehr_runtime_class_type_object(elementClass, &type.token);
    if (status != EHR_RUNTIME_OK) return status;
    const char *parameters[] = {"System.Type", "System.Int32"};
    EHRRuntimeToken method = 0;
    status = api.method("CreateInstance", parameters, 2, "System.Array", true, &method);
    if (status != EHR_RUNTIME_OK) return status;
    const EHRRuntimeArgument args[] = {{EHR_RUNTIME_REFERENCE, 0, type.token, nullptr, 0}, api.integer(&length)};
    return ehr_runtime_invoke(method, 0, args, 2, result, exception);
}

extern "C" EHRRuntimeStatus ehr_runtime_array_length(EHRRuntimeToken array, int32_t *length,
    EHRRuntimeToken *exception) {
    if (!length || !exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *length = 0; *exception = 0;
    ArrayAPI api;
    auto status = api.resolve();
    if (status != EHR_RUNTIME_OK) return status;
    EHRRuntimeToken method = 0;
    status = api.method("get_Length", nullptr, 0, "System.Int32", false, &method);
    if (status != EHR_RUNTIME_OK) return status;
    Owned boxed;
    status = ehr_runtime_invoke(method, array, nullptr, 0, &boxed.token, exception);
    if (status != EHR_RUNTIME_OK) return status;
    size_t bytes = 0;
    status = ehr_runtime_copy_value(boxed.token, length, sizeof(*length), &bytes);
    if (status != EHR_RUNTIME_OK) return status;
    return bytes == sizeof(*length) && *length >= 0 ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH;
}

extern "C" EHRRuntimeStatus ehr_runtime_array_get(EHRRuntimeToken array, int32_t index,
    EHRRuntimeToken *result, EHRRuntimeToken *exception) {
    if (!result || !exception || result == exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *result = *exception = 0;
    int32_t length = 0;
    auto status = ehr_runtime_array_length(array, &length, exception);
    if (status != EHR_RUNTIME_OK) return status;
    if (index < 0 || index >= length) return EHR_RUNTIME_BAD_ARGUMENT;
    ArrayAPI api;
    status = api.resolve();
    if (status != EHR_RUNTIME_OK) return status;
    const char *parameters[] = {"System.Int32"};
    EHRRuntimeToken method = 0;
    status = api.method("GetValue", parameters, 1, "System.Object", false, &method);
    if (status != EHR_RUNTIME_OK) return status;
    const auto arg = api.integer(&index);
    return ehr_runtime_invoke(method, array, &arg, 1, result, exception);
}

extern "C" EHRRuntimeStatus ehr_runtime_array_set(EHRRuntimeToken array, int32_t index,
    EHRRuntimeToken value, EHRRuntimeToken *exception) {
    if (!exception) return EHR_RUNTIME_BAD_ARGUMENT;
    *exception = 0;
    int32_t length = 0;
    auto status = ehr_runtime_array_length(array, &length, exception);
    if (status != EHR_RUNTIME_OK) return status;
    if (index < 0 || index >= length) return EHR_RUNTIME_BAD_ARGUMENT;
    ArrayAPI api;
    status = api.resolve();
    if (status != EHR_RUNTIME_OK) return status;
    const char *parameters[] = {"System.Object", "System.Int32"};
    EHRRuntimeToken method = 0;
    status = api.method("SetValue", parameters, 2, "System.Void", false, &method);
    if (status != EHR_RUNTIME_OK) return status;
    const EHRRuntimeArgument args[] = {{EHR_RUNTIME_REFERENCE, 0, value, nullptr, 0}, api.integer(&index)};
    Owned returned;
    return ehr_runtime_invoke(method, array, args, 2, &returned.token, exception);
}
