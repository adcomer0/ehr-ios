// Executes ORIGINAL native registry + actual NativeAOT iterator over OWN test
// objects. No Unity objects/metadata/game code are fabricated or executed. Real
// IL2CPP association, exception construction and engine scheduling are separate.
#import <Foundation/Foundation.h>
#include "EHRManagedBridgeV1.h"
#include "EHRManagedIteratorAdapter.h"
#include "EHRRuntimeIteratorPrivate.h"
#include <cassert>
#include <cstring>
#include <dlfcn.h>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace {
constexpr uint64_t Enum = 101, List = 102, Interface = 103, BoolClass = 104, String = 105, Invalid = 106, Unsupported = 107;
constexpr uint64_t Move = 201, Current = 202, Reset = 203;
struct OwnObject { uint64_t klass; uint8_t boolean = 0; std::u16string text; };
struct Raised { std::shared_ptr<OwnObject> exception; };
std::unordered_map<uint64_t, std::shared_ptr<OwnObject>> roots;
std::vector<std::shared_ptr<OwnObject>> objects;
uint64_t next = 1000, fallbackMove = 0, fallbackReset = 0, pinned = 0;
EHRManagedIteratorHostV1 activeHost{};
bool activeWorkerChecked = false;
std::shared_ptr<OwnObject> make(uint64_t klass) {
    auto object = std::make_shared<OwnObject>(); object->klass = klass; objects.push_back(object); return object;
}
uint64_t root(std::shared_ptr<OwnObject> value) { if (!value) return 0; uint64_t id = next++; roots.emplace(id, value); return id; }
std::shared_ptr<OwnObject> object(uint64_t token) {
    if (!token) return nullptr; const auto found = roots.find(token); return found == roots.end() ? nullptr : found->second;
}
std::shared_ptr<OwnObject> object(void *pointer) {
    for (const auto &value : objects) if (value.get() == pointer) return value; return nullptr;
}
int32_t initialize() { return NSThread.isMainThread ? 0 : 2; }
uint32_t abi() { return 1; }
int32_t findClass(const char *image, const char *space, const char *name, uint64_t *result) {
    *result = 0; if (strcmp(image, "mscorlib.dll")) return 3;
    if (!strcmp(space, "System.Collections")) {
        if (!strcmp(name, "ArrayList+ArrayListEnumeratorSimple")) *result = Enum;
        else if (!strcmp(name, "ArrayList")) *result = List;
        else if (!strcmp(name, "IEnumerator")) *result = Interface;
    } else if (!strcmp(space, "System")) {
        if (!strcmp(name, "InvalidOperationException")) *result = Invalid;
        else if (!strcmp(name, "NotSupportedException")) *result = Unsupported;
    }
    return *result ? 0 : 3;
}
int32_t objectClass(uint64_t token, uint64_t *result) { auto value = object(token); *result = value ? value->klass : 0; return value ? 0 : 9; }
int32_t findMethod(uint64_t klass, const char *name, const char *const *, size_t count, const char *returns, int isStatic, uint64_t *result) {
    *result = 0; if ((klass != Enum && klass != Interface) || count || isStatic) return 3;
    if (!strcmp(name, "MoveNext") && !strcmp(returns, "System.Boolean")) *result = Move;
    if (!strcmp(name, "get_Current") && !strcmp(returns, "System.Object")) *result = Current;
    if (!strcmp(name, "Reset") && !strcmp(returns, "System.Void")) *result = Reset;
    return *result ? 0 : 3;
}
int32_t release(uint64_t token) { return token == 0 || roots.erase(token) == 1 ? 0 : 9; }
int32_t retain(uint64_t token, uint64_t *result) { auto value = object(token); *result = root(value); return !token || value ? 0 : 9; }
int32_t invoke(uint64_t method, uint64_t receiver, const EHRManagedArgumentV1 *, size_t count, uint64_t *result, uint64_t *exception) {
    *result = *exception = 0; auto value = object(receiver);
    if (!value || value->klass != Enum || count) return 5;
    try {
        if (method == Move) {
            if (!activeWorkerChecked && EHRManagedIteratorRegistrationCount() == 1) {
                activeWorkerChecked = true;
                uint64_t duplicate = 0;
                assert(activeHost.register_carrier(receiver, 999, &duplicate) == EHR_RUNTIME_BAD_ARGUMENT && duplicate == 0);
                const size_t before = roots.size();
                std::thread worker([&] {
                    bool stopped = true; void *currentValue = reinterpret_cast<void *>(1);
                    assert(EHRManagedIteratorMoveNext(value.get(), &stopped) && !stopped);
                    assert(EHRManagedIteratorCurrent(value.get(), &currentValue) && !currentValue);
                    assert(EHRManagedIteratorReset(value.get()));
                }); worker.join();
                assert(roots.size() == before);
            }
            bool nextValue = false;
            if (!EHRManagedIteratorMoveNext(value.get(), &nextValue)) ++fallbackMove;
            auto boxed = make(BoolClass); boxed->boolean = nextValue ? 1 : 0; *result = root(boxed);
        } else if (method == Current) {
            void *current = nullptr;
            if (!EHRManagedIteratorCurrent(value.get(), &current)) throw Raised{make(Invalid)};
            *result = root(object(current));
        } else if (method == Reset) {
            if (!EHRManagedIteratorReset(value.get())) ++fallbackReset;
        } else return 3;
        return 0;
    } catch (const Raised &raised) { *exception = root(raised.exception); return 6; }
}
int32_t copyValue(uint64_t token, void *output, size_t capacity, size_t *count) {
    auto value = object(token); *count = 1; if (!value || value->klass != BoolClass) return 5;
    if (capacity < 1 || !output) return 8; *static_cast<uint8_t *>(output) = value->boolean; return 0;
}
int32_t stringCreate(const uint16_t *units, size_t count, uint64_t *result) {
    auto value = make(String); value->text.assign(reinterpret_cast<const char16_t *>(units), count); *result = root(value); return 0;
}
int32_t stringCopy(uint64_t token, uint16_t *units, size_t capacity, size_t *count) {
    auto value = object(token); if (!value || value->klass != String) return 5; *count = value->text.size();
    if (capacity < *count || (*count && !units)) return 8;
    if (*count) memcpy(units, value->text.data(), *count * sizeof(uint16_t)); return 0;
}
EHRManagedGatewayV1 table() {
    return {1, sizeof(EHRManagedGatewayV1), abi, initialize, findClass, objectClass, findMethod,
        [](uint64_t,const char*,const char*,int,uint64_t*) -> int32_t { return 7; }, invoke,
        [](uint64_t,uint64_t,uint64_t*) -> int32_t { return 7; },
        [](uint64_t,uint64_t,const EHRManagedArgumentV1*) -> int32_t { return 7; },
        [](uint64_t,size_t*) -> int32_t { return 7; },
        [](uint64_t,const void*,size_t,uint64_t*) -> int32_t { return 7; }, copyValue, stringCreate, stringCopy, release, retain,
        []() -> uint64_t { return 0; }, []() -> int32_t { return 0; }};
}
}
extern "C" EHRRuntimeStatus ehr_runtime_find_class(const char *i,const char *s,const char *n,uint64_t *r) { return static_cast<EHRRuntimeStatus>(findClass(i,s,n,r)); }
extern "C" EHRRuntimeStatus ehr_runtime_object_class(uint64_t o,uint64_t *r) { return static_cast<EHRRuntimeStatus>(objectClass(o,r)); }
extern "C" EHRRuntimeStatus ehr_runtime_find_method(uint64_t c,const char *n,const char *const *p,size_t z,const char *t,int s,uint64_t *r) { return static_cast<EHRRuntimeStatus>(findMethod(c,n,p,z,t,s,r)); }
extern "C" EHRRuntimeStatus ehr_runtime_object_release(uint64_t o) { return static_cast<EHRRuntimeStatus>(release(o)); }
extern "C" EHRRuntimeStatus ehr_runtime_object_same(uint64_t a,uint64_t b,int32_t *same) {
    auto x=object(a),y=object(b); if ((a&&!x)||(b&&!y)) return EHR_RUNTIME_INVALID_TOKEN; *same=x==y; return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_validate_native_method(uint64_t method,uint64_t expected,uint64_t *observed) {
    *observed = method == Move ? 0x367ade0 : method == Current ? 0x367afe4 : method == Reset ? 0x367b0dc : 0;
    return *observed && *observed == expected ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH;
}
EHRRuntimeStatus EHRRuntimeIteratorPin(uint64_t borrowed,uint64_t *owned,void **identity) {
    auto value=object(borrowed); if (!value) return EHR_RUNTIME_INVALID_TOKEN; ++pinned;
    *owned=root(value); *identity=value.get(); return EHR_RUNTIME_OK;
}
EHRRuntimeStatus EHRRuntimeIteratorBorrow(uint64_t token,void **result) {
    auto value=object(token); *result=value.get(); return !token||value ? EHR_RUNTIME_OK : EHR_RUNTIME_INVALID_TOKEN;
}
void EHRRuntimeIteratorRaise(EHRRuntimeStatus status) { throw Raised{make(status==EHR_RUNTIME_UNSUPPORTED?Unsupported:Invalid)}; }

int main(int argc,char **argv) { @autoreleasepool {
    if(argc!=2)return 2;
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL); if(!library){std::cerr<<dlerror()<<'\n';return 1;}
    auto bindCore=reinterpret_cast<int32_t(*)(const EHRManagedGatewayV1*,size_t)>(dlsym(library,"ehr_generated_bind_gateway"));
    auto bindIterator=reinterpret_cast<decltype(&ehr_iterator_bind_gateway)>(dlsym(library,"ehr_iterator_bind_gateway"));
    auto selfTest=reinterpret_cast<decltype(&ehr_iterator_self_test)>(dlsym(library,"ehr_iterator_self_test"));
    assert(bindCore&&bindIterator&&selfTest);
    auto core=table(); assert(bindCore(&core,sizeof(core))==0);
    EHRManagedIteratorHostV1 host{}; EHRManagedIteratorMakeTable(&host);
    activeHost = host;
    EHRManagedIteratorCallbacksV1 callbacks{};
    assert(bindIterator(&host,sizeof(host)-1,&callbacks,sizeof(callbacks))==4);
    assert(bindIterator(&host,sizeof(host),&callbacks,sizeof(callbacks))==0);
    assert(EHRManagedIteratorSetCallbacks(&callbacks)==EHR_RUNTIME_OK);
    auto native=make(Enum),ordinary=make(Enum); uint64_t carrier=root(native),unregistered=root(ordinary);
    EHRManagedIteratorProofV1 proof{}; int32_t status=selfTest(carrier,unregistered,&proof,sizeof(proof));
    if(status||proof.pass!=1) { std::cerr<<"status="<<status<<" proof="<<proof.status<<" side="<<proof.side_effects<<" disposed="<<proof.disposed_once<<" flags=";
        const auto *flags=&proof.null_yield; for(size_t i=0;i<9;++i)std::cerr<<flags[i]<<',';std::cerr<<'\n';return 1; }
    assert(EHRManagedIteratorRegistrationCount()==0&&EHRManagedIteratorCurrentRootCount()==0);
    assert(roots.size()==2&&pinned==2&&fallbackMove==1&&fallbackReset==1&&activeWorkerChecked);
    assert(release(carrier)==0&&release(unregistered)==0&&roots.empty());
    bool nextValue=true; void *current=reinterpret_cast<void*>(1);
    assert(!EHRManagedIteratorMoveNext(native.get(),&nextValue));
    assert(!EHRManagedIteratorCurrent(native.get(),&current));
    assert(!EHRManagedIteratorReset(native.get()));
    assert(host.release_carrier(0)==EHR_RUNTIME_INVALID_TOKEN);
    uint64_t wrong = root(make(BoolClass)), rejected = 0;
    assert(host.register_carrier(wrong, 999, &rejected) == EHR_RUNTIME_TYPE_MISMATCH && rejected == 0);
    assert(release(wrong) == 0 && roots.empty());
    std::thread worker([&]{uint64_t registration=0;assert(host.register_carrier(0,1,&registration)==EHR_RUNTIME_WRONG_THREAD);});worker.join();
    std::cout<<"PASS: NativeAOT source iterator -> native identity registry -> source callbacks -> owned native yields; exact caught Reset/Current exceptions; all roots/registrations closed. OWN FIXTURE ONLY.\n";
    return 0;
}}
