// ORIGINAL own byte storage. No game structure instances, bytes or execution.
#include "native/EHRRuntimePinnedAssociationCore.h"
#include <array>
#include <iostream>
#include <stdexcept>
using namespace ehr_pinned;
static void require(bool value) { if (!value) throw std::runtime_error("association fixture failure"); }
int main() {
    std::array<unsigned char, 96> storage{};
    const char name[] = "OwnFixtureMethod";
    int owner = 0, otherOwner = 0;
    const uint32_t token = 0x06000017;
    const uintptr_t base = 0x100000000, target = base + 0x2200;
    auto put = [&](size_t offset, auto value) { memcpy(storage.data() + offset, &value, sizeof(value)); };
    auto reset = [&] {
        storage.fill(0); put(0, target); put(0x18, reinterpret_cast<uintptr_t>(name));
        put(0x20, reinterpret_cast<uintptr_t>(&owner)); put(0x48, token);
    };
    reset();
    const MethodFacts facts{storage.data(), &owner, &owner, name, token};
    VerifiedImage image{base, base + 0x1000, true, true, true, {{base, 0x4000}}};
    uint64_t observed = 999;
    require(compare_known_layout(facts,image,0x2200,&observed)==EHR_RUNTIME_OK && observed==0x2200);
    require(compare_known_layout(facts,image,0x2204,&observed)==EHR_RUNTIME_TYPE_MISMATCH && observed==0x2200);
    require(compare_known_layout(facts,image,0x2201,&observed)==EHR_RUNTIME_BAD_ARGUMENT && observed==0);
    require(compare_known_layout(facts,image,0,&observed)==EHR_RUNTIME_BAD_ARGUMENT && observed==0);
    require(compare_known_layout(facts,image,0x2200,nullptr)==EHR_RUNTIME_BAD_ARGUMENT);
    for (size_t offset : {size_t(0x18), size_t(0x20), size_t(0x48)}) {
        reset(); put(offset, uint64_t(0));
        require(compare_known_layout(facts,image,0x2200,&observed)==EHR_RUNTIME_TYPE_MISMATCH && observed==0);
    }
    reset();
    auto wrong = facts; wrong.metadata_owner = &otherOwner;
    require(compare_known_layout(wrong,image,0x2200,&observed)==EHR_RUNTIME_TYPE_MISMATCH && observed==0);
    wrong = facts; wrong.public_token = 0x02000001;
    require(compare_known_layout(wrong,image,0x2200,&observed)==EHR_RUNTIME_TYPE_MISMATCH && observed==0);
    for (uintptr_t address : {uintptr_t(0),base+1,base+0x100,base+0x2201,base+0x4000,base+0x5000}) {
        reset(); put(0,address);
        const auto status=compare_known_layout(facts,image,0x2200,&observed);
        require(status==(address?EHR_RUNTIME_TYPE_MISMATCH:EHR_RUNTIME_UNSUPPORTED) && observed==0);
    }
    reset(); put(0,base+0x3ffc);
    require(compare_known_layout(facts,image,0x3ffc,&observed)==EHR_RUNTIME_OK && observed==0x3ffc);
    reset();
    auto overlapping=image; overlapping.executable_file_ranges.push_back({base+0x2000,0x1000});
    require(compare_known_layout(facts,overlapping,0x2200,&observed)==EHR_RUNTIME_TYPE_MISMATCH && observed==0);
    auto zeroFill=image; zeroFill.executable_file_ranges={{base,0x2000}};
    require(compare_known_layout(facts,zeroFill,0x2200,&observed)==EHR_RUNTIME_TYPE_MISMATCH && observed==0);
    auto overflow=image; overflow.executable_file_ranges={{base,UINT64_MAX}};
    require(compare_known_layout(facts,overflow,0x2200,&observed)==EHR_RUNTIME_TYPE_MISMATCH && observed==0);
    // Deliberately unreadable own sentinel proves provenance checks precede
    // any known-layout memcpy in the helper, rather than relying on its fields.
    auto unreadable=facts;unreadable.method=reinterpret_cast<const void *>(uintptr_t(1));
    for (unsigned missing=0;missing<3;++missing) {
        auto unverified=image;
        if(missing==0)unverified.uuid_verified=false;
        if(missing==1)unverified.source_verified=false;
        if(missing==2)unverified.candidate_hash_verified=false;
        require(compare_known_layout(unreadable,unverified,0x2200,&observed)==EHR_RUNTIME_UNSUPPORTED && observed==0);
    }
    std::cout << "{\"pass\":true,\"fixture_only\":true,\"actual_game_executed\":false,\"pin_before_reads\":true,\"public_facts_cross_checked\":true,\"executable_file_backed_bounds\":true,\"only_rva_exported\":true}\n";
}
