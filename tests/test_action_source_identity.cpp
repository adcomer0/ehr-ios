#include "EHRActionRegistry.hpp"
#include <cassert>
#include <cstdint>
int main(){
 ehr_action::Registry r;int first=1,second=2;void *targets[]={nullptr,&first,&second};int forgets=0,frees=0;
 const auto a=r.add(42,1);assert(a&&r.findSource(42)->registration==a&&r.findSource(0)==nullptr);
 auto *same=r.findSource(42);assert(same->weak==1&&targets[same->weak]==&first&&r.count()==1);
 assert(r.close(a,[&](uint64_t source){assert(source==42);++forgets;return 0;})==0);
 assert(r.findSource(42)==nullptr&&r.count()==1&&r.active()==0);
 const auto b=r.add(42,2);assert(b&&b!=a&&r.findSource(42)->registration==b);
 targets[1]=nullptr;assert(r.sweep([&](uint32_t h){return targets[h];},[&](uint32_t h){assert(h==1);++frees;},[&](uint64_t){++forgets;return 0;})==1);
 assert(r.findSource(42)->registration==b&&forgets==1&&frees==1);
 targets[2]=nullptr;assert(r.sweep([&](uint32_t h){return targets[h];},[&](uint32_t h){assert(h==2);++frees;},[&](uint64_t source){assert(source==42);++forgets;return 0;})==1);
 assert(!r.findSource(42)&&r.count()==0&&forgets==2&&frees==2);
}
