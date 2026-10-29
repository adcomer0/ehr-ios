#pragma once
#include <cstdint>
// Pure policy for the exact factory product. Non-host yields are untouched.
namespace ehr_game_start {
enum class Policy:uint32_t {Ignore=0,Replace=1,Reject=2};
inline Policy policy(bool hostCurrent,int32_t parentState,int32_t childState,
                     bool parentOwner,bool childOwner,bool sameOwner,bool fixtureNullOwner) noexcept {
    if(!hostCurrent)return Policy::Ignore;
    if(parentState!=5&&parentState!=7)return Policy::Reject;
    if(childState!=0)return Policy::Reject;
    if(!parentOwner||!childOwner)
        return fixtureNullOwner&&!parentOwner&&!childOwner?Policy::Replace:Policy::Reject;
    return sameOwner?Policy::Replace:Policy::Reject;
}
}
