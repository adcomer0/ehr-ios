// Actual gateway metadata recorder; synthetic metadata only, no loaded game.
#include "EHRRuntimeGateway.mm"
#include <cstdio>
#include <thread>
#define CHECK(x) do{++checks;if(!(x)){std::fprintf(stderr,"line %d\n",__LINE__);return 1;}}while(0)
struct OwnClass{const char*space;const char*name;OwnClass*parent=nullptr;};
struct OwnObject{OwnClass*klass;};
struct OwnMethod{OwnClass*owner;const char*name;uint32_t token;};
static size_t metadataCalls=0;
static uint32_t throwMetadata=0;
static RuntimeClass* ownClass(Object*o){++metadataCalls;if(throwMetadata==1)throw 7;if(throwMetadata==2)@throw [NSException exceptionWithName:@"OwnMetadataFailure" reason:nil userInfo:nil];return reinterpret_cast<RuntimeClass*>(reinterpret_cast<OwnObject*>(o)->klass);}
static const char* ownName(RuntimeClass*c){++metadataCalls;return reinterpret_cast<OwnClass*>(c)->name;}
static const char* ownSpace(RuntimeClass*c){++metadataCalls;return reinterpret_cast<OwnClass*>(c)->space;}
static RuntimeClass* ownParent(RuntimeClass*c){++metadataCalls;return reinterpret_cast<RuntimeClass*>(reinterpret_cast<OwnClass*>(c)->parent);}
static uint32_t ownToken(const Method*m){++metadataCalls;return reinterpret_cast<const OwnMethod*>(m)->token;}
static const char* ownMethodName(const Method*m){++metadataCalls;return reinterpret_cast<const OwnMethod*>(m)->name;}
static RuntimeClass* ownOwner(const Method*m){++metadataCalls;return reinterpret_cast<RuntimeClass*>(reinterpret_cast<const OwnMethod*>(m)->owner);}
int main(){@autoreleasepool{size_t checks=0;auto&s=state();auto&a=s.api;
 a.object_get_class=ownClass;a.class_get_name=ownName;a.class_get_namespace=ownSpace;a.class_get_parent=ownParent;
 a.method_get_token=ownToken;a.method_get_name=ownMethodName;a.method_get_declaring_type=ownOwner;
 OwnClass owner{"UnityEngine","GameObject"},error{"System","NullReferenceException"};OwnObject raised{&error};OwnMethod method{&owner,"SetActive",0x60000ab};
 ehr_diagnostics::context={42,4096,33,15,0};recordNativeException(reinterpret_cast<Method*>(&method),reinterpret_cast<Exception*>(&raised));
 auto proof=ehr_diagnostics::state().snapshot();CHECK(proof.detail_total==1&&proof.detail_count==1);auto value=proof.details[0];
 CHECK(value.kind==2&&value.status==EHR_RUNTIME_MANAGED_EXCEPTION&&value.target==42&&value.rva==4096&&value.iterator==33);
 CHECK(value.method_token==0x60000ab&&value.exception_kind==1&&value.owner_hash==diagnosticNameHash(nullptr,"UnityEngine.GameObject")&&value.method_hash==diagnosticNameHash(nullptr,"SetActive"));
 const char*names[]={"NullReferenceException","ArgumentException","InvalidOperationException","IndexOutOfRangeException","MissingMethodException","NotSupportedException","TypeLoadException","InvalidCastException","ObjectDisposedException","ArgumentNullException","ArgumentOutOfRangeException","Exception"};
 const uint32_t kinds[]={1,3,4,5,6,7,8,9,10,11,12,13};
 for(size_t i=0;i<12;++i){error.name=names[i];CHECK(diagnosticExceptionKind(a,reinterpret_cast<Object*>(&raised))==kinds[i]);}
 error.space="UnityEngine";error.name="MissingReferenceException";CHECK(diagnosticExceptionKind(a,reinterpret_cast<Object*>(&raised))==2);
 OwnClass parent{"System","ArgumentException"};error={"Own","Derived",&parent};CHECK(diagnosticExceptionKind(a,reinterpret_cast<Object*>(&raised))==3);
 error={"Own","Unknown"};CHECK(diagnosticExceptionKind(a,reinterpret_cast<Object*>(&raised))==0);
 CHECK(diagnosticNameHash(nullptr,"hello")==UINT64_C(0xa430d84680aabd0b));CHECK(diagnosticNameHash("A","B")==diagnosticNameHash(nullptr,"A.B"));
 char longName[514];memset(longName,'x',513);longName[513]=0;CHECK(diagnosticNameHash(nullptr,longName)==0);CHECK(diagnosticNameHash(nullptr,nullptr)==0);CHECK(diagnosticNameHash(nullptr,"")==0);
 auto calls=metadataCalls;std::thread worker([&]{recordNativeException(reinterpret_cast<Method*>(&method),reinterpret_cast<Exception*>(&raised));});worker.join();CHECK(metadataCalls==calls&&ehr_diagnostics::state().snapshot().detail_total==1);
 for(uint32_t mode:{1u,2u}){throwMetadata=mode;recordNativeException(reinterpret_cast<Method*>(&method),reinterpret_cast<Exception*>(&raised));CHECK(ehr_diagnostics::state().snapshot().detail_total==1&&s.roots.empty());}throwMetadata=0;
 for(size_t i=0;i<50;++i)recordNativeException(reinterpret_cast<Method*>(&method),reinterpret_cast<Exception*>(&raised));
 proof=ehr_diagnostics::state().snapshot();CHECK(proof.detail_total==51&&proof.detail_count==32);CHECK(!s.loaded&&s.roots.empty());
 std::printf("{\"pass\":true,\"checks\":%zu,\"gameLoaded\":false,\"realGcCalls\":0}\n",checks);return 0;
}}
