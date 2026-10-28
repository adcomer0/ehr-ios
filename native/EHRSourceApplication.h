#ifndef EHR_SOURCE_APPLICATION_H
#define EHR_SOURCE_APPLICATION_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
enum { EHR_SOURCE_CORE=1,EHR_SOURCE_DELEGATES=2,EHR_SOURCE_COMPONENTS=4,
       EHR_SOURCE_TOUCH=8,EHR_SOURCE_COROUTINES=16,EHR_SOURCE_TARGETS=32,
       EHR_SOURCE_PREPARE=47,EHR_SOURCE_ALL=63 };
typedef struct { uint32_t version,size;int32_t(*require_ready)(uint32_t flags); } EHRSourceApplicationHostV1;
typedef struct {
    uint32_t version,size;
    const uint8_t *root;size_t root_length;
    const uint8_t *module;size_t module_length;
    const uint8_t *update_instructions;size_t update_instructions_length;
} EHRSourceApplicationConfigV1;
typedef struct {
    uint32_t version,size,state,status,source_types,role_types,callbacks,candidates,
        unavailable_targets,active_bindings,host_state,load_attempts,dynamic_code_flags,
        options_is_loaded_observed,option_count,options_post_load_completed;
} EHRSourceApplicationStatusV1;
int32_t ehr_source_application_bind_v1(const EHRSourceApplicationHostV1*,size_t);
int32_t ehr_source_application_prepare_v1(const EHRSourceApplicationConfigV1*,size_t);
int32_t ehr_source_application_load_v1(void);
int32_t ehr_source_application_status_v1(EHRSourceApplicationStatusV1*,size_t);
int32_t ehr_source_application_copy_error_v1(uint8_t*,size_t,size_t*);
#ifdef __cplusplus
}
static_assert(sizeof(EHRSourceApplicationHostV1)==16,"host");
static_assert(sizeof(EHRSourceApplicationConfigV1)==56,"config");
static_assert(sizeof(EHRSourceApplicationStatusV1)==64,"status");
#endif
#endif
