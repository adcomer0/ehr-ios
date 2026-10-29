#import <Foundation/Foundation.h>
#include <cstring>
#include <cstdlib>
#include <map>
#include <stdexcept>
#include <thread>
#include "../native/EHRAuthRetryGuard.mm"

namespace fixture {
int eosType, accountType, parentType, wrongType;
struct Object { const void *klass; uint8_t trying; } eos{&eosType,0}, account{&accountType,0}, other{&eosType,0};
struct Field { const char *name; const char *type; uint32_t flags; } instance{"_instance","AccountManager",16}, trying{"tryingToLogin","System.Boolean",0};
bool parentInitialized=true, storagePresent=true, throwFailure=false, badParent=false, gatewayReady=true, parentHasCctor=false;
uint64_t checks=0, failures=0, originalCalls=0, failureCalls=0, nextRoot=100;
const void *retryMetadata=reinterpret_cast<const void *>(0x5555), *failMetadata=reinterpret_cast<const void *>(0x6666);
std::map<uint64_t,void *> roots;
void check(bool value){++checks;if(!value)++failures;}
void ownOriginal(void *self,const void *metadata){check(self==&eos||self==&other);check(metadata==retryMetadata);++originalCalls;}
void ownFailure(void *self,const void *metadata){check(self==&account);check(metadata==failMetadata);check(roots.size()==4);++failureCalls;if(throwFailure)throw std::runtime_error("own failure handler raised");}
const void *parent(const void *klass){return klass==&accountType?&parentType:nullptr;}
const void *methods(const void *,void **iter){if(!parentHasCctor||*iter)return nullptr;*iter=reinterpret_cast<void *>(1);return &wrongType;}
const char *methodName(const void *){return ".cctor";}
const void *classType(const void *klass){return klass==&parentType?(badParent?"WrongParent":"DestroyableSingleton<AccountManager>"):"other";}
char *typeName(const void *type){return strdup(static_cast<const char *>(type));}
void freeName(void *name){free(name);}
void *fields(const void *klass,void **iter){if(*iter)return nullptr;*iter=reinterpret_cast<void *>(1);return klass==&parentType?&instance:klass==&eosType?&trying:nullptr;}
const char *fieldName(void *field){return static_cast<Field *>(field)->name;}
uint32_t fieldFlags(void *field){return static_cast<Field *>(field)->flags;}
const void *fieldType(void *field){return static_cast<Field *>(field)->type;}
const void *fromType(const void *type){return !strcmp(static_cast<const char *>(type),"AccountManager")?&accountType:nullptr;}
bool initialized(const void *){return parentInitialized;}
void staticGet(void *field,void *out){check(field==&instance);*static_cast<void **>(out)=storagePresent?&account:nullptr;}
void instanceGet(void *object,void *field,void *out){check(field==&trying);*static_cast<uint8_t *>(out)=static_cast<Object *>(object)->trying;}
const void *objectClass(void *object){return static_cast<Object *>(object)->klass;}
void *resolve(const char *name){
#define ENTRY(apiName,own) if(!strcmp(name,apiName))return reinterpret_cast<void *>(own)
 ENTRY("il2cpp_class_get_parent",parent);ENTRY("il2cpp_class_get_type",classType);
 ENTRY("il2cpp_class_get_methods",methods);ENTRY("il2cpp_method_get_name",methodName);
 ENTRY("il2cpp_type_get_name",typeName);ENTRY("il2cpp_free",freeName);
 ENTRY("il2cpp_class_get_fields",fields);ENTRY("il2cpp_field_get_name",fieldName);
 ENTRY("il2cpp_field_get_flags",fieldFlags);ENTRY("il2cpp_field_get_type",fieldType);
 ENTRY("il2cpp_class_from_type",fromType);ENTRY("il2cpp_class_is_inited",initialized);
 ENTRY("il2cpp_field_static_get_value",staticGet);ENTRY("il2cpp_field_get_value",instanceGet);
 ENTRY("il2cpp_object_get_class",objectClass);
#undef ENTRY
 return nullptr;
}
}
uintptr_t EHRAuthRetryTrampolineRVA=0;
extern "C" uintptr_t EHRNativeHooksImageBaseForDiagnostics(void){return reinterpret_cast<uintptr_t>(fixture::ownFailure)-0x1b06374;}
namespace ehr_pinned { EHRRuntimeStatus validate_engine_entry(const void *){return EHR_RUNTIME_OK;} }
extern "C" EHRRuntimeStatus ehr_runtime_find_class(const char *image,const char *ns,const char *name,EHRRuntimeToken *out){
 if(!fixture::gatewayReady)return EHR_RUNTIME_NOT_READY;
 if(strcmp(image,"Assembly-CSharp.dll")||strcmp(ns,""))return EHR_RUNTIME_TYPE_MISMATCH;
 if(!strcmp(name,"AccountManager"))*out=1;else if(!strcmp(name,"EOSManager"))*out=2;else return EHR_RUNTIME_NOT_FOUND;return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_find_method(EHRRuntimeToken klass,const char *name,const char *const *params,size_t count,const char *returns,int isStatic,EHRRuntimeToken *out){
 if(params||count||isStatic||strcmp(returns,"System.Void"))return EHR_RUNTIME_TYPE_MISMATCH;
 if(klass==1&&!strcmp(name,"PlatformSignInFail"))*out=3;else if(klass==2&&!strcmp(name,"LoginWithCorrectPlatform"))*out=4;else return EHR_RUNTIME_NOT_FOUND;return EHR_RUNTIME_OK;
}
extern "C" EHRRuntimeStatus ehr_runtime_validate_native_method(EHRRuntimeToken token,uint64_t expected,uint64_t *out){*out=token==3?0x1b06374:token==4?0x1b0fd70:0;return *out==expected&&*out?EHR_RUNTIME_OK:EHR_RUNTIME_TYPE_MISMATCH;}
EHRRuntimeStatus EHRRuntimeBorrowClass(EHRRuntimeToken token,const void **out){*out=token==1?&fixture::accountType:token==2?&fixture::eosType:nullptr;return *out?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;}
EHRRuntimeStatus EHRRuntimeBorrowMethod(EHRRuntimeToken token,const void **out,const void **owner){*out=token==3?fixture::failMetadata:nullptr;*owner=&fixture::accountType;return *out?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;}
EHRRuntimeStatus EHRRuntimeActionRootBorrowed(void *object,EHRRuntimeToken *out){*out=0;if(!fixture::gatewayReady)return EHR_RUNTIME_NOT_READY;*out=++fixture::nextRoot;fixture::roots[*out]=object;return EHR_RUNTIME_OK;}
EHRRuntimeStatus EHRRuntimeIteratorPin(EHRRuntimeToken token,EHRRuntimeToken *out,void **object){auto it=fixture::roots.find(token);if(it==fixture::roots.end())return EHR_RUNTIME_INVALID_TOKEN;*object=it->second;*out=++fixture::nextRoot;fixture::roots[*out]=*object;return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_release(EHRRuntimeToken token){return fixture::roots.erase(token)?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;}

int main(){@autoreleasepool{
 using namespace fixture;
 EHRAuthRetryTrampolineRVA=reinterpret_cast<uintptr_t>(ownOriginal)-EHRNativeHooksImageBaseForDiagnostics();
 check(EHRAuthRetryGuardSetEnabled(1)==EHR_RUNTIME_NOT_READY);
 check(EHRAuthRetryGuardStart(0)==EHR_RUNTIME_OK);check(prepared.load()==EHR_RUNTIME_NOT_READY&&!enabled.load());
 check(EHRAuthRetryGuardStart(2)==EHR_RUNTIME_BAD_ARGUMENT);
 check(EHRAuthRetryGuardStart(1)==EHR_RUNTIME_NOT_READY);check(!enabled.load());
 check([EHRAuthRetryGuardCopyStatus()[@"startupPrepareStatus"] intValue]==EHR_RUNTIME_NOT_READY);
 check([EHRAuthRetryGuardCopyStatus()[@"startupEnableStatus"] intValue]==EHR_RUNTIME_NOT_READY);
 gatewayReady=false;check(prepare(resolve)==EHR_RUNTIME_NOT_READY);gatewayReady=true;
 badParent=true;check(prepare(resolve)==EHR_RUNTIME_TYPE_MISMATCH);badParent=false;
 parentHasCctor=true;check(prepare(resolve)==EHR_RUNTIME_UNSUPPORTED);parentHasCctor=false;
 instance.type="T";check(prepare(resolve)==EHR_RUNTIME_TYPE_MISMATCH);instance.type="AccountManager";
 trying.flags=16;check(prepare(resolve)==EHR_RUNTIME_TYPE_MISMATCH);trying.flags=0;
 check(prepare(resolve)==EHR_RUNTIME_OK);check(EHRAuthRetryGuardStart(1)==EHR_RUNTIME_OK);
 check([EHRAuthRetryGuardCopyStatus()[@"startupRequested"] boolValue]);
 check([EHRAuthRetryGuardCopyStatus()[@"startupPrepareStatus"] intValue]==0);
 check([EHRAuthRetryGuardCopyStatus()[@"startupEnableStatus"] intValue]==0);
 check(EHRAuthRetryGuardSetEnabled(1)==EHR_RUNTIME_OK);
 ehr_native_eos_platform_retry_guard(&eos,retryMetadata);check(originalCalls==1&&failureCalls==0);
 {ehr_auth_retry::Scope scope(&eos,true,true,7000);ehr_native_eos_platform_retry_guard(&eos,retryMetadata);check(failureCalls==1&&originalCalls==1);check(roots.empty());}
 // A later manual action retains original eligibility, without clearing flags.
 ehr_native_eos_platform_retry_guard(&eos,retryMetadata);check(originalCalls==2);
 for(int32_t result:{0,7003,7004}){ehr_auth_retry::Scope scope(&eos,true,true,result);ehr_native_eos_platform_retry_guard(&eos,retryMetadata);}
 check(originalCalls==5&&failureCalls==1);
 {ehr_auth_retry::Scope scope(&other,true,true,7000);ehr_native_eos_platform_retry_guard(&eos,retryMetadata);}check(originalCalls==6);
 {ehr_auth_retry::Scope scope(&eos,true,false,7000);ehr_native_eos_platform_retry_guard(&eos,retryMetadata);}check(originalCalls==7);
 parentInitialized=false;{ehr_auth_retry::Scope scope(&eos,true,true,7000);ehr_native_eos_platform_retry_guard(&eos,retryMetadata);}parentInitialized=true;check(originalCalls==8);
 storagePresent=false;{ehr_auth_retry::Scope scope(&eos,true,true,7000);ehr_native_eos_platform_retry_guard(&eos,retryMetadata);}storagePresent=true;check(originalCalls==9);
 eos.trying=1;{ehr_auth_retry::Scope scope(&eos,true,true,7000);ehr_native_eos_platform_retry_guard(&eos,retryMetadata);}check(originalCalls==10);eos.trying=0;
 // Already-entered genuine failure must propagate: never retry after it throws.
 throwFailure=true;bool raised=false;try{ehr_auth_retry::Scope scope(&eos,true,true,7000);ehr_native_eos_platform_retry_guard(&eos,retryMetadata);}catch(const std::runtime_error &){raised=true;}throwFailure=false;
 check(raised&&failureCalls==2&&originalCalls==10&&roots.empty());check(!ehr_auth_retry::eligible(&eos,true));
 {ehr_auth_retry::Scope outer(&eos,true,true,7000);{ehr_auth_retry::Scope inner(&eos,true,true,0);check(!ehr_auth_retry::eligible(&eos,true));}check(ehr_auth_retry::eligible(&eos,true));}
 int32_t workerStatus=0;std::thread worker([&]{workerStatus=EHRAuthRetryGuardSetEnabled(1);check(EHRAuthRetryGuardStart(1)==EHR_RUNTIME_WRONG_THREAD);ehr_auth_retry::Scope scope(&eos,true,true,7000);ehr_native_eos_platform_retry_guard(&eos,retryMetadata);});worker.join();check(workerStatus==EHR_RUNTIME_WRONG_THREAD&&originalCalls==11&&failureCalls==2);
 check(EHRAuthRetryGuardSetEnabled(0)==0);{ehr_auth_retry::Scope scope(&eos,true,true,7000);ehr_native_eos_platform_retry_guard(&eos,retryMetadata);}check(originalCalls==12&&failureCalls==2);
 check(EHRAuthRetryGuardSetEnabled(1)==0);gatewayReady=false;{ehr_auth_retry::Scope scope(&eos,true,true,7000);ehr_native_eos_platform_retry_guard(&eos,retryMetadata);}gatewayReady=true;check(originalCalls==13&&failureCalls==2&&roots.empty());check(EHRAuthRetryGuardSetEnabled(0)==0);
 NSDictionary *status=EHRAuthRetryGuardCopyStatus();check([status[@"failureHandlerEntries"] unsignedLongLongValue]==2);check([status[@"failureHandlerCompleted"] unsignedLongLongValue]==1);check(roots.empty());
 printf("{\"pass\":%s,\"checks\":%llu,\"failureEntries\":%llu,\"originalForwards\":%llu,\"liveRoots\":%zu,\"gameAccountCalls\":0,\"authRequests\":0}\n",failures?"false":"true",static_cast<unsigned long long>(checks),static_cast<unsigned long long>(failureCalls),static_cast<unsigned long long>(originalCalls),roots.size());return failures?1:0;
}}
