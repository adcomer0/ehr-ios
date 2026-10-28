#pragma once
#include <cstddef>
#include <cstdint>

// Original bounded verifier for the simple inline Boehm bitmap form only.
// No descriptor is dereferenced, allocated, freed, or treated as a pointer.
namespace ehr_reference_layout {
inline bool simpleDescriptor(size_t instanceBytes,uint64_t publicBitmap,uintptr_t descriptor) noexcept {
    if(sizeof(uintptr_t)!=8||instanceBytes<16||instanceBytes%8||instanceBytes/8>29||!publicBitmap)return false;
    const size_t slots=instanceBytes/8;
    if(publicBitmap>>slots||publicBitmap&3)return false; // Native object header is not a managed field.
    uint64_t expected=1; // GC_DS_BITMAP; upper bits run in reversed pointer-word order.
    for(size_t i=0;i<slots;++i)if(publicBitmap&(UINT64_C(1)<<i))expected|=UINT64_C(1)<<(63-i);
    return descriptor==expected;
}
}
