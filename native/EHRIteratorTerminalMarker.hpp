#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>

namespace ehr_iterators {
// Immutable after publication. The only unchecked memory inputs are live native
// hook receivers: their exact class header is checked before reading a field.
// Offsets and the header representation are validated through public runtime
// APIs while a real carrier is pinned; no IL2CPP layout constants are guessed.
class TerminalMarker {
    std::atomic<void *> marker_{nullptr};
    void *klass_ = nullptr;
    size_t offset_ = 0;
    static uintptr_t load(const void *slot) noexcept {
        return __atomic_load_n(static_cast<const uintptr_t *>(slot), __ATOMIC_ACQUIRE);
    }
public:
    bool configure(void *klass, void *marker, size_t offset, size_t instanceSize,
                   size_t headerSize) noexcept {
        if (!klass || !marker || reinterpret_cast<uintptr_t>(klass) % alignof(void *) ||
            reinterpret_cast<uintptr_t>(marker) % alignof(void *) ||
            headerSize < sizeof(void *) || headerSize > instanceSize ||
            instanceSize > 1024 * 1024 || offset < headerSize ||
            offset % alignof(void *) || offset > instanceSize ||
            instanceSize - offset < sizeof(void *)) return false;
        if (void *existing = marker_.load(std::memory_order_acquire))
            return existing == marker && klass_ == klass && offset_ == offset;
        klass_ = klass;
        offset_ = offset;
        marker_.store(marker, std::memory_order_release);
        return true;
    }
    bool hasClassHeader(const void *identity, const void *klass) const noexcept {
        return identity && !(reinterpret_cast<uintptr_t>(identity) % alignof(void *)) &&
            load(identity) == reinterpret_cast<uintptr_t>(klass);
    }
    bool contains(const void *identity) const noexcept {
        void *marker = marker_.load(std::memory_order_acquire);
        if (!marker || !hasClassHeader(identity, klass_)) return false;
        const auto *field = static_cast<const unsigned char *>(identity) + offset_;
        return load(field) == reinterpret_cast<uintptr_t>(marker);
    }
    bool ready() const noexcept { return marker_.load(std::memory_order_acquire) != nullptr; }
};
}
