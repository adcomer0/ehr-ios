// Production predispatch code with own synthetic metadata/API functions only.
// This does not validate an installed game site, run source, or load any game.
#include "EHRNativePatchThunks.mm"
#include <cstdio>
#define CHECK(x) do{++checks;if(!(x)){std::fprintf(stderr,"line %d\n",__LINE__);return 1;}}while(0)
struct OwnObject{const void*klass;};
static int ownerClass=0,otherClass=0,stringClass=0,scalarClass=0;
static size_t rooted=0,released=0,dispatched=0;
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
extern "C" void il2cpp_raise_exception(){}
EHRRuntimeStatus EHRRuntimeBorrowClass(EHRRuntimeToken token,const void**klass){*klass=token==1?&ownerClass:nullptr;return *klass?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;}
EHRRuntimeStatus EHRRuntimeActionRootBorrowed(void*object,EHRRuntimeToken*token){*token=object?++rooted:0;return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_release(EHRRuntimeToken token){released+=token!=0;return EHR_RUNTIME_OK;}
extern "C" int32_t ehr_source_patch_dispatch_v2(uint64_t,uint64_t,const uint64_t*,size_t,uint64_t*,uint64_t*,uint64_t*,size_t,EHRManagedPatchDispatchProofV2*,size_t){++dispatched;return 99;}
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
 std::printf("{\"pass\":true,\"checks\":%zu,\"gameLoaded\":false,\"sourceCalls\":%zu}\n",checks,dispatched);return 0;
}}
