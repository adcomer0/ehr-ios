#ifndef EHR_SOURCE_HOST_RUNTIME_H
#define EHR_SOURCE_HOST_RUNTIME_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct EHRSourceHostV1 {
    uint32_t version, size;
    int32_t (*is_main_thread)(void);
    // UTF-8 may contain embedded NUL; consume the exact supplied length.
    void (*log)(int32_t level, const uint8_t *utf8, size_t length);
} EHRSourceHostV1;
int32_t ehr_source_host_bind_v1(const EHRSourceHostV1 *host, size_t bytes);
// Both paths must be absolute; module must name the actual existing native image.
// The native host owns the sandbox data root and passes it before source static
// initialization. Never pass a bundle resource directory as writable data root.
// Proof[16]: pass,status,stage,configTypes,loadCount,finishedCount,logEvents,
// pluginInfo,selfOnly,failedNoRetry,reentrancy,workerRejected,componentBlocked,
// dynamicFlags,unloadFalse,realCorePaths. Nonzero dynamicFlags means failure.
int32_t ehr_source_host_self_test(const uint8_t *root,size_t root_length,
    const uint8_t *module,size_t module_length,int32_t *proof,size_t proof_count);
#ifdef __cplusplus
}
static_assert(sizeof(EHRSourceHostV1)==24,"SourceHostV1 layout");
#endif
#endif
