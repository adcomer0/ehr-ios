#ifndef EHR_NATIVE_SIGNED_UPDATES_H
#define EHR_NATIVE_SIGNED_UPDATES_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Once, main-thread only, after source-host binding and before Main.Load.
// nullptr/0 explicitly configures NO update instructions. A configured URL is
// host-reviewed HTTPS instructions for a rebuilt signed iOS application; this
// API does not claim to verify a remote app signature. Nothing opens until the
// user presses the update action. No DLL download, file mutation or installation.
int32_t ehr_source_updates_configure(const uint8_t *https_url,size_t length);
#ifdef __cplusplus
}
#endif
#endif
