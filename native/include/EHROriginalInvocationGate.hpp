#pragma once

#include <cstdint>
#include <cstdlib>

namespace ehr {

// A caught runtime_invoke used by a patch's original delegate re-enters the
// installed native thunk. This scope lets precisely that entry call its signed
// trampoline. Consume before calling the trampoline: recursive calls made by
// the original body must receive the normal patch pipeline again.
//
// This is only routing state. It grants no memory access and owns no runtime
// objects. The enclosing native invocation must retain all of its roots until
// the managed callback has returned. It must inspect consumed() afterwards:
// an unconsumed permit is not evidence that an original target ran.
class OriginalInvocationPermit final {
public:
    OriginalInvocationPermit(uint64_t target, const void *method) noexcept
        : target_(target), method_(method), previous_(top_), active_(target && method) {
        if (active_) top_ = this;
    }

    ~OriginalInvocationPermit() noexcept {
        if (!active_) return;
        // A cross-thread destruction or non-LIFO lifetime is a programming
        // error. Continuing could bypass an unrelated intercepted invocation.
        if (top_ != this) std::abort();
        top_ = previous_;
    }

    OriginalInvocationPermit(const OriginalInvocationPermit &) = delete;
    OriginalInvocationPermit &operator=(const OriginalInvocationPermit &) = delete;
    OriginalInvocationPermit(OriginalInvocationPermit &&) = delete;
    OriginalInvocationPermit &operator=(OriginalInvocationPermit &&) = delete;

    bool valid() const noexcept { return active_; }
    bool consumed() const noexcept { return consumed_; }

    static bool tryConsume(uint64_t target, const void *method) noexcept {
        OriginalInvocationPermit *permit = top_;
        if (!permit || !target || !method || permit->consumed_ ||
            permit->target_ != target || permit->method_ != method) return false;
        permit->consumed_ = true;
        return true;
    }

private:
    inline static thread_local OriginalInvocationPermit *top_ = nullptr;
    const uint64_t target_;
    const void *const method_;
    OriginalInvocationPermit *const previous_;
    const bool active_;
    bool consumed_ = false;
};

} // namespace ehr
