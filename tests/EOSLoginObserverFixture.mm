#import <Foundation/Foundation.h>
#include <cstring>
#include <stdexcept>
#include <thread>
#include "../native/EHREOSLoginDiagnostics.mm"

// Entirely original objects and callbacks. No game image or account is loaded.
namespace fixture {
struct OwnInfo { int32_t result; uint64_t untouchedA; void *untouchedB; };
uint64_t checks = 0, failures = 0, originals[2]{}, getterCalls = 0, sinks = 0;
bool available = false, throwSink = false, throwOriginal = false;
uint32_t phase = 0; int32_t result = 0, status = -1; uint64_t count = 0;
void *expectedSelf = nullptr, *expectedInfo = nullptr;
const void *expectedMethod = nullptr;
const void *getterMethod = reinterpret_cast<const void *>(0x1234);
void check(bool value) { ++checks; if (!value) ++failures; }
int32_t ownGetter(const void *info, const void *metadata) {
    check(metadata == getterMethod); ++getterCalls;
    return static_cast<const OwnInfo *>(info)->result;
}
void normal(void *self, void *info, const void *metadata) {
    ++originals[0]; check(self == expectedSelf); check(info == expectedInfo); check(metadata == expectedMethod);
    if (throwOriginal) throw std::runtime_error("own original failure");
}
void silent(void *self, void *info, const void *metadata) {
    ++originals[1]; check(self == expectedSelf); check(info == expectedInfo); check(metadata == expectedMethod);
}
}

uintptr_t EHREOSPlatformLoginTrampolineRVA = 0;
uintptr_t EHREOSPlatformSilentLoginTrampolineRVA = 0;
extern "C" uintptr_t EHRNativeHooksImageBaseForDiagnostics(void) {
    return reinterpret_cast<uintptr_t>(fixture::ownGetter) - 0x1aae088;
}
extern "C" EHRRuntimeStatus ehr_runtime_find_class(const char *image, const char *ns,
    const char *name, EHRRuntimeToken *token) {
    using namespace fixture;
    if (!available) return EHR_RUNTIME_NOT_READY;
    if (!strcmp(image,"Assembly-CSharp.dll") && !strcmp(ns,"") && !strcmp(name,"EOSManager")) *token=1;
    else if (!strcmp(image,"Assembly-CSharp-firstpass.dll") && !strcmp(ns,"Epic.OnlineServices.Connect") && !strcmp(name,"LoginCallbackInfo")) *token=2;
    else return EHR_RUNTIME_TYPE_MISMATCH;
    return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_find_method(EHRRuntimeToken owner, const char *name,
    const char *const *params, size_t count, const char *returns, int isStatic, EHRRuntimeToken *token) {
    if (isStatic) return EHR_RUNTIME_TYPE_MISMATCH;
    if (owner==1 && count==1 && params && !strcmp(params[0],"Epic.OnlineServices.Connect.LoginCallbackInfo&") && !strcmp(returns,"System.Void")) {
        if (!strcmp(name,"EOSConnectPlatformLoginCallback")) *token=3;
        else if (!strcmp(name,"EOSConnectPlatformSilentLoginCallback")) *token=4;
        else return EHR_RUNTIME_NOT_FOUND;
    } else if (owner==2 && count==0 && !params && !strcmp(name,"get_ResultCode") && !strcmp(returns,"Epic.OnlineServices.Result")) *token=5;
    else return EHR_RUNTIME_TYPE_MISMATCH;
    return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_validate_native_method(EHRRuntimeToken token, uint64_t expected, uint64_t *observed) {
    const uint64_t actual = token==3 ? 0x1b10078 : token==4 ? 0x1b137d0 : token==5 ? 0x1aae088 : 0;
    *observed=actual;
    return expected==actual && actual ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH;
}
EHRRuntimeStatus EHRRuntimeBorrowMethod(EHRRuntimeToken token, const void **method, const void **owner) {
    if (token!=5) return EHR_RUNTIME_BAD_ARGUMENT;
    *method=fixture::getterMethod; *owner=reinterpret_cast<const void *>(0x5678); return EHR_RUNTIME_OK;
}
void EHRRuntimeDiagnosticsRecordEOSLogin(uint32_t phase, int32_t result, int32_t status, uint64_t count) {
    ++fixture::sinks;
    if (fixture::throwSink) throw std::runtime_error("own optional writer failure");
    fixture::phase=phase; fixture::result=result; fixture::status=status; fixture::count=count;
}

int main() { @autoreleasepool {
    using namespace fixture;
    const auto base=EHRNativeHooksImageBaseForDiagnostics();
    EHREOSPlatformLoginTrampolineRVA=reinterpret_cast<uintptr_t>(fixture::normal)-base;
    EHREOSPlatformSilentLoginTrampolineRVA=reinterpret_cast<uintptr_t>(fixture::silent)-base;
    OwnInfo info{7007, 0xabcdef, reinterpret_cast<void *>(0x9876)};
    expectedSelf=&info; expectedInfo=&info; expectedMethod=reinterpret_cast<const void *>(0x1111);
    check(EHREOSLoginDiagnosticsPrepare()==EHR_RUNTIME_NOT_READY);
    ehr_native_eos_platform_login_observer(expectedSelf,expectedInfo,expectedMethod);
    check(originals[0]==1 && getterCalls==0 && status==EHR_RUNTIME_NOT_READY && result==0 && count==1);
    available=true; check(EHREOSLoginDiagnosticsPrepare()==EHR_RUNTIME_OK);
    check(EHREOSLoginDiagnosticsPrepare()==EHR_RUNTIME_OK);
    ehr_native_eos_platform_login_observer(expectedSelf,expectedInfo,expectedMethod);
    check(originals[0]==2 && getterCalls==1 && phase==1 && result==7007 && status==0 && count==2);
    check(info.untouchedA==0xabcdef && info.untouchedB==reinterpret_cast<void *>(0x9876) && info.result==7007);
    info.result=0; ehr_native_eos_silent_login_observer(expectedSelf,expectedInfo,expectedMethod);
    check(originals[1]==1 && getterCalls==2 && phase==2 && result==0 && status==0 && count==1);
    info.result=-123456; ehr_native_eos_platform_login_observer(expectedSelf,expectedInfo,expectedMethod);
    check(result==-123456 && status==0);
    expectedInfo=nullptr; ehr_native_eos_silent_login_observer(expectedSelf,nullptr,expectedMethod);
    check(originals[1]==2 && getterCalls==3 && status==EHR_RUNTIME_BAD_ARGUMENT && result==0);
    expectedInfo=&info; throwSink=true;
    ehr_native_eos_platform_login_observer(expectedSelf,expectedInfo,expectedMethod);
    check(originals[0]==4); throwSink=false;
    throwOriginal=true; bool raised=false;
    try { ehr_native_eos_platform_login_observer(expectedSelf,expectedInfo,expectedMethod); }
    catch (const std::runtime_error &) { raised=true; }
    check(raised && originals[0]==5); throwOriginal=false;
    int32_t workerStatus=0;
    std::thread worker([&]{workerStatus=EHREOSLoginDiagnosticsPrepare();}); worker.join();
    check(workerStatus==EHR_RUNTIME_WRONG_THREAD);
    printf("{\"pass\":%s,\"checks\":%llu,\"originalNormal\":%llu,\"originalSilent\":%llu,\"getterCalls\":%llu,\"gameAuthCalls\":0,\"networkRequests\":0,\"suppressed\":0}\n",
        failures?"false":"true",static_cast<unsigned long long>(checks),static_cast<unsigned long long>(originals[0]),
        static_cast<unsigned long long>(originals[1]),static_cast<unsigned long long>(getterCalls));
    return failures?1:0;
} }
