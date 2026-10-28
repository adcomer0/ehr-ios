#pragma once
#include "EHRRuntimeGateway.h"
#ifdef __cplusplus
extern "C" {
#endif
// Generic arguments and returned classes are process-lifetime metadata tokens.
// MakeGenericType runs on real managed Type/Type[] objects. Invalid arity or
// constraints remain managed exceptions; unavailable AOT bodies are not made up.
EHRRuntimeStatus ehr_runtime_make_generic_class(EHRRuntimeToken open_class,
    const EHRRuntimeToken *argument_classes, size_t argument_count,
    EHRRuntimeToken *closed_class, EHRRuntimeToken *exception);
// Uses the real MethodInfo.MakeGenericMethod(Type[]) and exported reflection
// conversion. It never creates executable code. Missing AOT implementations
// and invalid generic arguments stay explicit caught managed exceptions.
EHRRuntimeStatus ehr_runtime_make_generic_method(EHRRuntimeToken open_method,
    const EHRRuntimeToken *argument_classes, size_t argument_count,
    EHRRuntimeToken *closed_method, EHRRuntimeToken *exception);
// Returns a boxed System.IntPtr from the runtime's MethodHandle.GetFunctionPointer
// path. Intended for native binder association checks; no MethodInfo offsets are
// read and no function pointer is called by this operation.
EHRRuntimeStatus ehr_runtime_method_function_pointer(EHRRuntimeToken method,
    EHRRuntimeToken *boxed_pointer, EHRRuntimeToken *exception);
// Constructor arguments are owned/borrowed object tokens (boxed values or null)
// copied into a real managed Object[]. A zero count permits a null arguments
// pointer. Activator.CreateInstance(Type,Object[]) chooses the public managed
// constructor and contains constructor/.cctor exceptions through the gateway.
// Every nonzero object/exception result is a new caller-owned strong root.
EHRRuntimeStatus ehr_runtime_construct(EHRRuntimeToken klass,
    const EHRRuntimeToken *arguments, size_t argument_count,
    EHRRuntimeToken *result, EHRRuntimeToken *exception);
#ifdef __cplusplus
}
#endif
