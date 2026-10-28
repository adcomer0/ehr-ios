// Original native command-line integration test. It runs no game code.
#include <dlfcn.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct Context { uintptr_t self; uintptr_t target; uint32_t flags; };
typedef void (*Murder)(void *, void *, uint32_t, void *);
typedef int32_t (*Version)(void *);
typedef unsigned (*Count)(void);
typedef uintptr_t (*Base)(void);
typedef size_t (*Length)(const char *);
typedef uintptr_t (*Address)(void *);
typedef uint32_t (*Load32)(const void *);
typedef uint64_t (*Load64)(const void *);
typedef int (*Check)(void);

static void *required(void *handle, const char *name) {
    void *result = dlsym(handle, name);
    if (!result) { fprintf(stderr, "dlsym %s: %s\n", name, dlerror()); exit(2); }
    return result;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    void *image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!image) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
    Murder murder = (Murder)required(image, "fixture_murder");
    Version version = (Version)required(image, "fixture_version");
    Count murders = (Count)required(image, "fixture_murder_call_count");
    Count versions = (Count)required(image, "fixture_version_call_count");
    Base base = (Base)required(image, "fixture_loaded_base");
    Murder *rebased_pointer = required(image, "fixture_original_pointer");
    Length *bound_pointer = required(image, "fixture_library_pointer");
    Length lazy_bound = (Length)required(image, "fixture_unhooked");
    uint32_t self = 0, target = 0;
    struct Context context = {0};
    murder(&self, &target, 19, &context);
    int32_t result = version(&context);
    int direct_ok = self == 119 && target == 20 && context.self == (uintptr_t)&self
        && context.target == (uintptr_t)&target && context.flags == 19
        && result == 32 && murders() == 1 && versions() == 1 && base() != 0;
    (*rebased_pointer)(&self, &target, 29, &context);
    int rebase_ok = self == 129 && target == 30 && context.self == (uintptr_t)&self
        && context.target == (uintptr_t)&target && context.flags == 29 && murders() == 2;
    int bind_ok = (*bound_pointer)("callback") == 8;
    int lazy_ok = lazy_bound("classic dyld") == 12;
    Address adrp = (Address)required(image, "fixture_adrp");
    Address adr = (Address)required(image, "fixture_adr");
    Version stp = (Version)required(image, "fixture_stp");
    Count adrps = (Count)required(image, "fixture_adrp_call_count");
    Count adrs = (Count)required(image, "fixture_adr_call_count");
    Count stps = (Count)required(image, "fixture_stp_call_count");
    uint32_t *constant = required(image, "fixture_pc_constant");
    uintptr_t adrp_result = adrp(&context), adr_result = adr(&context);
    int32_t stp_result = stp(&context);
    int adrp_ok = adrp_result == (uintptr_t)constant && *constant == 0x13579bdf && adrps() == 1;
    int adr_ok = adr_result == (uintptr_t)constant && *constant == 0x13579bdf && adrs() == 1;
    int stp_ok = stp_result == 0x1234 + 7 && stps() == 1;
    Check stpd_check = (Check)required(image, "fixture_check_stpd_preserves");
    Load32 ldrb = (Load32)required(image, "fixture_ldrb");
    Load32 ldrw = (Load32)required(image, "fixture_ldrw");
    Load64 ldrx = (Load64)required(image, "fixture_ldrx");
    Load32 ldpw = (Load32)required(image, "fixture_ldpw");
    Count stpds = (Count)required(image, "fixture_stpd_call_count");
    Count ldrbs = (Count)required(image, "fixture_ldrb_call_count");
    Count ldrws = (Count)required(image, "fixture_ldrw_call_count");
    Count ldrxs = (Count)required(image, "fixture_ldrx_call_count");
    Count ldpws = (Count)required(image, "fixture_ldpw_call_count");
    uint64_t load_memory[6] = {0};
    unsigned char *memory = (unsigned char *)load_memory;
    memory[3] = 0xed;
    uint32_t word = 0xf1234567U;
    uint64_t wide = 0xfedcba9876543210ULL;
    memcpy(memory + 12, &word, sizeof(word));
    memcpy(memory + 24, &wide, sizeof(wide));
    uint32_t pair[4] = {0x80000000U, 0x12345678U, 3, 4};
    int stpd_ok = stpd_check() == 1 && stpds() == 1;
    int ldrb_ok = ldrb(memory) == 0xed + 7 && ldrbs() == 1;
    int ldrw_ok = ldrw(memory) == (word ^ 0x51515151U) && ldrws() == 1;
    int ldrx_ok = ldrx(memory) == (wide ^ 0x5151515151515151ULL) && ldrxs() == 1;
    int ldpw_ok = ldpw(pair + 2) == 0x92345683U && ldpws() == 1;
    int ok = direct_ok && rebase_ok && bind_ok && lazy_ok && adrp_ok && adr_ok && stp_ok
        && stpd_ok && ldrb_ok && ldrw_ok && ldrx_ok && ldpw_ok;
    printf("{\"pass\":%s,\"self_after_original_and_hook\":%u,\"target_after_original\":%u,"
           "\"flags_preserved\":%s,\"context_preserved\":%s,\"version_after_original_and_hook\":%d,"
           "\"original_rebase_executed\":%s,\"original_normal_bind_executed\":%s,\"original_lazy_bind_executed\":%s,"
           "\"murder_callbacks\":%u,\"version_callbacks\":%u,"
           "\"adrp_target_preserved\":%s,\"adr_target_preserved\":%s,\"stp_prologue_preserved\":%s,"
           "\"stpd_callee_saved_lanes_and_return_preserved\":%s,\"ldrb_preserved\":%s,"
           "\"ldrw_preserved\":%s,\"ldrx_preserved\":%s,\"ldpw_preserved\":%s,"
           "\"loaded_base\":\"0x%" PRIxPTR "\"}\n",
           ok ? "true" : "false", self, target, context.flags == 29 ? "true" : "false",
           context.self == (uintptr_t)&self && context.target == (uintptr_t)&target ? "true" : "false",
           result, rebase_ok ? "true" : "false", bind_ok ? "true" : "false", lazy_ok ? "true" : "false",
           murders(), versions(), adrp_ok ? "true" : "false", adr_ok ? "true" : "false", stp_ok ? "true" : "false",
           stpd_ok ? "true" : "false", ldrb_ok ? "true" : "false", ldrw_ok ? "true" : "false",
           ldrx_ok ? "true" : "false", ldpw_ok ? "true" : "false", base());
    dlclose(image);
    return ok ? 0 : 1;
}
