// Original own-source routing fixture; no game bytes, layouts or runtime mocks.
#include "EHRActionRegistry.hpp"
#include <cstdio>
#include <stdexcept>
#include <unordered_map>
int main() {
    int checks=0,failures=0;
    auto check=[&](bool value){++checks;if(!value)++failures;};
    ehr_action::Registry registry;
    std::unordered_map<uint32_t,void *> targets;
    int first=1,second=2,moved=3;uint64_t invoked=0,forgotten=0,freed=0;
    auto target=[&](uint32_t weak){return targets[weak];};
    auto invoke=[&](uint64_t source){invoked=source;return 0;};
    auto forget=[&](uint64_t source){forgotten+=source;return 0;};
    auto free=[&](uint32_t weak){targets.erase(weak);++freed;};
    targets[1]=&first;
    const auto one=registry.add(1,1);
    check(one && registry.active()==1 && registry.count()==1);
    check(registry.dispatch(&first,target,invoke) && invoked==1 && registry.find(one)->status==0);
    check(registry.close(one,forget)==0 && forgotten==1 && registry.active()==0);
    check(registry.close(one,forget)==0 && forgotten==1);
    invoked=0;check(registry.dispatch(&first,target,invoke) && invoked==0);
    targets[1]=nullptr;
    check(registry.sweep(target,free,forget)==1 && freed==1 && forgotten==1 && registry.count()==0);
    check(registry.close(one,forget)==9);
    targets[2]=&second;const auto two=registry.add(2,2);
    check(registry.dispatch(&second,target,[](uint64_t){return 6;}) && registry.find(two)->status==6);
    check(registry.dispatch(&second,target,[](uint64_t)->int32_t{throw std::runtime_error("own fixture");}) && registry.find(two)->status==4 && !registry.find(two)->executing);
    check(registry.dispatch(&second,target,[&](uint64_t){registry.dispatch(&second,target,invoke);return 0;}) && registry.find(two)->status==4);
    check(registry.dispatch(&second,target,[&](uint64_t){return registry.close(two,forget);}) && registry.find(two)->closed && forgotten==3);
    targets[2]=nullptr;registry.sweep(target,free,forget);
    targets[3]=&first;const auto dead=registry.add(3,3);targets[3]=nullptr;
    targets[4]=&first;const auto fresh=registry.add(4,4);invoked=0;
    check(registry.dispatch(&first,target,invoke) && invoked==4 && registry.find(dead)->status==0);
    targets[4]=&moved;invoked=0;
    check(!registry.dispatch(&first,target,invoke) && invoked==0);
    check(registry.dispatch(&moved,target,invoke) && invoked==4);
    check(registry.sweep(target,free,forget)==1 && forgotten==6 && registry.find(fresh));
    targets[4]=nullptr;check(registry.sweep(target,free,forget)==1 && forgotten==10 && registry.count()==0);
    check(registry.sweep(target,free,forget)==0 && forgotten==10);
    for(uint32_t i=1;i<=256;++i) check(registry.add(i,1000+i)!=0);
    check(!registry.hasCapacity() && registry.add(257,9999)==0 && registry.count()==256);
    check(registry.sweep(target,free,forget)==256 && registry.count()==0 && registry.hasCapacity());
    std::printf("{\"checks\":%d,\"failures\":%d,\"scope\":\"original native routing model only\"}\n",checks,failures);
    return failures ? 1 : 0;
}
