// Exact native adapter with owned in-process runtime objects and sentinels.
// No game, service, real clipboard, credential or account operation is linked.
#import <Foundation/Foundation.h>
#include <cstring>
#include <atomic>
#include <initializer_list>
#import "../native/EHRRuntimeGateway.h"
static void OwnedOriginalHelper(void *,const void *);
static void *ownedCaller();
static NSDictionary *ownedInfo;
@interface OwnedBundle:NSObject
+ (instancetype)mainBundle;
- (NSDictionary *)infoDictionary;
@end
@implementation OwnedBundle
+ (instancetype)mainBundle {static auto b=[OwnedBundle new];return b;}
- (NSDictionary *)infoDictionary{return ownedInfo;}
@end
#define NSBundle OwnedBundle
#define __builtin_return_address(x) ownedCaller()
#import "../native/EHRLobbySearch.mm"
#undef __builtin_return_address
#undef NSBundle

@interface OwnedObject:NSObject
@property(nonatomic) const void *klass;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,OwnedObject *> *fields;
@property(nonatomic,strong) NSMutableArray<OwnedObject *> *items;
@property(nonatomic,copy) NSString *text;
@property(nonatomic,strong) NSData *value;
@end
@implementation OwnedObject
@end
namespace {
int setClass,filterClass,modClass,guidClass,listClass,stringClass,intClass;
NSUInteger checks=0;NSMutableArray<NSString *> *errors;NSMutableArray<OwnedObject *> *objects;
NSMutableDictionary<NSNumber *,OwnedObject *> *roots;uint64_t nextRoot=1000;
bool permitted=true,foreignCaller=false;NSUInteger originalCalls=0,allocations=0;
int failMethod=0;bool changeGateDuringCtor=false;
OwnedObject *globalString;
enum {Helper=1,SetCtor=2,FilterCtor=3,ModCtor=4,GuidParse=5,Count=6,Item=7,Add=8,Global=9,Filters=10,Key=11,Sub=12,Accepted=13,Int=14,Option=15};
void Check(bool okay,NSString *label){++checks;if(!okay)[errors addObject:label];}
OwnedObject *object(const void *klass){auto v=[OwnedObject new];v.klass=klass;v.fields=[NSMutableDictionary new];v.items=[NSMutableArray new];[objects addObject:v];return v;}
OwnedObject *text(NSString *value){auto v=object(&stringClass);v.text=value;return v;}
OwnedObject *box(const void *klass,const void *bytes,size_t count){auto v=object(klass);v.value=[NSData dataWithBytes:bytes length:count];return v;}
EHRRuntimeToken root(OwnedObject *value){if(!value)return 0;auto token=nextRoot++;roots[@(token)]=value;return token;}
OwnedObject *resolve(EHRRuntimeToken token){return roots[@(token)];}
OwnedObject *newSet(){auto set=object(&setClass);set.fields[@(Filters)]=object(&listClass);return set;}
OwnedObject *row(NSString *name,bool matching=true){auto v=object(&filterClass);v.fields[@(Key)]=text(name);v.fields[@(Option)]=text(name);if([name isEqual:@"mod"]){auto mod=object(&modClass);uint8_t bytes[16];memset(bytes,matching?42:7,sizeof(bytes));mod.fields[@(Accepted)]=box(&guidClass,bytes,sizeof(bytes));v.fields[@(Sub)]=mod;}return v;}
const void *objectClass(void *value){return [(__bridge OwnedObject *)value klass];}
void *objectNew(const void *klass){++allocations;return (__bridge void *)object(klass);}
int32_t permissionFixture(){return permitted?1:0;}
int32_t anotherPermission(){return 0;}
void Reset(){Check(roots.count==0,@"prior_owned_roots_released");objects=[NSMutableArray new];roots=[NSMutableDictionary new];globalString=text(@"");permitted=true;foreignCaller=false;failMethod=0;changeGateDuringCtor=false;originalCalls=allocations=0;ownedInfo=@{@"EHRLobbySearchCompiled":@YES};
 meta={};meta.setClass=&setClass;meta.filterClass=&filterClass;meta.modClass=&modClass;meta.guidClass=&guidClass;meta.listClass=&listClass;meta.helper=Helper;meta.setCtor=SetCtor;meta.filterCtor=FilterCtor;meta.modCtor=ModCtor;meta.guidParse=GuidParse;meta.count=Count;meta.item=Item;meta.add=Add;meta.global=Global;meta.filters=Filters;meta.key=Key;meta.option=Option;meta.sub=Sub;meta.accepted=Accepted;api.object_get_class=objectClass;api.object_new=objectNew;prepared.store(0);allowed.store(permissionFixture);applying=false;
}
void OnWorker(void(^operation)(void)){dispatch_semaphore_t done=dispatch_semaphore_create(0);dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{operation();dispatch_semaphore_signal(done);});Check(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0,@"owned_worker_finishes");}
}
static void *ownedCaller(){return (void *)(foreignCaller?0x100:EHRLobbySearchCallerReturnRVA);}
static void OwnedOriginalHelper(void *value,const void *info){(void)info;++originalCalls;OwnedObject *set=(__bridge OwnedObject *)value;if(!set)return;auto list=set.fields[@(Filters)];for(NSInteger i=(NSInteger)list.items.count-1;i>=0;--i)if([list.items[(NSUInteger)i].fields[@(Key)].text isEqual:@"mod"])[list.items removeObjectAtIndex:(NSUInteger)i];}
extern "C" uintptr_t EHRNativeHooksImageBaseForDiagnostics(void){return 0;}
namespace ehr_pinned {EHRRuntimeStatus validate_engine_entry(const void*){return EHR_RUNTIME_OK;}}
extern "C" EHRRuntimeStatus ehr_runtime_object_release(EHRRuntimeToken token){if(!roots[@(token)])return EHR_RUNTIME_INVALID_TOKEN;[roots removeObjectForKey:@(token)];return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_root_count(size_t *count){*count=roots.count;return EHR_RUNTIME_OK;}
EHRRuntimeStatus EHRRuntimeActionRootBorrowed(void *value,EHRRuntimeToken *out){*out=root((__bridge OwnedObject *)value);return EHR_RUNTIME_OK;}
EHRRuntimeStatus EHRRuntimeIteratorBorrow(EHRRuntimeToken token,void **out){*out=(__bridge void *)resolve(token);return *out?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;}
extern "C" EHRRuntimeStatus ehr_runtime_read_field(EHRRuntimeToken field,EHRRuntimeToken owner,EHRRuntimeToken *out){auto value=field==Global?globalString:resolve(owner).fields[@(field)];*out=root(value);return value?EHR_RUNTIME_OK:EHR_RUNTIME_NOT_FOUND;}
extern "C" EHRRuntimeStatus ehr_runtime_write_field(EHRRuntimeToken field,EHRRuntimeToken owner,const EHRRuntimeArgument *arg){if(field!=Accepted||arg->kind!=EHR_RUNTIME_BOXED_VALUE)return EHR_RUNTIME_TYPE_MISMATCH;resolve(owner).fields[@(field)]=resolve(arg->token);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_object_same(EHRRuntimeToken a,EHRRuntimeToken b,int32_t *same){*same=resolve(a)==resolve(b);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_string_create(const uint16_t *units,size_t count,EHRRuntimeToken *out){*out=root(text([[NSString alloc] initWithCharacters:units length:count]));return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_string_copy(EHRRuntimeToken token,uint16_t *units,size_t capacity,size_t *length){OwnedObject *v=resolve(token);if(v.klass!=&stringClass)return EHR_RUNTIME_TYPE_MISMATCH;*length=v.text.length;if(capacity<*length)return EHR_RUNTIME_LIMIT;if(*length)[v.text getCharacters:units range:NSMakeRange(0,*length)];return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_copy_value(EHRRuntimeToken token,void *bytes,size_t capacity,size_t *count){OwnedObject *v=resolve(token);*count=v.value.length;if(!v.value||capacity<*count)return EHR_RUNTIME_LIMIT;memcpy(bytes,v.value.bytes,*count);return EHR_RUNTIME_OK;}
extern "C" EHRRuntimeStatus ehr_runtime_invoke(EHRRuntimeToken method,EHRRuntimeToken owner,const EHRRuntimeArgument *args,size_t count,EHRRuntimeToken *out,EHRRuntimeToken *exception){*out=*exception=0;if((int)method==failMethod)return EHR_RUNTIME_MANAGED_EXCEPTION;auto target=resolve(owner);
 switch(method){case SetCtor:target.fields[@(Filters)]=object(&listClass);break;
 case ModCtor:break;
 case GuidParse:{Check(count==1&&[resolve(args[0].token).text isEqual:@"446420cc-ce35-4c2f-8f5d-b14f84354421"],@"only_public_ehr_guid_constructed");uint8_t value[16];memset(value,42,16);*out=root(box(&guidClass,value,16));break;}
 case FilterCtor:Check(count==2,@"exact_original_filter_constructor_arguments");target.fields[@(Key)]=resolve(args[0].token);target.fields[@(Option)]=text(@"mod");target.fields[@(Sub)]=resolve(args[1].token);if(changeGateDuringCtor)permitted=false;break;
 case Count:{int32_t n=(int32_t)target.items.count;*out=root(box(&intClass,&n,sizeof(n)));break;}
 case Item:{int32_t i=*(const int32_t *)args[0].bytes;if(i<0||(NSUInteger)i>=target.items.count)return EHR_RUNTIME_BAD_ARGUMENT;*out=root(target.items[(NSUInteger)i]);break;}
 case Add:Check(count==1&&args[0].kind==EHR_RUNTIME_REFERENCE,@"single_reference_list_commit");[target.items addObject:resolve(args[0].token)];break;
 default:return EHR_RUNTIME_UNSUPPORTED;}
 return EHR_RUNTIME_OK;}
// Passive preparation is independently validated against real pinned metadata.
// These fixture stubs make accidental runtime lookup fail, never call a game.
extern "C" EHRRuntimeStatus ehr_runtime_find_class(const char*,const char*,const char *name,EHRRuntimeToken *out){if(!strcmp(name,"Int32")){*out=Int;return EHR_RUNTIME_OK;}return EHR_RUNTIME_NOT_READY;}
extern "C" EHRRuntimeStatus ehr_runtime_find_method(EHRRuntimeToken,const char*,const char *const*,size_t,const char*,int,EHRRuntimeToken*){return EHR_RUNTIME_NOT_READY;}
extern "C" EHRRuntimeStatus ehr_runtime_find_field(EHRRuntimeToken,const char*,const char*,int,EHRRuntimeToken*){return EHR_RUNTIME_NOT_READY;}
extern "C" EHRRuntimeStatus ehr_runtime_validate_native_method(EHRRuntimeToken,uint64_t,uint64_t*){return EHR_RUNTIME_NOT_READY;}
extern "C" EHRRuntimeStatus ehr_runtime_class_from_type_object(EHRRuntimeToken,EHRRuntimeToken*){return EHR_RUNTIME_NOT_READY;}
EHRRuntimeStatus EHRRuntimeBorrowClass(EHRRuntimeToken,const void**){return EHR_RUNTIME_NOT_READY;}
EHRRuntimeStatus EHRRuntimeBorrowMethod(EHRRuntimeToken,const void**,const void**){return EHR_RUNTIME_NOT_READY;}

int main(){@autoreleasepool{
 errors=[NSMutableArray new];roots=[NSMutableDictionary new];Reset();
 Check(EHRLobbySearchPrepare(nullptr)==EHR_RUNTIME_BAD_ARGUMENT,@"null_gate_rejected");Check(EHRLobbySearchPrepare(anotherPermission)==EHR_RUNTIME_BAD_ARGUMENT,@"gate_rebinding_rejected");
 OnWorker(^{Check(EHRLobbySearchPrepare(permissionFixture)==EHR_RUNTIME_WRONG_THREAD,@"worker_prepare_rejected");});
 Check(allocations==0,@"preparation_never_constructs_filter_or_request_objects");
 {Root set;auto v=newSet();v.fields[@(Filters)].items=[NSMutableArray arrayWithObject:row(@"map")];set.token=root(v);auto first=append(set.token,true);Check(!first.status&&first.appended&&v.fields[@(Filters)].items.count==2,@"append_preserves_other_filters");auto second=append(set.token,true);Check(!second.status&&second.existing&&!second.appended&&v.fields[@(Filters)].items.count==2,@"same_request_application_is_idempotent");}
 for(int malformed=0;malformed<5;++malformed){Reset();{Root set;auto v=newSet();auto list=v.fields[@(Filters)];
  if(malformed==0)[list.items addObject:row(@"mod",false)];
  else if(malformed==1){[list.items addObject:row(@"mod")];[list.items addObject:row(@"mod")];}
  else if(malformed==2)[list.items addObject:object(&modClass)];
  else if(malformed==3){auto x=row(@"map");x.fields[@(Option)]=text(@"mod");[list.items addObject:x];}
  else for(NSUInteger i=0;i<=maxFilters;++i)[list.items addObject:row(@"map")];
  auto before=list.items.count;set.token=root(v);auto result=append(set.token,true);Check(result.status&&list.items.count==before,@"malformed_or_foreign_filter_set_unchanged");}}
 for(int failing:{GuidParse,ModCtor,FilterCtor,Add}){Reset();{Root set;auto v=newSet();set.token=root(v);failMethod=failing;auto result=append(set.token,true);Check(result.status&&v.fields[@(Filters)].items.count==0,@"caught_native_failure_never_commits_partial_filter");}}
 Reset();{Root set;auto v=newSet();set.token=root(v);changeGateDuringCtor=true;auto result=append(set.token,true);Check(result.status&&v.fields[@(Filters)].items.count==0,@"permission_rechecked_before_commit");}
 Reset();{Root set;auto v=newSet();set.token=root(v);globalString=text(@"OWNED-FOREIGN-REGISTRATION");auto result=append(set.token,true);Check(result.status&&v.fields[@(Filters)].items.count==0,@"global_registration_is_never_changed_or_overridden");}
 for(int guard=0;guard<4;++guard){Reset();auto v=newSet();if(guard==0)foreignCaller=true;else if(guard==1)permitted=false;else if(guard==2)ownedInfo=@{@"EHRLobbySearchCompiled":@NO};
  if(guard==3)OnWorker(^{ehr_native_ehr_lobby_search_filters((__bridge void *)v,nullptr);});else ehr_native_ehr_lobby_search_filters((__bridge void *)v,nullptr);
  Check(originalCalls==1&&v.fields[@(Filters)].items.count==0,@"original_once_foreign_inactive_or_worker_unchanged");}
 Reset();auto v=newSet();for(int request=0;request<3;++request){ehr_native_ehr_lobby_search_filters((__bridge void *)v,nullptr);Check(originalCalls==(NSUInteger)request+1&&v.fields[@(Filters)].items.count==1,@"original_cleanup_then_ehr_filter_reapplied_every_request");}
 Check(globalString.text.length==0,@"registration_unchanged_after_real_hook_path");Check(roots.count==0,@"all_owned_tokens_released");
 Reset();auto self=EHRLobbySearchSelfTest();Check([self[@"success"] boolValue]&&[self[@"rootsBefore"] isEqual:self[@"rootsAfter"]],@"owned_self_test_uses_same_object_pipeline_and_preserves_roots");
 auto snapshot=EHRLobbySearchCopyStatus();for(id value in snapshot.allValues)Check([value isKindOfClass:NSNumber.class],@"status_is_numeric_only");
 NSDictionary *proof=@{@"schema":@"ehr.lobby-search-owned-fixture.v1",@"success":@(errors.count==0),@"checks":@(checks),@"failures":errors,@"actualGameRequests":@0,@"accountActions":@0,@"realCredentialReads":@0,@"globalRegistrationWrites":@0};auto bytes=[NSJSONSerialization dataWithJSONObject:proof options:NSJSONWritingSortedKeys error:nil];puts([[NSString alloc]initWithData:bytes encoding:NSUTF8StringEncoding].UTF8String);return errors.count?1:0;
}}
