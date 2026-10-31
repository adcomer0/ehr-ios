// Actual private gateway implementation with owned synthetic public exports.
// No game binary, managed source callback, account or network is loaded.
#include "EHRRuntimeGateway.mm"
#include <cstdio>
#include <stdexcept>
#include <thread>
#include <unordered_map>
#define CHECK(x) do { ++checks; if (!(x)) { std::fprintf(stderr,"line %d\n",__LINE__); return 1; } } while (0)
namespace fixture {
struct Class { const char *name; };
Class base{"Exception"}, invalid{"InvalidOperationException"}, unsupported{"NotSupportedException"}, other{"Object"};
struct Value { Class *klass; };
Value invalidValue{&invalid}, unsupportedValue{&unsupported}, otherValue{&other};
struct Handle { Object *value; bool pinned; };
std::unordered_map<uint32_t,Handle> handles;
uint32_t nextHandle=1;
size_t touches=0,factories=0,raises=0,activators=0;
bool denyValidation=false,noCore=false,wrongImage=false,noClass=false,notAssignable=false,
     nullFactory=false,wrongClass=false,throwFactory=false,failHandle=false,nullTarget=false,returnRaise=false;
struct Raised { Object *value; };
void touch(){if(!NSThread.isMainThread)abort();++touches;}
RuntimeClass *as(Class &value){return reinterpret_cast<RuntimeClass *>(&value);}
Domain *domain(){touch();return reinterpret_cast<Domain *>(1);}
void *thread(){touch();return reinterpret_cast<void *>(1);}
const Image *core(){touch();return noCore?nullptr:reinterpret_cast<Image *>(1);}
const char *imageName(const Image *){touch();return wrongImage?"Owned.Other.dll":"mscorlib.dll";}
RuntimeClass *findClass(const Image *,const char *space,const char *name){
    touch();if(noClass||strcmp(space,"System"))return nullptr;
    for(auto *value:{&base,&invalid,&unsupported})if(!strcmp(value->name,name))return as(*value);
    return nullptr;
}
const char *className(RuntimeClass *value){touch();return reinterpret_cast<Class *>(value)->name;}
const char *classSpace(RuntimeClass *){touch();return "System";}
bool assignable(RuntimeClass *a,RuntimeClass *b){touch();return !notAssignable&&a==as(base)&&(b==as(invalid)||b==as(unsupported));}
RuntimeClass *objectClass(Object *value){touch();return as(*reinterpret_cast<Value *>(value)->klass);}
uint32_t newHandle(Object *value,bool pinned){touch();if(failHandle)return 0;auto key=nextHandle++;handles.emplace(key,Handle{value,pinned});return key;}
Object *target(uint32_t key){touch();auto i=handles.find(key);return nullTarget||i==handles.end()?nullptr:i->second.value;}
void freeHandle(uint32_t key){touch();if(handles.erase(key)!=1)abort();}
Exception *create(const Image *image,const char *space,const char *name,const char *message){
    touch();++factories;if(image!=reinterpret_cast<Image *>(1)||strcmp(space,"System")||strcmp(message,"EHR source iterator failed."))abort();
    if(throwFactory)throw std::runtime_error("owned factory failure");
    if(nullFactory)return nullptr;
    auto *value=wrongClass?&otherValue:!strcmp(name,"NotSupportedException")?&unsupportedValue:&invalidValue;
    return reinterpret_cast<Exception *>(value);
}
void raise(Exception *exception){
    touch();++raises;auto *object=reinterpret_cast<Object *>(exception);bool pinned=false;
    for(auto &entry:handles)if(entry.second.value==object&&entry.second.pinned)pinned=true;
    if(!pinned)abort();if(returnRaise)return;throw Raised{object};
}
}
extern "C" __attribute__((visibility("default"))) const Image *il2cpp_get_corlib(){return fixture::core();}
extern "C" __attribute__((visibility("default"))) Exception *il2cpp_exception_from_name_msg(const Image *image,const char *space,const char *name,const char *message){return fixture::create(image,space,name,message);}
extern "C" __attribute__((visibility("default"))) void il2cpp_raise_exception(Exception *exception){fixture::raise(exception);}
namespace ehr_pinned {
EHRRuntimeStatus validate_engine_entry(const void *entry){fixture::touch();return entry&&!fixture::denyValidation?EHR_RUNTIME_OK:EHR_RUNTIME_UNSUPPORTED;}
}
extern "C" EHRRuntimeStatus ehr_runtime_construct(EHRRuntimeToken,const EHRRuntimeToken *,size_t,EHRRuntimeToken *,EHRRuntimeToken *){++fixture::activators;abort();}
int main(){@autoreleasepool{using namespace fixture;using namespace ehr_iterator_exception;size_t checks=0;auto &s=state();s.loaded=true;
    s.api.domain_get=domain;s.api.thread_current=thread;s.api.image_get_name=imageName;s.api.class_from_name=findClass;
    s.api.class_get_name=className;s.api.class_get_namespace=classSpace;s.api.class_is_assignable_from=assignable;
    s.api.object_get_class=objectClass;s.api.gchandle_new=newHandle;s.api.gchandle_get_target=target;s.api.gchandle_free=freeHandle;
    NSDictionary *proof=EHRRuntimeIteratorExceptionSelfTest();
    CHECK([proof[@"success"] boolValue]&&[proof[@"caughtMask"] unsignedIntValue]==3&&handles.empty()&&activators==0);
    CHECK([proof[@"nativeHandlesCreated"] unsignedLongLongValue]==2&&[proof[@"nativeHandlesReleased"] unsignedLongLongValue]==2);
    for(auto failure:{EHR_RUNTIME_BAD_ARGUMENT,EHR_RUNTIME_UNSUPPORTED}){
        bool caught=false;try{EHRRuntimeIteratorRaise(failure);}catch(const Raised &value){caught=true;CHECK(objectClass(value.value)==as(failure==EHR_RUNTIME_UNSUPPORTED?unsupported:invalid));}
        CHECK(caught&&handles.empty()&&s.roots.empty()&&activators==0);
    }
    auto rejected=[&](EHRRuntimeStatus expected){const auto before=factories;NativeException value;const auto status=make(EHR_RUNTIME_BAD_ARGUMENT,value);return status==expected&&!value.handle&&handles.empty()&&raises==4&&factories==before;};
    denyValidation=true;CHECK(rejected(EHR_RUNTIME_UNSUPPORTED));denyValidation=false;
    noCore=true;CHECK(rejected(EHR_RUNTIME_NOT_READY));noCore=false;
    wrongImage=true;CHECK(rejected(EHR_RUNTIME_TYPE_MISMATCH));wrongImage=false;
    noClass=true;CHECK(rejected(EHR_RUNTIME_NOT_FOUND));noClass=false;
    notAssignable=true;CHECK(rejected(EHR_RUNTIME_TYPE_MISMATCH));notAssignable=false;
    auto image=s.api.image_get_name;s.api.image_get_name=nullptr;CHECK(rejected(EHR_RUNTIME_NOT_FOUND));s.api.image_get_name=image;
    for(auto failure:{static_cast<EHRRuntimeStatus>(-1),EHR_RUNTIME_OK,static_cast<EHRRuntimeStatus>(11)}){
        const auto before=touches;NativeException value;CHECK(make(failure,value)==EHR_RUNTIME_BAD_ARGUMENT&&touches==before&&handles.empty());
    }
    for(int mode=0;mode<5;++mode){
        nullFactory=mode==0;wrongClass=mode==1;throwFactory=mode==2;failHandle=mode==3;nullTarget=mode==4;
        Counts counts;{NativeException value;const auto status=make(EHR_RUNTIME_BAD_ARGUMENT,value,&counts);CHECK(status!=EHR_RUNTIME_OK&&!value.handle);}
        CHECK(handles.empty()&&counts.created==counts.released&&raises==4);
    }
    nullFactory=wrongClass=throwFactory=failHandle=nullTarget=false;
    const auto before=touches;EHRRuntimeStatus workerStatus=EHR_RUNTIME_OK;
    std::thread worker([&]{NativeException value;workerStatus=make(EHR_RUNTIME_BAD_ARGUMENT,value);});worker.join();
    CHECK(workerStatus==EHR_RUNTIME_WRONG_THREAD&&touches==before&&handles.empty());
    // A gateway capacity/token exhaustion must not disable the native error
    // path. Fake token rows intentionally own no runtime handles in this test.
    for(size_t i=0;i<kMaxRoots;++i)s.roots.emplace(i+1,1);s.next=UINT64_MAX;
    proof=EHRRuntimeIteratorExceptionSelfTest();CHECK([proof[@"success"] boolValue]&&s.roots.size()==kMaxRoots&&handles.empty()&&s.next==UINT64_MAX);s.roots.clear();
    returnRaise=true;proof=EHRRuntimeIteratorExceptionSelfTest();CHECK(![proof[@"success"] boolValue]&&[proof[@"returnedMask"] unsignedIntValue]==3&&handles.empty());returnRaise=false;
    CHECK(activators==0);
    std::printf("{\"pass\":true,\"checks\":%zu,\"gameLoaded\":false,\"activatorCalls\":%zu,\"liveNativeHandles\":%zu}\n",checks,activators,handles.size());return 0;
}}
