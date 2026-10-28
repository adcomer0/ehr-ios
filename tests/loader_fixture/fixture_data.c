// Exercise original rebase, normal bind and lazy bind streams too.
#include <stdint.h>
#include <string.h>
extern void fixture_murder(void *, void *, uint32_t, void *);
void (*fixture_original_pointer)(void *, void *, uint32_t, void *) = fixture_murder;
size_t (*fixture_library_pointer)(const char *) = strlen;
size_t fixture_unhooked(const char *message) { return strlen(message); }
// Original zero-filled storage makes LINKEDIT/the inserted trampoline more
// than one megabyte away, so ADR must expand instead of remaining in range.
unsigned char fixture_relocation_gap[0x140000];
