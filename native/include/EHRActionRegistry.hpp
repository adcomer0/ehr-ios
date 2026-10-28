#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace ehr_action {
// Own fixed-capacity routing model. Runtime weak handles are opaque integers.
// The adapter guarantees main-thread access before entering this class.
struct Entry {
    uint64_t registration=0,source=0;
    uint32_t weak=0;
    int32_t status=0;
    bool closed=false,executing=false;
};
class Registry {
    std::array<Entry,256> entries_{};
    uint64_t next_=UINT64_C(0x4143544e00000001);
public:
    Entry *find(uint64_t registration) noexcept {
        for(auto &entry:entries_) if(entry.weak && entry.registration==registration) return &entry;
        return nullptr;
    }
    Entry *findSource(uint64_t source) noexcept {
        if(!source)return nullptr;
        for(auto &entry:entries_)if(entry.weak&&!entry.closed&&entry.source==source)return &entry;
        return nullptr;
    }
    bool hasCapacity() const noexcept {
        if(next_==std::numeric_limits<uint64_t>::max()) return false;
        for(const auto &entry:entries_) if(!entry.weak) return true;
        return false;
    }
    uint64_t add(uint64_t source,uint32_t weak) noexcept {
        if(!source || !weak || !hasCapacity()) return 0;
        for(auto &entry:entries_) if(!entry.weak) {
            entry={next_++,source,weak,0,false,false};return entry.registration;
        }
        return 0;
    }
    template<class Forget> int32_t close(uint64_t registration,Forget forget) noexcept {
        auto *entry=find(registration);
        if(!entry) return 9;
        if(entry->closed) return 0;
        const auto source=entry->source;
        // Tombstone before managed reentry; each source is forgotten once.
        entry->closed=true;entry->source=0;
        try {return forget(source);} catch(...) {return 4;}
    }
    template<class Target,class Invoke> bool dispatch(void *identity,Target target,Invoke invoke) noexcept {
        if(!identity) return false;
        for(auto &entry:entries_) {
            // Never trust a cached object address. The current weak target is
            // checked on every call, including closed and reused registrations.
            if(!entry.weak || target(entry.weak)!=identity) continue;
            if(entry.closed) return true;
            if(entry.executing) {entry.status=4;return true;}
            entry.executing=true;entry.status=0;
            try {const auto status=invoke(entry.source);if(!entry.status) entry.status=status;} catch(...) {entry.status=4;}
            entry.executing=false;
            return true;
        }
        return false;
    }
    template<class Target,class Free,class Forget> size_t sweep(Target target,Free free,Forget forget) noexcept {
        size_t removed=0;
        for(auto &entry:entries_) {
            if(!entry.weak || entry.executing || target(entry.weak)) continue;
            const auto registration=entry.registration;
            const auto weak=entry.weak;
            close(registration,forget);
            free(static_cast<uint32_t>(weak));entry={};++removed;
        }
        return removed;
    }
    size_t count() const noexcept {size_t n=0;for(const auto &entry:entries_) n+=entry.weak!=0;return n;}
    size_t active() const noexcept {size_t n=0;for(const auto &entry:entries_) n+=entry.weak && !entry.closed;return n;}
};
}
