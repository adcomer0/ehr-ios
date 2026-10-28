// Original macOS handler fixture: never changes executable memory.
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "fixture_pins.h"

typedef void (*Murder)(void *, void *, uint32_t, void *);
typedef int32_t (*Version)(void *);
typedef uintptr_t (*Address)(void *);
static unsigned murder_calls;
static unsigned version_calls;
static unsigned adrp_calls, adr_calls, stp_calls;
static uintptr_t loaded_base;

static intptr_t fixture_slide(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const struct mach_header_64 *h = (const void *)_dyld_get_image_header(i);
        if (!h || h->magic != MH_MAGIC_64) continue;
        const uint8_t *cursor = (const uint8_t *)(h + 1);
        for (uint32_t n = 0; n < h->ncmds; ++n) {
            const struct load_command *lc = (const void *)cursor;
            if (lc->cmd == LC_UUID && lc->cmdsize == sizeof(struct uuid_command)) {
                const struct uuid_command *u = (const void *)cursor;
                if (!memcmp(u->uuid, fixture_uuid, sizeof(fixture_uuid))) {
                    loaded_base = (uintptr_t)h;
                    return _dyld_get_image_vmaddr_slide(i);
                }
            }
            cursor += lc->cmdsize;
        }
    }
    abort();
}

void ehr_native_murder_hook(void *self, void *target, uint32_t flags, void *context) {
    Murder original = (Murder)(fixture_slide() + FIXTURE_MURDER_TRAMPOLINE);
    original(self, target, flags, context);
    ++murder_calls;
    *(uint32_t *)self += 100;
}

int32_t ehr_native_broadcast_version_hook(void *context) {
    Version original = (Version)(fixture_slide() + FIXTURE_VERSION_TRAMPOLINE);
    int32_t result = original(context);
    ++version_calls;
    return result + 25;
}

uintptr_t ehr_fixture_adrp_hook(void *context) {
    Address original = (Address)(fixture_slide() + FIXTURE_ADRP_TRAMPOLINE);
    uintptr_t result = original(context);
    ++adrp_calls;
    return result;
}

uintptr_t ehr_fixture_adr_hook(void *context) {
    Address original = (Address)(fixture_slide() + FIXTURE_ADR_TRAMPOLINE);
    uintptr_t result = original(context);
    ++adr_calls;
    return result;
}

int32_t ehr_fixture_stp_hook(void *context) {
    Version original = (Version)(fixture_slide() + FIXTURE_STP_TRAMPOLINE);
    int32_t result = original(context);
    ++stp_calls;
    return result + 7;
}

unsigned fixture_murder_call_count(void) { return murder_calls; }
unsigned fixture_version_call_count(void) { return version_calls; }
uintptr_t fixture_loaded_base(void) { return loaded_base; }
unsigned fixture_adrp_call_count(void) { return adrp_calls; }
unsigned fixture_adr_call_count(void) { return adr_calls; }
unsigned fixture_stp_call_count(void) { return stp_calls; }

typedef double (*DoublePair)(double, double, void *);
typedef uint32_t (*Load32)(const void *);
typedef uint64_t (*Load64)(const void *);
static unsigned stpd_calls, ldrb_calls, ldrw_calls, ldrx_calls, ldpw_calls;

double ehr_fixture_stpd_hook(double left, double right, void *context) {
    DoublePair original = (DoublePair)(fixture_slide() + FIXTURE_STPD_TRAMPOLINE);
    double value = original(left, right, context);
    ++stpd_calls;
    return value + 0.5;
}
uint32_t ehr_fixture_ldrb_hook(const void *memory) {
    Load32 original = (Load32)(fixture_slide() + FIXTURE_LDRB_TRAMPOLINE);
    uint32_t value = original(memory);
    ++ldrb_calls;
    return value + 7;
}
uint32_t ehr_fixture_ldrw_hook(const void *memory) {
    Load32 original = (Load32)(fixture_slide() + FIXTURE_LDRW_TRAMPOLINE);
    uint32_t value = original(memory);
    ++ldrw_calls;
    return value ^ 0x51515151U;
}
uint64_t ehr_fixture_ldrx_hook(const void *memory) {
    Load64 original = (Load64)(fixture_slide() + FIXTURE_LDRX_TRAMPOLINE);
    uint64_t value = original(memory);
    ++ldrx_calls;
    return value ^ 0x5151515151515151ULL;
}
uint32_t ehr_fixture_ldpw_hook(const void *memory) {
    Load32 original = (Load32)(fixture_slide() + FIXTURE_LDPW_TRAMPOLINE);
    uint32_t value = original(memory);
    ++ldpw_calls;
    return value + 11;
}
unsigned fixture_stpd_call_count(void) { return stpd_calls; }
unsigned fixture_ldrb_call_count(void) { return ldrb_calls; }
unsigned fixture_ldrw_call_count(void) { return ldrw_calls; }
unsigned fixture_ldrx_call_count(void) { return ldrx_calls; }
unsigned fixture_ldpw_call_count(void) { return ldpw_calls; }
