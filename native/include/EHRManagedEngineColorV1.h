#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct EHRManagedEngineColorV1 {
    uint32_t abi_version,byte_size;
    int32_t (*parse_html)(uint64_t,int32_t *,uint32_t *);
} EHRManagedEngineColorV1;
int32_t ehr_generated_bind_engine_colors(const EHRManagedEngineColorV1 *,size_t);
/* pass,status,named,hex,invalid,null */
int32_t ehr_generated_engine_color_self_test(int32_t *,size_t);
int32_t ehr_generated_engine_color_implementation(void);
#ifdef __cplusplus
}
#endif
