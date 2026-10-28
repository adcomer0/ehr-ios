// OWN byte storage tests the guarded comparison algorithm. It is never an
// IL2CPP class/object, registered metadata, game structure or executable code.
#include "EHRClassLayoutCore.hpp"
#include <cassert>
#include <iostream>
#include <functional>
using namespace ehr_class_preflight;
struct OwnStorage {
    std::array<uint8_t,4096> bytes{};
    Facts facts;
    size_t reads=0,invalidReads=0;
    uintptr_t base(){return reinterpret_cast<uintptr_t>(bytes.data());}
    template<class T> void put(size_t offset,T value){memcpy(bytes.data()+offset,&value,sizeof(value));}
    OwnStorage(){
        facts.klass=base();facts.image=0x101;facts.name=0x102;facts.nameSpace=0x103;facts.type=base()+32;
        facts.element=base();facts.instanceSize=32;facts.flags=1;facts.token=0x02000001;facts.fieldCount=2;
        facts.typeKind=0x12;facts.initialized=true;facts.hasReferences=true;facts.publicHierarchy={base()};
        put(0,facts.image);put(16,facts.name);put(24,facts.nameSpace);put(64,facts.element);put(120,facts.klass);
        put(248,facts.instanceSize);put(280,facts.flags);put(284,facts.token);put<uint16_t>(292,2);
        put<uint8_t>(304,1);put<uint8_t>(309,34);put<uint32_t>(40,uint32_t(0x12)<<16);
        put<uintptr_t>(200,base()+512);put<uintptr_t>(512,base());
        facts.collections={{"methods",152,288,8,true,base()+600,{0x701,0x702}},
            {"fields",128,292,32,false,base()+800,{base()+800,base()+832}},
            {"properties",144,290,40,false,0,{}},{"events",136,294,56,false,0,{}},
            {"nested",160,296,8,true,base()+700,{0x801}}, {"interfaces",168,300,8,true,0,{}}};
        put<uintptr_t>(152,base()+600);put<uint16_t>(288,2);put<uintptr_t>(600,0x701);put<uintptr_t>(608,0x702);
        put<uintptr_t>(128,base()+800);put<uintptr_t>(160,base()+700);put<uint16_t>(296,1);put<uintptr_t>(700,0x801);
    }
    bool read(uintptr_t address,void*out,size_t size){++reads;if(address<base()||size>bytes.size()||address-base()>bytes.size()-size){++invalidReads;return false;}memcpy(out,bytes.data()+address-base(),size);return true;}
    Result verify(bool gate=true){return ehr_class_preflight::verify(gate,facts,[&](auto a,auto b,auto c){return read(a,b,c);});}
};
int main(){
    size_t checks=0;
    {OwnStorage s;auto r=s.verify(false);assert(!r.all()&&s.reads==0);++checks;}
    {OwnStorage s;auto r=s.verify();assert(r.all()&&s.reads>1);++checks;}
    for(size_t offset:{0u,16u,24u,64u,80u,88u,120u,152u}){
        OwnStorage s;s.put<uintptr_t>(offset,0xdead);auto r=s.verify();assert(!r.all()&&!r.header&&s.reads==1);++checks;
    }
    {OwnStorage s;s.put<uint16_t>(288,3);auto r=s.verify();assert(!r.header&&s.reads==1);++checks;}
    {OwnStorage s;s.put<uint8_t>(309,2);auto r=s.verify();assert(!r.header&&s.reads==1);++checks;}
    {OwnStorage s;s.put<uintptr_t>(608,0xbad);auto r=s.verify();assert(r.header&&!r.collections&&!r.hierarchy);++checks;}
    {OwnStorage s;s.put<uintptr_t>(512,0xbad);auto r=s.verify();assert(r.header&&r.collections&&!r.hierarchy);++checks;}
    {OwnStorage s;s.put<uintptr_t>(200,0xbad);auto r=s.verify();assert(r.header&&r.collections&&!r.hierarchy);++checks;}
    {OwnStorage s;s.facts.collections[0].publicEntries.resize(4097);auto r=s.verify();assert(!r.header&&s.reads==1);++checks;}
    {OwnStorage s;s.facts.publicHierarchy.resize(33);auto r=s.verify();assert(!r.all()&&s.reads==0);++checks;}
    {OwnStorage s;s.facts.collections[0].publicBase=UINTPTR_MAX-4;s.put<uintptr_t>(152,UINTPTR_MAX-4);auto r=s.verify();assert(r.header&&!r.collections&&s.invalidReads==0);++checks;}
    {OwnStorage s;s.facts.collections[1].publicEntries[1]+=8;auto r=s.verify();assert(r.header&&!r.collections&&!r.hierarchy);++checks;}
    std::cout<<"PASS: "<<checks<<" OWN guarded layout checks; false provenance/count/pointer facts forbid indirect reads; no game code or structures executed.\n";
}
