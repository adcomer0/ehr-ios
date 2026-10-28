// Production predispatch code with own synthetic metadata/API functions only.
// This does not validate an installed game site, run source, or load any game.
#include "EHRNativePatchThunks.mm"
#include <cstdio>
#include <set>
#include <stdexcept>
#include <thread>
#define CHECK(x) do{++checks;if(!(x)){std::fprintf(stderr,"line %d\n",__LINE__);return 1;}}while(0)
struct OwnObject{const void*klass;};
static int ownerClass=0,otherClass=0,stringClass=0,scalarClass=0;
static size_t rooted=0,released=0,dispatched=0,observed=0;static int observerMode=0;
static std::set<uint64_t> live;
struct OwnedRaised{};struct FallbackRaised{EHRRuntimeStatus status;};
static OwnObject raisedIdentity{&otherClass};
static uint64_t owned(){auto value=++rooted;if(!live.insert(value).second)abort();return value;}
static int32_t observer(uint64_t target,uint32_t*words,size_t count){++observed;
 if(observerMode==1)throw std::runtime_error("owned synthetic observer failure");
 if(observerMode==2)@throw [NSException exceptionWithName:@"OwnedFixture" reason:nil userInfo:nil];
 if(count!=12)return 4;uint32_t value[12]={1,12,1,0,uint32_t(target),uint32_t(target>>32),7,89,0,1,6,1};memcpy(words,value,sizeof(value));return 0;}
static int32_t differentObserver(uint64_t,uint32_t*,size_t){return 3;}
extern "C" void *il2cpp_object_get_class(void*p){return const_cast<void*>(static_cast<OwnObject*>(p)->klass);}
extern "C" bool il2cpp_class_is_assignable_from(const void*a,const void*b){return a==b;}
extern "C" void *il2cpp_value_box(const void*,void*){static OwnObject value{&scalarClass};return &value;}
extern "C" void il2cpp_method_get_param_count(){}
extern "C" void il2cpp_method_get_token(){}
extern "C" void il2cpp_method_get_flags(){}
extern "C" void il2cpp_method_get_param(){}
extern "C" void il2cpp_method_get_return_type(){}
extern "C" void il2cpp_class_get_type(){}
extern "C" void il2cpp_class_from_type(){}
extern "C" void il2cpp_type_is_byref(){}
extern "C" void il2cpp_class_is_valuetype(){}
extern "C" void il2cpp_class_is_enum(){}
extern "C" void il2cpp_class_is_blittable(){}
extern "C" void il2cpp_class_has_references(){}
extern "C" void il2cpp_type_get_attrs(){}
extern "C" void il2cpp_object_header_size(){}
extern "C" void il2cpp_method_is_generic(){}
extern "C" void il2cpp_method_is_inflated(){}
extern "C" void il2cpp_class_is_generic(){}
extern "C" void il2cpp_class_is_inflated(){}
extern "C" void il2cpp_field_get_offset(){}
extern "C" void il2cpp_field_get_flags(){}
extern "C" void il2cpp_class_value_size(){}
extern "C" void il2cpp_class_enum_basetype(){}
extern "C" void il2cpp_field_get_type(){}
extern "C" void il2cpp_class_get_fields(){}
extern "C" void il2cpp_object_unbox(){}
extern "C" void il2cpp_field_get_name(){}
extern "C" void il2cpp_type_get_name(){}
extern "C" void il2cpp_free(){}
extern "C" void il2cpp_raise_exception(void *value){if(value!=&raisedIdentity)abort();throw OwnedRaised{};}
EHRRuntimeStatus EHRRuntimeIteratorBorrow(EHRRuntimeToken token,void **value){*value=live.count(token)?&raisedIdentity:nullptr;return *value?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;}
void EHRRuntimeIteratorRaise(EHRRuntimeStatus status){throw FallbackRaised{status};}
EHRRuntimeStatus EHRRuntimeBorrowClass(EHRRuntimeToken token,const void**klass){*klass=token==1?&ownerClass:nullptr;return *klass?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;}
EHRRuntimeStatus EHRRuntimeActionRootBorrowed(void*object,EHRRuntimeToken*token){*token=object?owned():0;return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_release(EHRRuntimeToken token){if(token){if(live.erase(token)!=1)abort();++released;}return EHR_RUNTIME_OK;}
extern "C" int32_t ehr_source_patch_dispatch_v2(uint64_t,uint64_t,const uint64_t*,size_t,uint64_t*returned,uint64_t*error,uint64_t*refs,size_t,EHRManagedPatchDispatchProofV2*proof,size_t){++dispatched;*returned=owned();*error=owned();refs[0]=owned();*proof={2,32,1,1,1,1,1,1};return 6;}
int main(){@autoreleasepool {size_t checks=0;
 const EHRNativePatchTypeV1 voidType{"System.Void",0,0,1,0,nullptr,nullptr,0},boolean{"System.Boolean",2,1,1,4,nullptr,nullptr,0},text{"System.String",1,8,8,1,nullptr,nullptr,0};
 const EHRNativePatchParameterV1 parameters[]{{&boolean,1},{&text,0}};
 const EHRNativePatchSiteV1 site{42,4096,0x6000001,1,nullptr,nullptr,nullptr,nullptr,&voidType,parameters,2,true};
 Prepared value{};value.site=&site;value.signature.owner_class=1;value.classes={&scalarClass,&stringClass};
 prepared.emplace(42,std::make_shared<const Prepared>(value));
 bool scalar=false;OwnObject wrong{&otherClass},good{&ownerClass},badText{&otherClass};void*textValue=&badText;
 const EHRNativePatchArgumentV1 arguments[]{{&scalar,sizeof(scalar),nullptr},{&textValue,sizeof(textValue),nullptr}};
 auto outcome=EHRNativePatchInvokePrepared(site,nullptr,arguments,2,nullptr,0);auto snapshot=ehr_diagnostics::state().snapshot();
 CHECK(outcome.status==EHR_RUNTIME_TYPE_MISMATCH&&!outcome.dispatcher_entered&&snapshot.routes[0].last_phase==10&&snapshot.routes[0].last_argument==0);
 outcome=EHRNativePatchInvokePrepared(site,&wrong,arguments,2,nullptr,0);snapshot=ehr_diagnostics::state().snapshot();
 CHECK(outcome.status==EHR_RUNTIME_TYPE_MISMATCH&&!outcome.dispatcher_entered&&snapshot.routes[0].last_phase==12&&snapshot.routes[0].last_argument==0);
 outcome=EHRNativePatchInvokePrepared(site,&good,arguments,2,nullptr,0);snapshot=ehr_diagnostics::state().snapshot();
 CHECK(outcome.status==EHR_RUNTIME_TYPE_MISMATCH&&!outcome.dispatcher_entered&&snapshot.routes[0].last_phase==13&&snapshot.routes[0].last_argument==2);
 CHECK(snapshot.failure_count==3&&snapshot.failures[2].detail==(13u|(2u<<16)));CHECK(rooted==released&&rooted==2&&dispatched==0);
 CHECK(live.empty());CHECK(EHRNativePatchBindFailureDiagnostics(nullptr)==EHR_RUNTIME_BAD_ARGUMENT);
 CHECK(EHRNativePatchBindFailureDiagnostics(observer)==EHR_RUNTIME_OK);CHECK(EHRNativePatchBindFailureDiagnostics(observer)==EHR_RUNTIME_OK);
 CHECK(EHRNativePatchBindFailureDiagnostics(differentObserver)==EHR_RUNTIME_BAD_ARGUMENT);
 int workerStatus=0;std::thread worker([&]{workerStatus=EHRNativePatchBindFailureDiagnostics(observer);});worker.join();CHECK(workerStatus==EHR_RUNTIME_WRONG_THREAD);
 OwnObject validText{&stringClass};textValue=&validText;
 for(observerMode=0;observerMode<3;++observerMode){
  outcome=EHRNativePatchInvokePrepared(site,&good,arguments,2,nullptr,0);
  CHECK(outcome.status==6&&outcome.dispatcher_entered&&outcome.exception!=0&&outcome.proof.original_attempted==1&&outcome.proof.hook_consumptions==1);
  CHECK(live.size()==1&&live.count(outcome.exception)==1);
  bool caught=false;try{EHRNativePatchFinish(outcome);}catch(const OwnedRaised&){caught=true;}
  CHECK(caught&&live.empty()&&rooted==released);
 }
 CHECK(dispatched==3&&observed==3);snapshot=ehr_diagnostics::state().snapshot();CHECK(snapshot.detail_total==1&&snapshot.details[0].callback==89&&snapshot.details[0].original_entered==1);
 EHRNativeRaiseOwnedFailure(EHR_RUNTIME_OK,0);CHECK(live.empty());
 bool fallback=false;try{EHRNativeRaiseOwnedFailure(EHR_RUNTIME_TYPE_MISMATCH,0);}catch(const FallbackRaised&error){fallback=error.status==EHR_RUNTIME_TYPE_MISMATCH;}
 CHECK(fallback&&live.empty());
 const auto exception=owned();bool native=false;try{EHRNativeRaiseOwnedFailure(EHR_RUNTIME_MANAGED_EXCEPTION,exception);}catch(const OwnedRaised&){native=true;}
 CHECK(native&&live.empty()&&rooted==released&&dispatched==3&&observed==3);

 std::printf("{\"pass\":true,\"checks\":%zu,\"gameLoaded\":false,\"sourceCalls\":%zu}\n",checks,size_t(0));return 0;
}}
