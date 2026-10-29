#import <Foundation/Foundation.h>
#include <cstring>
#include <stdexcept>
#include <thread>
#include "../native/EHRAuthHandoffDiagnostics.mm"

namespace fixture {
struct OwnCredentials { void *untouched; int32_t type; };
uint64_t checks=0,failures=0,credentialCalls=0,loginCalls=0,setCalls=0,getterCalls=0;
bool available=false,badPin=false,throwGetter=false,throwObjCGetter=false,throwLogin=false,throwObjCLogin=false,throwCredential=false,nested=false;
void *expectedSelf=nullptr,*expectedOptions=nullptr,*expectedData=nullptr,*expectedCallback=nullptr;
void *expectedSetSelf=nullptr,*expectedCredentials=nullptr;
const void *expectedMethod=nullptr,*expectedSetMethod=nullptr;
const void *getterMethod=reinterpret_cast<const void *>(0x1234);
void check(bool value) {++checks;if(!value)++failures;}
int32_t scalar(const void *value,const void *metadata) {
    ++getterCalls;check(metadata==getterMethod);
    if(throwGetter) throw std::runtime_error("owned scalar fixture");
    if(throwObjCGetter) @throw [NSException exceptionWithName:@"OwnedFixture" reason:nil userInfo:nil];
    return static_cast<const OwnCredentials *>(value)->type;
}
void ownSet(void *self,void *value,const void *metadata) {
    ++setCalls;check(self==expectedSetSelf);check(value==expectedCredentials);check(metadata==expectedSetMethod);
}
void ownCredentials(void *self,void *value,const void *metadata) {
    ++credentialCalls;check(self==expectedSelf);check(value==expectedCredentials);check(metadata==expectedMethod);
    if(throwCredential) throw std::runtime_error("owned original credential callback");
}
void ownLogin(void *self,void *options,void *data,void *callback,const void *metadata) {
    ++loginCalls;check(self==expectedSelf);check(options==expectedOptions);check(data==expectedData);
    check(callback==expectedCallback);check(metadata==expectedMethod);
    ehr_native_auth_handoff_set(expectedSetSelf,expectedCredentials,expectedSetMethod);
    if(nested) {
        nested=false;ehr_native_auth_handoff_login(self,options,data,callback,metadata);
        ehr_native_auth_handoff_set(expectedSetSelf,expectedCredentials,expectedSetMethod);
    }
    if(throwLogin) throw std::runtime_error("owned original login");
    if(throwObjCLogin) @throw [NSException exceptionWithName:@"OwnedOriginal" reason:nil userInfo:nil];
}
uint64_t number(NSDictionary *dictionary,NSString *key) {return [dictionary[key] unsignedLongLongValue];}
void checkEventShape(NSDictionary *snapshot) {
    NSArray *events=snapshot[@"events"];
    check([events isKindOfClass:NSArray.class]);check(events.count<=32);
    check(events.count==number(snapshot,@"eventCount"));check(number(snapshot,@"eventCapacity")==32);
    NSSet *keys=[NSSet setWithArray:@[@"sequence",@"monotonicNs",@"phase",@"status",@"scalarValue",@"loginScopeSerial"]];
    uint64_t sequence=0,time=0;
    for(NSDictionary *event in events) {
        check([[NSSet setWithArray:event.allKeys] isEqualToSet:keys]);
        for(id value in event.allValues) check([value isKindOfClass:NSNumber.class]);
        check(number(event,@"sequence")>sequence);check(number(event,@"monotonicNs")>=time);
        check(number(event,@"monotonicNs")>0);check(number(event,@"phase")<8);
        sequence=number(event,@"sequence");time=number(event,@"monotonicNs");
    }
    if(events.count) check(sequence==number(snapshot,@"phaseSequence"));
}
}
uintptr_t EHRAuthHandoffCredentialsTrampolineRVA=0,EHRAuthHandoffLoginTrampolineRVA=0,EHRAuthHandoffSetTrampolineRVA=0;
extern "C" uintptr_t EHRNativeHooksImageBaseForDiagnostics(void) {
    return reinterpret_cast<uintptr_t>(fixture::scalar)-EHRAuthHandoffCredentialTypeGetterRVA;
}
extern "C" EHRRuntimeStatus ehr_runtime_find_class(const char *image,const char *space,const char *name,EHRRuntimeToken *out) {
    if(!fixture::available) return EHR_RUNTIME_NOT_READY;
    if(!strcmp(image,"Assembly-CSharp.dll") && !strcmp(space,"") && !strcmp(name,"EOSManager")) *out=1;
    else if(!strcmp(image,"Assembly-CSharp-firstpass.dll") && !strcmp(space,"Epic.OnlineServices.Connect")) {
        if(!strcmp(name,"ConnectInterface")) *out=2;
        else if(!strcmp(name,"CredentialsInternal")) *out=3;
        else if(!strcmp(name,"Credentials")) *out=4;
        else return EHR_RUNTIME_NOT_FOUND;
    } else return EHR_RUNTIME_TYPE_MISMATCH;
    return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_find_method(EHRRuntimeToken owner,const char *name,const char *const *parameters,
    size_t count,const char *returns,int isStatic,EHRRuntimeToken *out) {
    if(isStatic) return EHR_RUNTIME_TYPE_MISMATCH;
    if(owner==1 && !strcmp(name,"OnGetCredentials") && !strcmp(returns,"System.Void") && count==1 && parameters &&
        !strcmp(parameters[0],"AppleAuth.Interfaces.ICredential")) *out=10;
    else if(owner==2 && !strcmp(name,"Login") && !strcmp(returns,"System.Void") && count==3 && parameters &&
        !strcmp(parameters[0],"Epic.OnlineServices.Connect.LoginOptions&") && !strcmp(parameters[1],"System.Object") &&
        !strcmp(parameters[2],"Epic.OnlineServices.Connect.OnLoginCallback")) *out=11;
    else if(owner==3 && !strcmp(name,"Set") && !strcmp(returns,"System.Void") && count==1 && parameters &&
        !strcmp(parameters[0],"Epic.OnlineServices.Connect.Credentials&")) *out=12;
    else if(owner==4 && !strcmp(name,"get_Type") && !strcmp(returns,"Epic.OnlineServices.ExternalCredentialType") && !count && !parameters) *out=13;
    else return EHR_RUNTIME_TYPE_MISMATCH;
    return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_validate_native_method(EHRRuntimeToken token,uint64_t rva,uint64_t *observed) {
    const uint64_t expected=token==10?0x1b15150:token==11?0x1aab220:token==12?0x1aad608:token==13?0x1aad5f8:0;
    *observed=expected;
    return expected && expected==rva && !fixture::badPin?EHR_RUNTIME_OK:EHR_RUNTIME_TYPE_MISMATCH;
}
EHRRuntimeStatus EHRRuntimeBorrowMethod(EHRRuntimeToken token,const void **method,const void **owner) {
    if(token!=13) return EHR_RUNTIME_BAD_ARGUMENT;
    *method=fixture::getterMethod;*owner=reinterpret_cast<const void *>(0x4321);return EHR_RUNTIME_OK;
}
int main() { @autoreleasepool {
    using namespace fixture;
    const auto base=EHRNativeHooksImageBaseForDiagnostics();
    EHRAuthHandoffCredentialsTrampolineRVA=reinterpret_cast<uintptr_t>(ownCredentials)-base;
    EHRAuthHandoffLoginTrampolineRVA=reinterpret_cast<uintptr_t>(ownLogin)-base;
    EHRAuthHandoffSetTrampolineRVA=reinterpret_cast<uintptr_t>(ownSet)-base;
    OwnCredentials value{reinterpret_cast<void *>(0x9876),11};int self=1,options=2,data=3,callback=4,setSelf=5;
    expectedSelf=&self;expectedOptions=&options;expectedData=&data;expectedCallback=&callback;
    expectedSetSelf=&setSelf;expectedCredentials=&value;expectedMethod=&options;expectedSetMethod=&data;
    check(EHRAuthHandoffDiagnosticsPrepare()==EHR_RUNTIME_NOT_READY);
    ehr_native_auth_handoff_login(expectedSelf,expectedOptions,expectedData,expectedCallback,expectedMethod);
    check(loginCalls==1 && setCalls==1 && getterCalls==0);
    auto snapshot=EHRAuthHandoffDiagnosticsCopyStatus();check([snapshot[@"lastTypeStatus"] intValue]==EHR_RUNTIME_NOT_READY);
    available=true;badPin=true;check(EHRAuthHandoffDiagnosticsPrepare()==EHR_RUNTIME_TYPE_MISMATCH);badPin=false;
    check(EHRAuthHandoffDiagnosticsPrepare()==0);check(EHRAuthHandoffDiagnosticsPrepare()==0);
    EHRAuthHandoffDiagnosticsRecordAppleSuccess();
    ehr_native_auth_handoff_credentials(expectedSelf,expectedCredentials,expectedMethod);
    ehr_native_auth_handoff_login(expectedSelf,expectedOptions,expectedData,expectedCallback,expectedMethod);
    EHRAuthHandoffDiagnosticsRecordEOSResult(1,0,7000);
    snapshot=EHRAuthHandoffDiagnosticsCopyStatus();
    check(number(snapshot,@"appleSuccesses")==1);check(number(snapshot,@"managedCredentialEntries")==1);
    check(number(snapshot,@"managedCredentialReturns")==1);check(number(snapshot,@"lastCredentialType")==11);
    check(number(snapshot,@"lastTypeStatus")==0);check(number(snapshot,@"normalEOSResultCode")==7000);
    check(number(snapshot,@"appleSuccessSequence")<number(snapshot,@"managedCredentialEntrySequence"));
    check(number(snapshot,@"managedCredentialReturnSequence")<number(snapshot,@"loginEntrySequence"));
    check(number(snapshot,@"typeSequence")<number(snapshot,@"normalEOSSequence"));
    check(value.untouched==reinterpret_cast<void *>(0x9876) && value.type==11);
    // Reproduce the last-only ambiguity: the original Apple type11 must remain
    // in history after the later owned type10 fallback replaces lastType.
    value.type=10;
    ehr_native_auth_handoff_login(expectedSelf,expectedOptions,expectedData,expectedCallback,expectedMethod);
    snapshot=EHRAuthHandoffDiagnosticsCopyStatus();checkEventShape(snapshot);
    check(number(snapshot,@"lastCredentialType")==10);
    uint64_t appleTypeSequence=0,deviceTypeSequence=0,appleScope=0,deviceScope=0;
    for(NSDictionary *event in snapshot[@"events"]) {
        if(number(event,@"phase")==CredentialType && [event[@"status"] intValue]==0) {
            if([event[@"scalarValue"] intValue]==11) {appleTypeSequence=number(event,@"sequence");appleScope=number(event,@"loginScopeSerial");}
            if([event[@"scalarValue"] intValue]==10) {deviceTypeSequence=number(event,@"sequence");deviceScope=number(event,@"loginScopeSerial");}
        }
    }
    check(appleTypeSequence && appleTypeSequence<number(snapshot,@"normalEOSSequence"));
    check(number(snapshot,@"normalEOSSequence")<deviceTypeSequence);check(appleScope && deviceScope && appleScope!=deviceScope);
    value.type=11;
    auto oldGets=getterCalls;ehr_native_auth_handoff_set(expectedSetSelf,expectedCredentials,expectedSetMethod);
    check(getterCalls==oldGets && number(EHRAuthHandoffDiagnosticsCopyStatus(),@"outOfScopeSetForwards")==1);
    nested=true;auto oldLogins=loginCalls;oldGets=getterCalls;
    const auto beforeNested=number(EHRAuthHandoffDiagnosticsCopyStatus(),@"phaseSequence");
    ehr_native_auth_handoff_login(expectedSelf,expectedOptions,expectedData,expectedCallback,expectedMethod);
    check(loginCalls==oldLogins+2 && getterCalls==oldGets+3 && loginDepth==0 && loginScopeSerial==0);
    NSMutableArray<NSDictionary *> *nestedEvents=[NSMutableArray new];
    for(NSDictionary *event in EHRAuthHandoffDiagnosticsCopyStatus()[@"events"])
        if(number(event,@"sequence")>beforeNested) [nestedEvents addObject:event];
    check(nestedEvents.count==7);
    const auto outerScope=number(nestedEvents[0],@"loginScopeSerial"),innerScope=number(nestedEvents[2],@"loginScopeSerial");
    check(outerScope && innerScope && outerScope!=innerScope);
    for(size_t i=0;i<7;++i) check(number(nestedEvents[i],@"loginScopeSerial")==((i>=2 && i<=4)?innerScope:outerScope));
    throwGetter=true;oldGets=getterCalls;auto oldSets=setCalls;
    ehr_native_auth_handoff_login(expectedSelf,expectedOptions,expectedData,expectedCallback,expectedMethod);
    check(setCalls==oldSets+1 && getterCalls==oldGets+1);throwGetter=false;
    throwObjCGetter=true;oldSets=setCalls;
    ehr_native_auth_handoff_login(expectedSelf,expectedOptions,expectedData,expectedCallback,expectedMethod);
    check(setCalls==oldSets+1);throwObjCGetter=false;
    throwLogin=true;bool raised=false;
    try {ehr_native_auth_handoff_login(expectedSelf,expectedOptions,expectedData,expectedCallback,expectedMethod);}
    catch(const std::runtime_error &) {raised=true;}
    check(raised && loginDepth==0 && number(EHRAuthHandoffDiagnosticsCopyStatus(),@"activeLoginCalls")==0);throwLogin=false;
    throwObjCLogin=true;raised=false;
    @try {ehr_native_auth_handoff_login(expectedSelf,expectedOptions,expectedData,expectedCallback,expectedMethod);}
    @catch(NSException *error) {raised=[error.name isEqualToString:@"OwnedOriginal"];}
    check(raised && loginDepth==0 && number(EHRAuthHandoffDiagnosticsCopyStatus(),@"activeLoginCalls")==0);throwObjCLogin=false;
    throwCredential=true;raised=false;
    try {ehr_native_auth_handoff_credentials(expectedSelf,expectedCredentials,expectedMethod);}
    catch(const std::runtime_error &) {raised=true;}
    check(raised);throwCredential=false;
    expectedCredentials=nullptr;oldGets=getterCalls;oldSets=setCalls;
    ehr_native_auth_handoff_login(expectedSelf,expectedOptions,expectedData,expectedCallback,expectedMethod);
    check(getterCalls==oldGets && setCalls==oldSets+1);expectedCredentials=&value;
    check([EHRAuthHandoffDiagnosticsCopyStatus()[@"lastTypeStatus"] intValue]==EHR_RUNTIME_BAD_ARGUMENT);
    int32_t workerPrepare=0;oldGets=getterCalls;
    std::thread worker([&]{@autoreleasepool {
        workerPrepare=EHRAuthHandoffDiagnosticsPrepare();
        ehr_native_auth_handoff_login(expectedSelf,expectedOptions,expectedData,expectedCallback,expectedMethod);
        check(EHRAuthHandoffDiagnosticsCopyStatus()!=nil);
    }});worker.join();check(workerPrepare==EHR_RUNTIME_WRONG_THREAD && getterCalls==oldGets);
    EHRAuthHandoffDiagnosticsRecordEOSResult(2,EHR_RUNTIME_NOT_READY,7000);
    snapshot=EHRAuthHandoffDiagnosticsCopyStatus();check(number(snapshot,@"silentEOSResultCode")==0);
    check(number(snapshot,@"silentEOSStatus")==EHR_RUNTIME_NOT_READY);
    NSDictionary *unknown=[snapshot[@"events"] lastObject];
    check(number(unknown,@"phase")==EOSSilent && number(unknown,@"scalarValue")==0);
    check([unknown[@"status"] intValue]==EHR_RUNTIME_NOT_READY);
    const auto before=number(snapshot,@"phaseSequence");auto proof=EHRAuthHandoffDiagnosticsSelfTest();
    check([proof[@"success"] boolValue] && [proof[@"checks"] intValue]>=80);
    check(number(EHRAuthHandoffDiagnosticsCopyStatus(),@"phaseSequence")==before);
    // The copy is serialized with publishers but performs only owned numeric
    // work. Concurrent readers must always receive a complete ordered ring.
    std::thread reader([&]{for(unsigned i=0;i<50;++i) {@autoreleasepool {
        checkEventShape(EHRAuthHandoffDiagnosticsCopyStatus());
    }}});
    for(unsigned i=0;i<80;++i) EHRAuthHandoffDiagnosticsRecordAppleSuccess();
    reader.join();snapshot=EHRAuthHandoffDiagnosticsCopyStatus();checkEventShape(snapshot);
    check(number(snapshot,@"eventCount")==32);check(number(snapshot,@"eventOverwrites")>0);
    check(number([snapshot[@"events"] firstObject],@"sequence")==number(snapshot,@"phaseSequence")-31);
    printf("{\"pass\":%s,\"checks\":%llu,\"gameAuthCalls\":0,\"networkRequests\":0,\"tokenReads\":0}\n",
        failures?"false":"true",(unsigned long long)checks);
    return failures?1:0;
} }
