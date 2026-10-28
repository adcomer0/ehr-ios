#pragma once
#include <stdint.h>
namespace ehr_auth_retry {
// Native frame context only. No object is retained beyond the original callback.
struct Context { void *owner = nullptr; bool eligible = false; bool consumed = false; };
inline thread_local Context context;
class Scope {
    Context previous;
public:
    Scope(void *owner, bool mainThread, bool known, int32_t result) noexcept : previous(context) {
        context = {owner, mainThread && owner && known && result == 7000, false};
    }
    ~Scope() { context = previous; }
    Scope(const Scope &) = delete;
    Scope &operator=(const Scope &) = delete;
};
inline bool eligible(void *owner, bool mainThread) noexcept {
    return mainThread && context.eligible && !context.consumed && context.owner == owner;
}
inline void consume() noexcept { context.consumed = true; }
}
