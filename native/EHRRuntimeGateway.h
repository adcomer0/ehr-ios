#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ABI 1: tokens are owned by this gateway, never IL2CPP pointers. Metadata
// tokens live for the process lifetime. Every nonzero returned object token is
// a NEW strong GC root and must be released exactly once by its caller.
// All calls, including release, require the Unity main thread. No dispatch_sync
// is hidden in this API: facade callers must explicitly schedule game work.
typedef uint64_t EHRRuntimeToken;
typedef enum EHRRuntimeStatus {
    EHR_RUNTIME_OK = 0,
    EHR_RUNTIME_NOT_READY = 1,
    EHR_RUNTIME_WRONG_THREAD = 2,
    EHR_RUNTIME_NOT_FOUND = 3,
    EHR_RUNTIME_BAD_ARGUMENT = 4,
    EHR_RUNTIME_TYPE_MISMATCH = 5,
    EHR_RUNTIME_MANAGED_EXCEPTION = 6,
    EHR_RUNTIME_UNSUPPORTED = 7,
    EHR_RUNTIME_LIMIT = 8,
    EHR_RUNTIME_INVALID_TOKEN = 9,
    EHR_RUNTIME_AMBIGUOUS = 10
} EHRRuntimeStatus;

typedef enum EHRRuntimeArgumentKind {
    EHR_RUNTIME_REFERENCE = 1, // object token, with 0 representing managed null
    EHR_RUNTIME_VALUE = 2,     // exact value-class token and copied payload bytes
    EHR_RUNTIME_BOXED_VALUE = 3 // exact-class rooted boxed object; no raw bytes
} EHRRuntimeArgumentKind;

typedef struct EHRRuntimeArgument {
    uint32_t kind;
    uint32_t reserved; // must be zero
    EHRRuntimeToken token; // object token for reference/boxed, class for raw value
    const void *bytes;
    size_t byte_count;
} EHRRuntimeArgument;

// Explicit copy-in/copy-out for a value-type ref/out parameter. The immutable
// argument at argument_index supplies the initial value, including for out.
// bytes is writable storage, with byte_count EXACTLY the runtime value size.
// Output ranges must not overlap each other or the result/exception tokens.
// Managed execution copies back all supported ref/out values, even if it raises
// a managed exception. Preflight errors leave the output buffers unchanged.
typedef struct EHRRuntimeByRefOutput {
    uint32_t argument_index;
    uint32_t reserved; // must be zero
    EHRRuntimeToken value_class;
    void *bytes;
    size_t byte_count;
} EHRRuntimeByRefOutput;

uint32_t ehr_runtime_abi_version(void);
EHRRuntimeStatus ehr_runtime_initialize(void);
// name is an exact top-level metadata name or Outer+Inner[+Deeper] chain;
// name_space belongs to the outer class. Nested components are traversed via
// public runtime enumeration, never passed as guessed class_from_name syntax.
// Empty components, '/' aliases and excessive nesting are rejected.
EHRRuntimeStatus ehr_runtime_find_class(const char *image, const char *name_space,
                                      const char *name, EHRRuntimeToken *result);
EHRRuntimeStatus ehr_runtime_object_class(EHRRuntimeToken object, EHRRuntimeToken *result);
// Returns the real managed System.Type object for a metadata class token.
EHRRuntimeStatus ehr_runtime_class_type_object(EHRRuntimeToken klass, EHRRuntimeToken *result);
// Converts a real runtime System.Type object into a process-lifetime metadata
// class token. Arbitrary System.Type subclasses are rejected before conversion.
EHRRuntimeStatus ehr_runtime_class_from_type_object(EHRRuntimeToken type_object,
                                                   EHRRuntimeToken *result);
// Copies the runtime's exact UTF-8 type spelling, including generic/nested/
// array markers. required includes the trailing NUL. A null buffer with zero
// capacity queries the size and returns LIMIT. Insufficient capacity returns
// LIMIT with an empty buffer, never a partially copied UTF-8 sequence. The
// buffer and required must not overlap; no managed object or root is created.
EHRRuntimeStatus ehr_runtime_class_type_name(EHRRuntimeToken klass, char *utf8,
                                           size_t capacity, size_t *required);
// Exact runtime metadata class for a zero-based, one-dimensional T[] vector.
// Does not allocate an array or run its constructors. Open generic, void,
// byref/pointer and missing AOT metadata shapes remain explicitly unsupported.
EHRRuntimeStatus ehr_runtime_vector_class(EHRRuntimeToken element_class,
                                         EHRRuntimeToken *vector_class);
EHRRuntimeStatus ehr_runtime_field_type_name(EHRRuntimeToken field, char *utf8,
                                           size_t capacity, size_t *required);
// Runs the managed initializer through System.Type.TypeHandle and the caught
// RuntimeHelpers.RunClassConstructor invocation. Successful classes may then
// use static field APIs; failures return a caller-owned rooted exception.
EHRRuntimeStatus ehr_runtime_initialize_class(EHRRuntimeToken klass,
                                            EHRRuntimeToken *exception);
// Exact IL2CPP type names (including namespace/array/byref markers) are required.
// No name/arity fallback or implicit overload conversion occurs.
EHRRuntimeStatus ehr_runtime_find_method(EHRRuntimeToken klass, const char *name,
    const char *const *parameter_types, size_t parameter_count, const char *return_type,
    int is_static, EHRRuntimeToken *result);
EHRRuntimeStatus ehr_runtime_find_field(EHRRuntimeToken klass, const char *name,
    const char *field_type, int is_static, EHRRuntimeToken *result);
// Real runtime reflection MethodInfo objects, with the usual owned-root rule.
// Constructors and arbitrary MethodInfo subclasses are not accepted. Conversion
// back validates the exact reflection class produced by this runtime.
EHRRuntimeStatus ehr_runtime_method_object(EHRRuntimeToken method, EHRRuntimeToken *result);
EHRRuntimeStatus ehr_runtime_method_from_object(EHRRuntimeToken reflection_method, EHRRuntimeToken *result);
// Version-pinned native association only. Validates the gateway-owned Method
// through exported metadata facts, exact signed framework SHA/UUID provenance,
// and executable file-backed bounds before comparing its copied entry RVA.
// No function pointer or MethodInfo pointer crosses this ABI. On a valid entry
// with a different expected RVA, TYPE_MISMATCH includes the observed RVA.
EHRRuntimeStatus ehr_runtime_validate_native_method(EHRRuntimeToken method,
    uint64_t expected_rva, uint64_t *observed_rva);
// Result is a rooted reference/boxed value, or 0 for void/null. A managed
// exception is returned as its own rooted object token, not thrown across C ABI.
// Ordinary invoke rejects byref/pointer parameters and open generic methods.
// Boxed value receivers are pinned per call; value-declared instance methods
// receive the runtime's unboxed payload and can mutate that boxed value.
EHRRuntimeStatus ehr_runtime_invoke(EHRRuntimeToken method, EHRRuntimeToken instance,
    const EHRRuntimeArgument *arguments, size_t argument_count,
    EHRRuntimeToken *result, EHRRuntimeToken *exception);
// A descriptor is required for every byref parameter and forbidden for ordinary
// parameters. Only primitive values and supported reference-free/blittable
// structs are accepted. Byref managed references remain UNSUPPORTED. This API
// preserves the root ownership and exception contracts of ehr_runtime_invoke.
EHRRuntimeStatus ehr_runtime_invoke_with_refs(EHRRuntimeToken method,
    EHRRuntimeToken instance, const EHRRuntimeArgument *arguments,
    size_t argument_count, const EHRRuntimeByRefOutput *outputs,
    size_t output_count, EHRRuntimeToken *result, EHRRuntimeToken *exception);
EHRRuntimeStatus ehr_runtime_read_field(EHRRuntimeToken field, EHRRuntimeToken instance,
                                      EHRRuntimeToken *result);
// A declaring managed .cctor must first succeed via initialize_class; exported
// field helpers can otherwise execute it without an exception-out parameter.
EHRRuntimeStatus ehr_runtime_write_field(EHRRuntimeToken field, EHRRuntimeToken instance,
                                       const EHRRuntimeArgument *value);
// Only blittable value types and runtime-sized Boolean/Char scalars containing
// no managed references can cross as raw bytes.
// These APIs report the exact required size; no object/header offsets are used.
EHRRuntimeStatus ehr_runtime_value_size(EHRRuntimeToken klass, size_t *byte_count);
EHRRuntimeStatus ehr_runtime_box(EHRRuntimeToken klass, const void *bytes, size_t byte_count,
                               EHRRuntimeToken *result);
EHRRuntimeStatus ehr_runtime_copy_value(EHRRuntimeToken object, void *bytes, size_t capacity,
                                      size_t *byte_count);
EHRRuntimeStatus ehr_runtime_string_create(const uint16_t *units, size_t length,
                                         EHRRuntimeToken *result);
// Length excludes a terminator. UTF-16 is copied exactly, including embedded NUL.
EHRRuntimeStatus ehr_runtime_string_copy(EHRRuntimeToken object, uint16_t *units,
                                       size_t capacity, size_t *length);
EHRRuntimeStatus ehr_runtime_object_release(EHRRuntimeToken object);
EHRRuntimeStatus ehr_runtime_object_retain(EHRRuntimeToken object, EHRRuntimeToken *result);
// Read-only diagnostic count of owned object-token entries, including weak
// identity handles. Main thread only; does not collect, release, or drain them.
EHRRuntimeStatus ehr_runtime_object_root_count(size_t *count);
// Managed reference identity, independent of overridden Equals/GetHashCode.
// Identity hashes can collide; pair them with object_same when used as keys.
EHRRuntimeStatus ehr_runtime_object_same(EHRRuntimeToken left, EHRRuntimeToken right,
                                       int32_t *same);
EHRRuntimeStatus ehr_runtime_object_identity_hash(EHRRuntimeToken object, int32_t *hash,
                                                EHRRuntimeToken *exception);
// Exception to the main-thread rule: this function may run on a finalizer
// thread. OK acknowledges enqueue only, without validating the token there.
// The bounded main-queue drain validates ownership and frees handles once.
// Null is a no-op. Queue exhaustion returns LIMIT without releasing ownership.
EHRRuntimeStatus ehr_runtime_object_release_deferred(EHRRuntimeToken object);
// Main-thread explicit drain; normal deferred releases also schedule a drain.
// The count reports actual roots freed, excluding stale/duplicate requests.
EHRRuntimeStatus ehr_runtime_drain_deferred_releases(size_t *released);

#ifdef __cplusplus
}
#endif
