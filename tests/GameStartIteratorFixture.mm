// Entirely owned synthetic runtime. No game binary, scene or network is used.
#import <Foundation/Foundation.h>
#include <map>
#include <memory>
#include <set>
#include <vector>
#include <cstdio>
#include <thread>
#include <cstdlib>
#include <cstring>
#include "../native/EHRRuntimeGateway.h"
void EHRNativeRaiseOwnedFailure(int32_t,EHRRuntimeToken);
#include "../native/EHRGameStartIteratorAdapter.mm"
namespace own {
struct Object {uint64_t klass;int32_t state=0;Object *current=nullptr,*owner=nullptr;};
std::vector<std::unique_ptr<Object>> objects;std::map<uint64_t,Object*> roots;
uint64_t nextToken=100,nextRegistration=1;uint32_t originalCount=0,gameFactoryCount=0,constructCount=0,writeCount=0;
bool originalResult=true,throwOriginal=false,foreignMethod=false,readOnly=false;
int factoryMode=0;Object *factoryObject=nullptr,*factoryError=nullptr,*mutatedObject=nullptr,*mutatedChild=nullptr;
std::set<Object*> activeCarriers;
struct Registration {Object *object;EHRManagedIteratorCallbacksV1 callbacks;uint64_t source;bool active=true;};
std::map<uint64_t,Registration> registrations;
uint32_t checks=0;
void check(bool b){++checks;if(!b){fprintf(stderr,"check %u failed\n",checks);abort();}}
Object *make(uint64_t klass,int32_t state=0){objects.push_back(std::make_unique<Object>());auto *p=objects.back().get();p->klass=klass;p->state=state;return p;}
uint64_t root(Object *object){if(!object)return 0;uint64_t t=nextToken++;roots[t]=object;return t;}
Object *get(uint64_t token){return token?roots.at(token):nullptr;}
const void *ptr(uint64_t value){return reinterpret_cast<const void*>(uintptr_t(value));}
uint64_t val(const void *p){return uint64_t(reinterpret_cast<uintptr_t>(p));}
const char *fieldName(uint64_t f){switch(f){case 21:case 31:return "<>1__state";case 22:return "<>2__current";case 23:case 32:return "<>4__this";}return "bad";}
uint64_t fieldType(uint64_t f){return f==21||f==31?5:f==22?9:3;}
const char *typeName(uint64_t c){return c==5?"System.Int32":c==9?"System.Object":c==3?"AmongUsClient":"bad";}
struct NativeException{uint64_t token;int32_t status;};
}
extern "C" __attribute__((visibility("default"))) const void *il2cpp_class_get_methods(const void*,void**){return nullptr;}
extern "C" __attribute__((visibility("default"))) const char *il2cpp_method_get_name(const void*){return ".ctor";}
extern "C" __attribute__((visibility("default"))) uint32_t il2cpp_method_get_token(const void *m){return own::val(m)==11?0x6001ce5:0x6001c6b;}
extern "C" __attribute__((visibility("default"))) const void *il2cpp_object_get_class(const void *o){return own::ptr(static_cast<const own::Object*>(o)->klass);}
extern "C" __attribute__((visibility("default"))) bool il2cpp_class_is_assignable_from(const void *a,const void *b){return own::val(a)==4&&own::val(b)==8;}
extern "C" __attribute__((visibility("default"))) const void *il2cpp_class_get_fields(const void *klass,void **cursor){size_t i=reinterpret_cast<uintptr_t>(*cursor);const uint64_t list1[]={21,22,23},list2[]={31,32};
 auto count=own::val(klass)==1?3u:2u;if(i>=count)return nullptr;*cursor=reinterpret_cast<void*>(i+1);return own::ptr(own::val(klass)==1?list1[i]:list2[i]);}
extern "C" __attribute__((visibility("default"))) const void *il2cpp_field_get_parent(const void *f){return own::ptr(own::val(f)<30?1:2);}
extern "C" __attribute__((visibility("default"))) const void *il2cpp_field_get_type(const void *f){return own::ptr(own::fieldType(own::val(f)));}
extern "C" __attribute__((visibility("default"))) const char *il2cpp_field_get_name(const void *f){return own::fieldName(own::val(f));}
extern "C" __attribute__((visibility("default"))) uint32_t il2cpp_field_get_flags(const void*){return own::readOnly?0x20:0;}
extern "C" __attribute__((visibility("default"))) char *il2cpp_type_get_name(const void *t){return strdup(own::typeName(own::val(t)));}
extern "C" __attribute__((visibility("default"))) void il2cpp_free(void *p){free(p);}
namespace ehr_pinned {EHRRuntimeStatus validate_engine_entry(const void*){return EHR_RUNTIME_OK;}}
extern "C" EHRRuntimeStatus ehr_runtime_find_class(const char*,const char*,const char *name,EHRRuntimeToken *out){
 *out=!strcmp(name,ParentName)?1:!strcmp(name,HostName)?2:!strcmp(name,"AmongUsClient")?3:!strcmp(name,"IEnumerator")||!strcmp(name,"IEnumerable")?4:!strcmp(name,"Int32")?5:!strcmp(name,"ArrayList")?6:!strcmp(name,"InvalidOperationException")?7:0;return *out?EHR_RUNTIME_OK:EHR_RUNTIME_NOT_FOUND;}
extern "C" EHRRuntimeStatus ehr_runtime_find_method(EHRRuntimeToken,const char *name,const char*const*,size_t,const char*,int,EHRRuntimeToken *out){*out=!strcmp(name,"MoveNext")?11:!strcmp(name,"CoStartGameHost")?12:13;return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_validate_native_method(EHRRuntimeToken,uint64_t expected,uint64_t *out){*out=expected;return EHR_RUNTIME_OK;}
EHRRuntimeStatus EHRRuntimeBorrowClass(EHRRuntimeToken c,const void **out){*out=own::ptr(c);return EHR_RUNTIME_OK;}
EHRRuntimeStatus EHRRuntimeBorrowMethod(EHRRuntimeToken m,const void **out,const void **owner){*out=own::ptr(m);*owner=own::ptr(m==11?1:3);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_find_field(EHRRuntimeToken c,const char *name,const char*,int,EHRRuntimeToken *out){*out=c==1?(!strcmp(name,"<>1__state")?21:!strcmp(name,"<>2__current")?22:23):(!strcmp(name,"<>1__state")?31:32);return EHR_RUNTIME_OK;}
EHRRuntimeStatus EHRRuntimeActionRootBorrowed(void *o,EHRRuntimeToken *out){*out=own::root(static_cast<own::Object*>(o));return EHR_RUNTIME_OK;}
EHRRuntimeStatus EHRRuntimeIteratorPin(EHRRuntimeToken t,EHRRuntimeToken *out,void **object){*object=own::get(t);*out=own::root(static_cast<own::Object*>(*object));return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_class(EHRRuntimeToken t,EHRRuntimeToken *out){*out=own::get(t)->klass;return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_release(EHRRuntimeToken t){return !t||own::roots.erase(t)?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;}
extern "C" EHRRuntimeStatus ehr_runtime_object_same(EHRRuntimeToken a,EHRRuntimeToken b,int32_t *out){*out=own::get(a)==own::get(b);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_read_field(EHRRuntimeToken f,EHRRuntimeToken t,EHRRuntimeToken *out){auto *o=own::get(t);*out=own::root(f==21||f==31?own::make(5,o->state):f==22?o->current:o->owner);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_copy_value(EHRRuntimeToken t,void *out,size_t cap,size_t *count){if(cap!=4)return EHR_RUNTIME_BAD_ARGUMENT;*count=4;memcpy(out,&own::get(t)->state,4);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_write_field(EHRRuntimeToken f,EHRRuntimeToken t,const EHRRuntimeArgument *arg){auto *o=own::get(t);++own::writeCount;
 if(f==21||f==31)memcpy(&o->state,arg->bytes,4);else if(f==22)o->current=own::get(arg->token);else o->owner=own::get(arg->token);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_box(EHRRuntimeToken c,const void *value,size_t n,EHRRuntimeToken *out){if(n!=4)return EHR_RUNTIME_BAD_ARGUMENT;int v;memcpy(&v,value,4);*out=own::root(own::make(c,v));return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_construct(EHRRuntimeToken c,const EHRRuntimeToken *args,size_t n,EHRRuntimeToken *out,EHRRuntimeToken *error){++own::constructCount;*error=0;*out=own::root(own::make(c,n?own::get(args[0])->state:0));return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_invoke(EHRRuntimeToken method,EHRRuntimeToken,const EHRRuntimeArgument*,size_t,EHRRuntimeToken *out,EHRRuntimeToken *error){*out=*error=0;
 if(method==13){*out=own::root(own::make(8));return EHR_RUNTIME_OK;}
 ++own::gameFactoryCount;
 if(own::factoryMode==1){*out=own::root(own::factoryObject);*error=own::root(own::factoryError);return EHR_RUNTIME_MANAGED_EXCEPTION;}
 if(own::factoryMode==2){EHRGameStartIteratorSetEnabled(0);}
 if(own::factoryMode==3)own::mutatedObject->state=7;
 if(own::factoryMode==4)own::mutatedObject->current=nullptr;
 if(own::factoryMode==5)own::mutatedObject->owner=nullptr;
 if(own::factoryMode==6)own::mutatedChild->state=1;
 if(own::factoryMode==7)own::mutatedChild->owner=nullptr;
 *out=own::root(own::factoryObject);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_root_count(size_t *out){*out=own::roots.size();return EHR_RUNTIME_OK;}
bool EHRProductionIteratorHasActiveIdentity(void *p){return own::activeCarriers.count(static_cast<own::Object*>(p))!=0;}
extern "C" void EHRManagedIteratorProductionMakeTable(EHRManagedIteratorProductionV1 *host){*host={1,72,
 [](uint64_t t,uint64_t source,const EHRManagedIteratorCallbacksV1 *cb,uint64_t *out)->int32_t{auto *o=own::get(t);*out=own::nextRegistration++;own::registrations.emplace(*out,own::Registration{o,*cb,source,true});own::activeCarriers.insert(o);return 0;},nullptr,
 [](uint64_t id)->int32_t{auto &r=own::registrations.at(id);if(r.active){r.active=false;own::activeCarriers.erase(r.object);r.callbacks.cancel(r.source);}return 0;},nullptr,nullptr,nullptr,nullptr,nullptr};}
void EHRRuntimeGatewayPublishDiagnosticSnapshot() noexcept {}
namespace own {
bool original(void*,const void*){++originalCount;if(throwOriginal)throw NativeException{0,6};return originalResult;}
}
uintptr_t EHRNativePatchOriginal(const EHRNativePatchSiteV1&){return reinterpret_cast<uintptr_t>(&own::original);}
void EHRNativeRaiseOwnedFailure(int32_t status,EHRRuntimeToken exception){if(exception)ehr_runtime_object_release(exception);throw own::NativeException{exception,status};}

int main(){@autoreleasepool{using namespace own;
 check(EHRGameStartIteratorSetEnabled(1)==1);check(EHRGameStartIteratorPrepare()==0);check(constructCount==0);check(EHRGameStartIteratorSetEnabled(1)==0);
 auto *owner=make(3),*parent=make(1,5),*child=make(2,0),*carrier=make(8);parent->owner=child->owner=owner;parent->current=child;factoryObject=carrier;activeCarriers.insert(carrier);factoryError=make(7);mutatedObject=parent;mutatedChild=child;
 check(ehr_native_game_start_move_next_hook(parent,ptr(11)));check(parent->current==carrier&&originalCount==1&&gameFactoryCount==1&&roots.empty());
 check(ehr_native_game_start_move_next_hook(parent,nullptr));check(originalCount==2&&gameFactoryCount==1&&roots.empty());
 for(int mutation=1;mutation<=7;++mutation){factoryMode=mutation;parent->state=5;parent->current=child;parent->owner=child->owner=owner;child->state=0;EHRGameStartIteratorSetEnabled(1);const auto before=originalCount,fc=gameFactoryCount,wc=writeCount;
  bool caught=false;try{ehr_native_game_start_move_next_hook(parent,ptr(11));}catch(const NativeException &e){caught=true;check(e.status==(mutation==1?6:mutation==2?1:5));}
  check(caught&&originalCount==before+1&&gameFactoryCount==fc+1&&writeCount==wc&&roots.empty());}
 factoryMode=0;parent->state=5;parent->owner=child->owner=owner;
 for(int invalid=0;invalid<9;++invalid){parent->current=child;parent->state=5;child->state=0;parent->owner=child->owner=owner;activeCarriers.insert(carrier);EHRGameStartIteratorSetEnabled(1);
  if(invalid==0)parent->owner=nullptr;if(invalid==1)child->owner=make(3);if(invalid==2)child->owner=make(9);if(invalid==3)parent->state=6;if(invalid==4)child->state=1;if(invalid==5)activeCarriers.erase(carrier);if(invalid==7){factoryObject=make(9);activeCarriers.insert(factoryObject);}if(invalid==8)factoryObject=nullptr;
  const auto oc=originalCount,fc=gameFactoryCount,wc=writeCount;bool caught=false;
  try{ehr_native_game_start_move_next_hook(parent,invalid==6?ptr(999):ptr(11));}catch(const NativeException&){caught=true;}
  check(caught&&originalCount==oc+1&&writeCount==wc&&roots.empty());check(gameFactoryCount==fc+(invalid==5||invalid>=7?1:0));factoryObject=carrier;}
 EHRGameStartIteratorSetEnabled(0);const auto fc=gameFactoryCount;check(ehr_native_game_start_move_next_hook(parent,nullptr));check(gameFactoryCount==fc);
 EHRGameStartIteratorSetEnabled(1);originalResult=false;check(!ehr_native_game_start_move_next_hook(parent,ptr(11)));check(gameFactoryCount==fc);originalResult=true;
 throwOriginal=true;const auto oc=originalCount;bool thrown=false;try{ehr_native_game_start_move_next_hook(parent,nullptr);}catch(const NativeException&){thrown=true;}check(thrown&&originalCount==oc+1&&gameFactoryCount==fc&&roots.empty());throwOriginal=false;
 EHRGameStartIteratorSetEnabled(1);const auto workerFactory=gameFactoryCount;bool workerReturned=false;
 std::thread worker([&]{workerReturned=ehr_native_game_start_move_next_hook(parent,nullptr);});worker.join();check(workerReturned&&gameFactoryCount==workerFactory&&roots.empty());
 auto proof=EHRGameStartIteratorSelfTest();check([proof[@"success"] boolValue]);check(roots.empty());
 NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"pass":@YES,@"checks":@(checks),@"actualAdapterSourceCompiled":@YES,@"ownedMetadataFixture":@YES,@"rootCount":@(roots.size()),@"fabricatedIteratorSelfTest":proof} options:0 error:nil];puts([[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}}
