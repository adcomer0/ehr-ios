#pragma once
#include <array>
#include <cstdint>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

// Version-specific hypothesis checker, never a native class definition. Public
// facts are collected first. Reads use an injected bounded copier (Mach API in
// production, owned memory in tests). False provenance forbids even one read.
namespace ehr_class_preflight {
struct Collection {
    std::string name;
    size_t pointerOffset = 0, countOffset = 0, stride = 0;
    bool pointerArray = false;
    uintptr_t publicBase = 0; // First opaque cursor returned by public iterator.
    std::vector<uintptr_t> publicEntries;
};
struct Facts {
    uintptr_t klass = 0, image = 0, name = 0, nameSpace = 0, type = 0;
    uintptr_t parent = 0, declaring = 0, element = 0;
    uint32_t instanceSize = 0, flags = 0, token = 0, fieldCount = 0, typeAttributes = 0;
    uint8_t rank = 0, typeKind = 0;
    bool initialized = false, hasReferences = false, valueType = false, typeByRef = false;
    std::vector<uintptr_t> publicHierarchy; // Root -> class, max32.
    std::vector<Collection> collections;
};
struct Check { std::string name; bool pass; };
struct Result {
    bool gate = false, header = false, collections = false, hierarchy = false;
    uint16_t vtableCount = 0;
    uint8_t initializedBits = 0, extraBits = 0;
    std::vector<Check> checks;
    size_t privateReads = 0;
    bool all() const { return gate && header && collections && hierarchy; }
};
template<class T> T at(const std::array<uint8_t,312> &bytes, size_t offset) {
    T value{}; if (offset <= bytes.size() && sizeof(value) <= bytes.size()-offset) memcpy(&value, bytes.data()+offset, sizeof(value)); return value;
}
inline bool add(uintptr_t a, size_t b, uintptr_t &out) {
    if (b > std::numeric_limits<uintptr_t>::max()-a) return false; out=a+b; return true;
}
template<class Read> Result verify(bool provenance, const Facts &facts, Read read) {
    Result result; result.gate = provenance;
    if (!provenance || !facts.klass || facts.publicHierarchy.empty() || facts.publicHierarchy.size()>32) return result;
    std::array<uint8_t,312> bytes{};
    ++result.privateReads;
    if (!read(facts.klass, bytes.data(), bytes.size())) return result;
    auto check=[&](const char *name,bool pass){result.checks.push_back({name,pass});return pass;};
    bool header=true;
    auto pointer=[&](const char *name,size_t offset,uintptr_t expected){header=check(name,at<uintptr_t>(bytes,offset)==expected)&&header;};
    pointer("image+0",0,facts.image); pointer("name+16",16,facts.name); pointer("namespace+24",24,facts.nameSpace);
    header=check("byValTypeAddress+32",facts.type==facts.klass+32)&&header;
    pointer("element+64",64,facts.element); pointer("declaring+80",80,facts.declaring); pointer("parent+88",88,facts.parent); pointer("self+120",120,facts.klass);
    header=check("instanceSize+248",at<uint32_t>(bytes,248)==facts.instanceSize)&&header;
    header=check("flags+280",at<uint32_t>(bytes,280)==facts.flags)&&header;
    header=check("token+284",at<uint32_t>(bytes,284)==facts.token)&&header;
    header=check("fieldCount+292",at<uint16_t>(bytes,292)==facts.fieldCount)&&header;
    header=check("hierarchyDepth+304",at<uint8_t>(bytes,304)==facts.publicHierarchy.size())&&header;
    header=check("rank+306",at<uint8_t>(bytes,306)==facts.rank)&&header;
    result.initializedBits=at<uint8_t>(bytes,309); result.extraBits=at<uint8_t>(bytes,310);
    header=check("initializedBit+309.1",bool(result.initializedBits&2)==facts.initialized)&&header;
    header=check("hasReferencesBit+309.5",bool(result.initializedBits&32)==facts.hasReferences)&&header;
    const uint32_t typeBits=at<uint32_t>(bytes,40);
    header=check("typeKind+40.16",uint8_t(typeBits>>16)==facts.typeKind)&&header;
    header=check("typeAttributes+40.0",uint16_t(typeBits)==facts.typeAttributes)&&header;
    header=check("typeByRefBit+40.29",bool(typeBits&(1u<<29))==facts.typeByRef)&&header;
    header=check("valueTypeBit+40.31",bool(typeBits&(1u<<31))==facts.valueType)&&header;
    for (const auto &collection : facts.collections) {
        const bool bounded=collection.publicEntries.size()<=4096;
        const bool count=bounded && at<uint16_t>(bytes,collection.countOffset)==collection.publicEntries.size();
        result.checks.push_back({collection.name+"Count",count}); header=count&&header;
        if (!collection.publicEntries.empty()) {
            const bool pointer=collection.publicBase && at<uintptr_t>(bytes,collection.pointerOffset)==collection.publicBase;
            result.checks.push_back({collection.name+"PointerMatchesPublicCursor",pointer}); header=pointer&&header;
        }
    }
    result.header=header;
    // No pointer table, hierarchy array or vtable is read when any public
    // scalar/count/pointer prerequisite disagrees with the candidate header.
    if (!header) return result;
    result.vtableCount=at<uint16_t>(bytes,298); // Reported hypothesis, not a verified count.
    bool collections=true;
    for (const auto &collection : facts.collections) {
        const auto &entries=collection.publicEntries;
        if (entries.empty()) continue; // Empty pointer has no independent witness.
        const uintptr_t base=at<uintptr_t>(bytes,collection.pointerOffset);
        bool endpoints=true;
        if (collection.pointerArray) {
            uintptr_t first=0,last=0,end=0;
            endpoints=add(base,(entries.size()-1)*sizeof(uintptr_t),end);
            if(endpoints){++result.privateReads;endpoints=read(base,&first,sizeof(first));}
            if(endpoints){++result.privateReads;endpoints=read(end,&last,sizeof(last));}
            endpoints=endpoints&&first==entries.front()&&last==entries.back();
        } else {
            uintptr_t end=0;
            endpoints=collection.stride!=0 && add(base,(entries.size()-1)*collection.stride,end) && base==entries.front()&&end==entries.back();
            for(size_t i=0;endpoints&&i<entries.size();++i){uintptr_t expected=0;endpoints=add(base,i*collection.stride,expected)&&entries[i]==expected;}
        }
        result.checks.push_back({collection.name+"FirstLast",endpoints}); collections=endpoints&&collections;
    }
    result.collections=collections;
    if(!collections)return result;
    const auto hierarchy=at<uintptr_t>(bytes,200);
    std::array<uintptr_t,32> entries{};
    ++result.privateReads;
    result.hierarchy=hierarchy&&read(hierarchy,entries.data(),facts.publicHierarchy.size()*sizeof(uintptr_t));
    for(size_t i=0;result.hierarchy&&i<facts.publicHierarchy.size();++i)result.hierarchy=entries[i]==facts.publicHierarchy[i];
    result.checks.push_back({"hierarchyPointer+200RootToClass",result.hierarchy});
    return result;
}
}
