#pragma once
#include <stddef.h>
#include <stdint.h>
#include "EHRManagedBridgeV1.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct EHRManagedByRefOutputV1 {
    uint32_t argument_index;
    uint32_t reserved;
    uint64_t value_class;
    void *bytes;
    size_t byte_count;
} EHRManagedByRefOutputV1;
typedef struct EHRManagedFacadeExtensionsV1 {
    uint32_t abi_version;
    uint32_t byte_size;
    int32_t (*invoke_with_refs)(uint64_t, uint64_t, const EHRManagedArgumentV1 *, size_t,
        const EHRManagedByRefOutputV1 *, size_t, uint64_t *, uint64_t *);
    int32_t (*class_type_object)(uint64_t, uint64_t *);
    int32_t (*array_create)(uint64_t, int32_t, uint64_t *, uint64_t *);
    int32_t (*array_length)(uint64_t, int32_t *, uint64_t *);
    int32_t (*array_get)(uint64_t, int32_t, uint64_t *, uint64_t *);
    int32_t (*array_set)(uint64_t, int32_t, uint64_t, uint64_t *);
} EHRManagedFacadeExtensionsV1;
int32_t ehr_generated_bind_gateway(const EHRManagedGatewayV1 *, size_t);
int32_t ehr_generated_bind_extensions(const EHRManagedFacadeExtensionsV1 *, size_t);
uint32_t ehr_generated_binding_count(void);
int32_t ehr_generated_validate_binding(uint32_t);
int32_t ehr_generated_get_broadcast_version(int32_t *);
// Four Int32 outputs: pass, status, byte-array roundtrip, UTF16/null roundtrip.
int32_t ehr_generated_array_self_test(int32_t *, size_t);
// Four Int32 outputs: pass,status,int/float/byte/bool roundtrips,out-call count.
// Creates an owned NormalGameOptionsV12 object; never changes active settings.
int32_t ehr_generated_settings_self_test(int32_t *, size_t);
// Six Int32 outputs: pass,status,field-copy isolation,instance-call-copy
// isolation,default/native value equality+hash,native Distance. Own boxed values.
int32_t ehr_generated_value_self_test(int32_t *, size_t);
// Six Int32 outputs: pass,status,native-current/native-reset,validated-casts,
// retained actual game exception root. No managed-source coroutine carrier.
int32_t ehr_generated_object_self_test(int32_t *, size_t);
// Five Int32 outputs each: pass,status,three individual assertions.
// Dictionary mutates an independent real native Dictionary<string,int>.
// Predicate algorithms use managed-source callbacks over real native lists.
int32_t ehr_generated_dictionary_self_test(int32_t *, size_t);
int32_t ehr_generated_predicate_self_test(int32_t *, size_t);
#ifdef __cplusplus
}
#endif
