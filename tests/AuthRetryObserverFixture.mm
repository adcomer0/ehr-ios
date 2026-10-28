#import <Foundation/Foundation.h>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include "../native/EHREOSLoginDiagnostics.mm"

namespace fixture {
int owner, other, info, metadata;
uint32_t checks=0, failed=0, normalCalls=0, silentCalls=0, records=0;
int32_t code=7000;
bool shouldBeEligible=true, getterThrows=false, originalThrows=false;
void check(bool value){++checks;if(!value)++failed;}
int32_t result(const void *value,const void *method){check(value==&info);check(method==&metadata);if(getterThrows)throw std::runtime_error("own getter");return code;}
void normal(void *self,void *value,const void *method){
    ++normalCalls;check(self==&owner);check(value==&info||value==nullptr);check(method==&metadata);
    check(ehr_auth_retry::eligible(self,true)==shouldBeEligible);
    if(originalThrows)throw std::runtime_error("own original callback");
}
void silent(void *self,void *value,const void *method){
    ++silentCalls;check(self==&owner);check(value==&info);check(method==&metadata);
    check(!ehr_auth_retry::eligible(self,true));
}
}
uintptr_t EHREOSPlatformLoginTrampolineRVA=0,EHREOSPlatformSilentLoginTrampolineRVA=0;
extern "C" uintptr_t EHRNativeHooksImageBaseForDiagnostics(void){return 1;}
void EHRRuntimeDiagnosticsRecordEOSLogin(uint32_t phase,int32_t,int32_t,uint64_t count){fixture::check(phase==1||phase==2);fixture::check(count>0);++fixture::records;}
extern "C" EHRRuntimeStatus ehr_runtime_find_class(const char *,const char *,const char *,EHRRuntimeToken *){return EHR_RUNTIME_NOT_READY;}
extern "C" EHRRuntimeStatus ehr_runtime_find_method(EHRRuntimeToken,const char *,const char *const *,size_t,const char *,int,EHRRuntimeToken *){return EHR_RUNTIME_NOT_READY;}
extern "C" EHRRuntimeStatus ehr_runtime_validate_native_method(EHRRuntimeToken,uint64_t,uint64_t *){return EHR_RUNTIME_NOT_READY;}
EHRRuntimeStatus EHRRuntimeBorrowMethod(EHRRuntimeToken,const void **,const void **){return EHR_RUNTIME_NOT_READY;}

int main(){@autoreleasepool{
    using namespace fixture;
    EHREOSPlatformLoginTrampolineRVA=reinterpret_cast<uintptr_t>(fixture::normal)-1;
    EHREOSPlatformSilentLoginTrampolineRVA=reinterpret_cast<uintptr_t>(silent)-1;
    getter.store(result);getterMetadata.store(&metadata);prepareStatus.store(EHR_RUNTIME_OK);
    ehr_native_eos_platform_login_observer(&owner,&info,&metadata);
    check(normalCalls==1);check(!ehr_auth_retry::eligible(&owner,true));
    // Different result and unavailable observation still forward exactly once.
    code=7003;shouldBeEligible=false;ehr_native_eos_platform_login_observer(&owner,&info,&metadata);
    code=7000;getterThrows=true;ehr_native_eos_platform_login_observer(&owner,&info,&metadata);getterThrows=false;
    ehr_native_eos_platform_login_observer(&owner,nullptr,&metadata);
    check(normalCalls==4);check(!ehr_auth_retry::eligible(&owner,true));
    // A silent callback clears eligibility only within its original call.
    {ehr_auth_retry::Scope outer(&owner,true,true,7000);
        ehr_native_eos_silent_login_observer(&owner,&info,&metadata);
        check(ehr_auth_retry::eligible(&owner,true));
    }
    check(silentCalls==1);check(!ehr_auth_retry::eligible(&owner,true));
    // Native exceptions propagate; RAII restores the caller's exact context.
    bool raised=false;shouldBeEligible=true;originalThrows=true;
    {ehr_auth_retry::Scope outer(&other,true,true,7000);
        try{ehr_native_eos_platform_login_observer(&owner,&info,&metadata);}catch(const std::runtime_error &){raised=true;}
        check(ehr_auth_retry::eligible(&other,true));check(!ehr_auth_retry::eligible(&owner,true));
    }
    check(raised);check(normalCalls==5);check(!ehr_auth_retry::eligible(&other,true));
    printf("{\"pass\":%s,\"checks\":%u,\"normalForwards\":%u,\"silentForwards\":%u,\"records\":%u,\"authRequests\":0,\"gameAccountCalls\":0}\n",failed?"false":"true",checks,normalCalls,silentCalls,records);
    return failed?1:0;
}}
