#pragma once
#include <array>
#include <atomic>
#include <cstdint>
#include <cstring>

// Original fixed-capacity registry for the first two native-only components.
// Records and pointed-to metadata must outlive the process after publication.
// Readers never allocate or lock. Publication is main-thread-only and one-shot.
namespace ehr_static_types {
using Pointer = const void *;
struct Record {
    Pointer klass = nullptr;
    Pointer image = nullptr;
    Pointer byValue = nullptr;
    Pointer byReference = nullptr;
    int32_t definitionIndex = 0;
    const char *nameSpace = nullptr;
    const char *name = nullptr;
};
enum class Publish { Ok, Invalid, AlreadyPublished };
template<size_t Count> class RegistryOf final {
    std::array<Record, Count> records_{};
    std::atomic<bool> published_{false};
    static bool bounded(const char *value) {
        return value && strnlen(value, 129) <= 128;
    }
public:
    Publish publish(const std::array<Record, Count> &records) noexcept {
        if (published_.load(std::memory_order_acquire)) return Publish::AlreadyPublished;
        for (size_t i = 0; i < records.size(); ++i) {
            const auto &r = records[i];
            if (!r.klass || !r.image || !r.byValue || !r.byReference || r.byValue == r.byReference ||
                r.definitionIndex != -3 - static_cast<int32_t>(i) || !bounded(r.nameSpace) || !bounded(r.name) || !*r.name)
                return Publish::Invalid;
            for (size_t j = 0; j < i; ++j) {
                const auto &prior = records[j];
                if (r.klass == prior.klass || r.byValue == prior.byValue || r.byReference == prior.byReference ||
                    r.byValue == prior.byReference || r.byReference == prior.byValue ||
                    (r.image == prior.image && !strcmp(r.nameSpace, prior.nameSpace) && !strcmp(r.name, prior.name)))
                    return Publish::Invalid;
            }
        }
        records_ = records;
        published_.store(true, std::memory_order_release);
        return Publish::Ok;
    }
    bool published() const noexcept { return published_.load(std::memory_order_acquire); }
    Pointer index(int32_t value) const noexcept {
        if (!published()) return nullptr;
        for (const auto &r : records_) if (r.definitionIndex == value) return r.klass;
        return nullptr;
    }
    Pointer exactType(Pointer value) const noexcept {
        if (!published() || !value) return nullptr;
        for (const auto &r : records_) if (r.byValue == value || r.byReference == value) return r.klass;
        return nullptr;
    }
    Pointer copiedType(uint8_t kind, intptr_t data) const noexcept {
        if (kind != 0x12 || data < INT32_MIN || data > INT32_MAX) return nullptr;
        return index(static_cast<int32_t>(data));
    }
    Pointer name(Pointer image, const char *space, const char *name) const noexcept {
        if (!published() || !image || !bounded(space) || !bounded(name)) return nullptr;
        for (const auto &r : records_)
            if (r.image == image && !strcmp(r.nameSpace, space) && !strcmp(r.name, name)) return r.klass;
        return nullptr;
    }
};
using Registry=RegistryOf<2>;
}
