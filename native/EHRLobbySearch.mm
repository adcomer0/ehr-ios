#import "EHRLobbySearch.h"
#import <CoreFoundation/CoreFoundation.h>
#include "EHRNativeHooks.h"
#include "EHRRuntimeGateway.h"
#include "EHRRuntimeMetadataPrivate.h"
#include "EHRRuntimeActionPrivate.h"
#include "EHRRuntimeIteratorPrivate.h"
#include "EHRRuntimePinnedAssociation.h"
#include <atomic>
#include <cstring>
#include <dlfcn.h>
#include <initializer_list>
#if __has_include("EHRLobbySearchBinding.generated.h")
#include "EHRLobbySearchBinding.generated.h"
#define EHR_LOBBY_SEARCH_BINDING 1
#else
#define EHR_LOBBY_SEARCH_BINDING 0
#endif

namespace {
constexpr const char *Game="Assembly-CSharp.dll",*Space="AmongUs.Matchmaking";
constexpr const char *FilterName="AmongUs.Matchmaking.GameFilter";
constexpr const char *ListName="System.Collections.Generic.List<AmongUs.Matchmaking.GameFilter>";
constexpr size_t maxFilters=128;
struct Root {EHRRuntimeToken token=0;Root()=default;Root(const Root&)=delete;Root&operator=(const Root&)=delete;~Root(){if(token)ehr_runtime_object_release(token);}};
struct API {
    const void *(*object_get_class)(void *);
    void *(*object_new)(const void *);
    const void *(*class_get_parent)(const void *),*(*class_get_type)(const void *),*(*class_from_type)(const void *);
    void *(*type_get_object)(const void *);
    bool (*class_is_valuetype)(const void *),(*class_has_references)(const void *);
    int32_t (*class_value_size)(const void *,uint32_t *);
    const void *(*class_get_methods)(const void *,void **),*(*class_get_fields)(const void *,void **);
    const char *(*method_get_name)(const void *),*(*field_get_name)(const void *);
    const void *(*field_get_type)(const void *),*(*field_get_parent)(const void *);
    uint32_t (*method_get_token)(const void *),(*field_get_flags)(const void *);
    char *(*type_get_name)(const void *);void (*free)(void *);
} api{};
struct Metadata {
    EHRRuntimeToken registration=0,set=0,filter=0,mod=0,guid=0,list=0;
    EHRRuntimeToken helper=0,setCtor=0,filterCtor=0,modCtor=0,guidParse=0;
    EHRRuntimeToken global=0,filters=0,key=0,option=0,sub=0,accepted=0;
    EHRRuntimeToken count=0,item=0,add=0;
    const void *setClass=nullptr,*filterClass=nullptr,*modClass=nullptr,*guidClass=nullptr,*listClass=nullptr,*helperMethod=nullptr;
} meta;
std::atomic<int32_t> prepared{EHR_RUNTIME_NOT_READY},lastStatus{EHR_RUNTIME_NOT_READY};
std::atomic<uint32_t> lastPhase{0};
std::atomic<uint64_t> calls{0},originalReturned{0},applied{0},alreadyPresent{0},inactive{0},foreignCallsite{0},failures{0},workerForwards{0};
std::atomic<EHRLobbySearchAllowed> allowed{nullptr};
std::atomic<int32_t> selection{0};std::atomic<bool> selectionLoaded{false};
std::atomic<uint64_t> selectionChanges{0},allForwards{0};
NSString *const selectionKey=@"EHRLobbySearchSelection";
thread_local bool applying=false;
bool permission(){auto callback=allowed.load();if(!NSThread.isMainThread||!callback)return false;@try{try{return callback()==1;}catch(...){return false;}}@catch(__unused NSException *error){return false;}}
bool selected(){id value=NSBundle.mainBundle.infoDictionary[@"EHRLobbySearchCompiled"];return [value isKindOfClass:NSNumber.class]&&[value boolValue];}
void loadSelection(){if(!NSThread.isMainThread||selectionLoaded.load())return;int32_t mode=0;
    @try{id value=[NSUserDefaults.standardUserDefaults objectForKey:selectionKey];if([value isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)value)==CFNumberGetTypeID()&&!CFNumberIsFloatType((__bridge CFNumberRef)value)){
        auto stored=[value longLongValue];if(stored==0||stored==1)mode=(int32_t)stored;}}
    @catch(__unused NSException *error){}selection.store(mode);selectionLoaded.store(true);
}
template<class T> bool load(T &target,const char *name){void *p=dlsym(RTLD_DEFAULT,name);if(!p||ehr_pinned::validate_engine_entry(p)!=0)return false;target=reinterpret_cast<T>(p);return true;}
bool named(const void *type,const char *expected){if(!type)return false;char *name=api.type_get_name(type);bool okay=name&&!strcmp(name,expected);if(name)api.free(name);return okay;}
bool noInitializer(const void *klass){void *cursor=nullptr;for(size_t i=0;i<4096;++i){const void *method=api.class_get_methods(klass,&cursor);if(!method)return true;const char *name=api.method_get_name(method);if(!name||!strcmp(name,".cctor"))return false;}return false;}
const void *ownField(const void *klass,const char *name,const char *type,bool isStatic){void *cursor=nullptr,*found=nullptr;for(size_t i=0;i<4096;++i){const void *field=api.class_get_fields(klass,&cursor);if(!field)return found;const char *actual=api.field_get_name(field);if(actual&&!strcmp(actual,name)){if(found||api.field_get_parent(field)!=klass||bool(api.field_get_flags(field)&16)!=isStatic||!named(api.field_get_type(field),type))return nullptr;found=const_cast<void *>(field);}}return nullptr;}
int32_t bindMethod(EHRRuntimeToken klass,const char *name,const char *const *params,size_t count,const char *returns,bool isStatic,uintptr_t rva,uint32_t token,EHRRuntimeToken &out){
    auto status=ehr_runtime_find_method(klass,name,params,count,returns,isStatic,&out);uint64_t observed=0;
    if(!status)status=ehr_runtime_validate_native_method(out,rva,&observed);
    const void *method=nullptr,*owner=nullptr;if(!status)status=EHRRuntimeBorrowMethod(out,&method,&owner);
    if(!status&&(!method||!owner||api.method_get_token(method)!=token))status=EHR_RUNTIME_TYPE_MISMATCH;return status;
}
int32_t prepare(){
#if !EHR_LOBBY_SEARCH_BINDING
    return EHR_RUNTIME_UNSUPPORTED;
#else
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    if(prepared.load()==0)return 0;
#define LOAD(name) if(!load(api.name,"il2cpp_" #name))return EHR_RUNTIME_NOT_READY
    LOAD(object_get_class);LOAD(object_new);LOAD(class_get_parent);LOAD(class_get_type);LOAD(class_from_type);LOAD(type_get_object);
    LOAD(class_is_valuetype);LOAD(class_has_references);LOAD(class_value_size);LOAD(class_get_methods);LOAD(class_get_fields);
    LOAD(method_get_name);LOAD(method_get_token);LOAD(field_get_name);LOAD(field_get_type);LOAD(field_get_parent);LOAD(field_get_flags);LOAD(type_get_name);LOAD(free);
#undef LOAD
    Metadata next;int32_t status=0;
#define STEP(call) if(!status)status=(call)
    STEP(ehr_runtime_find_class(Game,"","CurrentModRegistration",&next.registration));
    STEP(ehr_runtime_find_class(Game,Space,"GameFilterSet",&next.set));STEP(ehr_runtime_find_class(Game,Space,"GameFilter",&next.filter));
    STEP(ehr_runtime_find_class(Game,Space,"ModFilter",&next.mod));STEP(ehr_runtime_find_class("mscorlib.dll","System","Guid",&next.guid));
    const char *helperParams[]={"AmongUs.Matchmaking.GameFilterSet"},*filterParams[]={"System.String","AmongUs.Matchmaking.ISubFilter"},*stringParams[]={"System.String"};
    STEP(bindMethod(next.registration,"UpdateFilterSetWithModRegistrationSettings",helperParams,1,"System.Void",true,EHRLobbySearchHelperRVA,EHRLobbySearchHelperToken,next.helper));
    STEP(bindMethod(next.set,".ctor",nullptr,0,"System.Void",false,EHRLobbySearchSetCtorRVA,EHRLobbySearchSetCtorToken,next.setCtor));
    STEP(bindMethod(next.mod,".ctor",nullptr,0,"System.Void",false,EHRLobbySearchModCtorRVA,EHRLobbySearchModCtorToken,next.modCtor));
    STEP(bindMethod(next.filter,".ctor",filterParams,2,"System.Void",false,EHRLobbySearchFilterCtorRVA,EHRLobbySearchFilterCtorToken,next.filterCtor));
    STEP(bindMethod(next.guid,"Parse",stringParams,1,"System.Guid",true,EHRLobbySearchGuidParseRVA,EHRLobbySearchGuidParseToken,next.guidParse));
    STEP(EHRRuntimeBorrowClass(next.set,&next.setClass));STEP(EHRRuntimeBorrowClass(next.filter,&next.filterClass));STEP(EHRRuntimeBorrowClass(next.mod,&next.modClass));STEP(EHRRuntimeBorrowClass(next.guid,&next.guidClass));
    const void *registrationClass=nullptr;STEP(EHRRuntimeBorrowClass(next.registration,&registrationClass));
    const void *declaring=nullptr;STEP(EHRRuntimeBorrowMethod(next.helper,&next.helperMethod,&declaring));
    if(!status&&(declaring!=registrationClass||!noInitializer(next.setClass)||!noInitializer(next.filterClass)||!noInitializer(next.modClass)||
       api.class_is_valuetype(next.setClass)||api.class_is_valuetype(next.filterClass)||api.class_is_valuetype(next.modClass)||
       !api.class_is_valuetype(next.guidClass)||api.class_has_references(next.guidClass)))status=EHR_RUNTIME_TYPE_MISMATCH;
    uint32_t align=0;if(!status&&(api.class_value_size(next.guidClass,&align)!=16||align!=4))status=EHR_RUNTIME_TYPE_MISMATCH;
    const void *filtersField=!status?ownField(next.setClass,"Filters",ListName,false):nullptr;
    if(!status&&(!filtersField||!ownField(registrationClass,"ModRegistrationGuidString","System.String",true)||
       !ownField(next.filterClass,"Key","System.String",false)||!ownField(next.filterClass,"OptionType","System.String",false)||!ownField(next.filterClass,"<SubFilter>k__BackingField","AmongUs.Matchmaking.ISubFilter",false)||
       !ownField(next.modClass,"AcceptedValues","System.Guid",false)))status=EHR_RUNTIME_TYPE_MISMATCH;
    STEP(ehr_runtime_find_field(next.registration,"ModRegistrationGuidString","System.String",1,&next.global));
    STEP(ehr_runtime_find_field(next.set,"Filters",ListName,0,&next.filters));STEP(ehr_runtime_find_field(next.filter,"Key","System.String",0,&next.key));STEP(ehr_runtime_find_field(next.filter,"OptionType","System.String",0,&next.option));
    STEP(ehr_runtime_find_field(next.filter,"<SubFilter>k__BackingField","AmongUs.Matchmaking.ISubFilter",0,&next.sub));STEP(ehr_runtime_find_field(next.mod,"AcceptedValues","System.Guid",0,&next.accepted));
    if(!status){next.listClass=api.class_from_type(api.field_get_type(filtersField));if(!next.listClass||!named(api.class_get_type(next.listClass),ListName))status=EHR_RUNTIME_TYPE_MISMATCH;}
    Root listType;if(!status)status=EHRRuntimeActionRootBorrowed(api.type_get_object(api.class_get_type(next.listClass)),&listType.token);
    STEP(ehr_runtime_class_from_type_object(listType.token,&next.list));
    const char *indexParams[]={"System.Int32"},*addParams[]={FilterName};
    STEP(ehr_runtime_find_method(next.list,"get_Count",nullptr,0,"System.Int32",0,&next.count));
    STEP(ehr_runtime_find_method(next.list,"get_Item",indexParams,1,FilterName,0,&next.item));
    STEP(ehr_runtime_find_method(next.list,"Add",addParams,1,"System.Void",0,&next.add));
    for(EHRRuntimeToken method:{next.count,next.item,next.add})if(!status){const void *pointer=nullptr,*owner=nullptr;status=EHRRuntimeBorrowMethod(method,&pointer,&owner);if(!status&&(!pointer||owner!=next.listClass))status=EHR_RUNTIME_TYPE_MISMATCH;}
#undef STEP
    if(!status)meta=next;return status;
#endif
}
int32_t invoke(EHRRuntimeToken method,EHRRuntimeToken owner,const EHRRuntimeArgument *args,size_t count,Root &out){Root error;return ehr_runtime_invoke(method,owner,args,count,&out.token,&error.token);}
int32_t string(const char *value,Root &out){uint16_t units[128];size_t count=strlen(value);if(count>128)return EHR_RUNTIME_LIMIT;for(size_t i=0;i<count;++i)units[i]=(uint8_t)value[i];return ehr_runtime_string_create(units,count,&out.token);}
int32_t isString(EHRRuntimeToken value,const char *expected,bool &equal){equal=false;uint16_t units[128];size_t count=0;auto status=ehr_runtime_string_copy(value,units,128,&count);if(status)return status;if(count!=strlen(expected))return 0;equal=true;for(size_t i=0;i<count;++i)if(units[i]!=(uint8_t)expected[i])equal=false;return 0;}
int32_t emptyRegistration(){Root value;auto status=ehr_runtime_read_field(meta.global,0,&value.token);if(status||!value.token)return status;size_t length=0;status=ehr_runtime_string_copy(value.token,nullptr,0,&length);return (!status||status==EHR_RUNTIME_LIMIT)&&length==0?0:EHR_RUNTIME_TYPE_MISMATCH;}
int32_t construct(const void *klass,EHRRuntimeToken ctor,const EHRRuntimeArgument *args,size_t count,Root &out){void *object=api.object_new(klass);if(!object||api.object_get_class(object)!=klass)return EHR_RUNTIME_NOT_READY;int32_t status=EHRRuntimeActionRootBorrowed(object,&out.token);Root ignored;if(!status)status=invoke(ctor,out.token,args,count,ignored);return status;}
int32_t integer(EHRRuntimeToken box,int32_t &value){size_t count=0;auto status=ehr_runtime_copy_value(box,&value,sizeof(value),&count);return !status&&count!=sizeof(value)?EHR_RUNTIME_TYPE_MISMATCH:status;}
int32_t count(EHRRuntimeToken list,int32_t &value){Root box;auto status=invoke(meta.count,list,nullptr,0,box);if(!status)status=integer(box.token,value);return status;}
struct Result {int32_t status=0;uint32_t phase=0;bool appended=false,existing=false;};
Result append(EHRRuntimeToken set,bool accountGate=false){
    Result result;Root list,guidText,guid,mod,key,filter,ignored;
#define TRY(phaseValue,call) result.phase=phaseValue;result.status=(call);if(result.status)return result
    TRY(1,emptyRegistration());TRY(2,ehr_runtime_read_field(meta.filters,set,&list.token));
    void *listObject=nullptr;TRY(3,EHRRuntimeIteratorBorrow(list.token,&listObject));if(!listObject||api.object_get_class(listObject)!=meta.listClass){result.status=EHR_RUNTIME_TYPE_MISMATCH;return result;}
    int32_t length=0;TRY(4,count(list.token,length));if(length<0||(size_t)length>maxFilters){result.status=EHR_RUNTIME_LIMIT;return result;}
    TRY(5,string("446420cc-ce35-4c2f-8f5d-b14f84354421",guidText));
    EHRRuntimeArgument parseArg{EHR_RUNTIME_REFERENCE,0,guidText.token,nullptr,0};TRY(6,invoke(meta.guidParse,0,&parseArg,1,guid));
    uint8_t expected[16];size_t bytes=0;TRY(7,ehr_runtime_copy_value(guid.token,expected,sizeof(expected),&bytes));if(bytes!=sizeof(expected)){result.status=EHR_RUNTIME_TYPE_MISMATCH;return result;}
    for(int32_t i=0;i<length;++i){
        Root row,rowKey,option,sub,accepted;EHRRuntimeArgument index{EHR_RUNTIME_VALUE,0,0,&i,sizeof(i)};
        // Exact primitive class metadata is supplied by a boxed index below.
        EHRRuntimeToken intClass=0;TRY(8,ehr_runtime_find_class("mscorlib.dll","System","Int32",&intClass));index.token=intClass;
        TRY(8,invoke(meta.item,list.token,&index,1,row));void *object=nullptr;TRY(8,EHRRuntimeIteratorBorrow(row.token,&object));
        if(!object||api.object_get_class(object)!=meta.filterClass){result.status=EHR_RUNTIME_TYPE_MISMATCH;return result;}
        TRY(8,ehr_runtime_read_field(meta.key,row.token,&rowKey.token));bool isMod=false,isTypeMod=false;TRY(8,isString(rowKey.token,"mod",isMod));TRY(8,ehr_runtime_read_field(meta.option,row.token,&option.token));TRY(8,isString(option.token,"mod",isTypeMod));if(!isMod&&!isTypeMod)continue;if(isMod!=isTypeMod){result.status=EHR_RUNTIME_TYPE_MISMATCH;return result;}
        TRY(8,ehr_runtime_read_field(meta.sub,row.token,&sub.token));TRY(8,EHRRuntimeIteratorBorrow(sub.token,&object));if(!object||api.object_get_class(object)!=meta.modClass){result.status=EHR_RUNTIME_TYPE_MISMATCH;return result;}
        TRY(8,ehr_runtime_read_field(meta.accepted,sub.token,&accepted.token));uint8_t actual[16];size_t actualBytes=0;TRY(8,ehr_runtime_copy_value(accepted.token,actual,sizeof(actual),&actualBytes));
        if(actualBytes!=16||memcmp(expected,actual,16)||result.existing){result.status=EHR_RUNTIME_TYPE_MISMATCH;return result;}result.existing=true;
    }
    if(result.existing)return result;
    TRY(9,construct(meta.modClass,meta.modCtor,nullptr,0,mod));
    EHRRuntimeArgument accepted{EHR_RUNTIME_BOXED_VALUE,0,guid.token,nullptr,0};TRY(10,ehr_runtime_write_field(meta.accepted,mod.token,&accepted));
    TRY(11,string("mod",key));EHRRuntimeArgument ctorArgs[]={{EHR_RUNTIME_REFERENCE,0,key.token,nullptr,0},{EHR_RUNTIME_REFERENCE,0,mod.token,nullptr,0}};
    TRY(12,construct(meta.filterClass,meta.filterCtor,ctorArgs,2,filter));
    // Recheck every mutable premise before the single public List.Add commit.
    if(accountGate&&(!permission()||selection.load()!=1)){result.status=EHR_RUNTIME_NOT_READY;result.phase=13;return result;}
    TRY(13,emptyRegistration());int32_t now=0;TRY(13,count(list.token,now));if(now!=length){result.status=EHR_RUNTIME_NOT_READY;return result;}
    Root current;TRY(13,ehr_runtime_read_field(meta.filters,set,&current.token));int32_t same=0;TRY(13,ehr_runtime_object_same(current.token,list.token,&same));if(!same){result.status=EHR_RUNTIME_NOT_READY;return result;}
    EHRRuntimeArgument addArg{EHR_RUNTIME_REFERENCE,0,filter.token,nullptr,0};TRY(14,invoke(meta.add,list.token,&addArg,1,ignored));result.appended=true;
#undef TRY
    return result;
}
}

int32_t EHRLobbySearchPrepare(EHRLobbySearchAllowed callback){if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;if(!callback||(allowed.load()&&allowed.load()!=callback))return EHR_RUNTIME_BAD_ARGUMENT;allowed.store(callback);if(selected())loadSelection();int32_t status=EHR_RUNTIME_UNSUPPORTED;@try{try{status=prepare();}catch(...){status=EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *error){status=EHR_RUNTIME_NOT_READY;}prepared.store(status);lastStatus.store(status);return status;}
int32_t EHRLobbySearchGetSelection(void){if(!NSThread.isMainThread||!selected())return 0;loadSelection();return selection.load();}
int32_t EHRLobbySearchSetSelection(int32_t mode){if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;if(mode!=0&&mode!=1)return EHR_RUNTIME_BAD_ARGUMENT;if(!EHR_LOBBY_SEARCH_BINDING||!selected())return EHR_RUNTIME_UNSUPPORTED;loadSelection();if(selection.load()==mode)return 0;@try{[NSUserDefaults.standardUserDefaults setInteger:mode forKey:selectionKey];}@catch(__unused NSException *error){return EHR_RUNTIME_NOT_READY;}selection.store(mode);++selectionChanges;return 0;}
NSDictionary *EHRLobbySearchCopyStatus(void){return @{@"schemaVersion":@2,@"compiled":@(EHR_LOBBY_SEARCH_BINDING),@"selected":@(selected()),@"bound":@(allowed.load()!=nullptr),@"preparedStatus":@(prepared.load()),@"lastStatus":@(lastStatus.load()),@"phase":@(lastPhase.load()),@"calls":@(calls.load()),@"originalReturned":@(originalReturned.load()),@"applied":@(applied.load()),@"alreadyPresent":@(alreadyPresent.load()),@"inactive":@(inactive.load()),@"foreignCallsite":@(foreignCallsite.load()),@"failures":@(failures.load()),@"workerForwards":@(workerForwards.load()),@"selection":@(selection.load()),@"selectionLoaded":@(selectionLoaded.load()),@"selectionChanges":@(selectionChanges.load()),@"allForwards":@(allForwards.load())};}
extern "C" __attribute__((visibility("default"))) void ehr_native_ehr_lobby_search_filters(void *filterSet,const void *methodInfo){
#if EHR_LOBBY_SEARCH_BINDING
    using Original=void(*)(void *,const void *);const auto base=EHRNativeHooksImageBaseForDiagnostics();const auto caller=(uintptr_t)__builtin_extract_return_addr(__builtin_return_address(0));
    ++calls;reinterpret_cast<Original>(base+EHRLobbySearchTrampolineRVA)(filterSet,methodInfo);++originalReturned;
    if(!NSThread.isMainThread){++workerForwards;return;}
    if(caller!=base+EHRLobbySearchCallerReturnRVA){++foreignCallsite;return;}
    if(!selected()){++inactive;return;}if(EHRLobbySearchGetSelection()==0){++allForwards;return;}
    if(!permission()||applying){++inactive;return;}
    if(prepared.load()&&EHRLobbySearchPrepare(allowed.load())!=0){++failures;return;}
    if(!filterSet||api.object_get_class(filterSet)!=meta.setClass||(methodInfo&&methodInfo!=meta.helperMethod)){lastStatus.store(EHR_RUNTIME_TYPE_MISMATCH);++failures;return;}
    applying=true;
    @try{try{Root set;auto status=EHRRuntimeActionRootBorrowed(filterSet,&set.token);Result result;if(!status)result=append(set.token,true);else result.status=status;
        lastStatus.store(result.status);lastPhase.store(result.phase);if(result.status)++failures;else if(result.appended)++applied;else if(result.existing)++alreadyPresent;
    }catch(...){lastStatus.store(EHR_RUNTIME_LIMIT);++failures;}}@catch(__unused NSException *error){lastStatus.store(EHR_RUNTIME_NOT_READY);++failures;}
    applying=false;
#else
    (void)filterSet;(void)methodInfo;
#endif
}
NSDictionary *EHRLobbySearchSelfTest(void){
    int32_t status=EHR_RUNTIME_UNSUPPORTED;NSUInteger checks=0;uint32_t phase=0;size_t before=0,after=0;bool okay=false;
#if EHR_LOBBY_SEARCH_BINDING
    @try{try{status=prepare();if(!status)status=ehr_runtime_object_root_count(&before);{Root set;if(!status){phase=15;status=construct(meta.setClass,meta.setCtor,nullptr,0,set);++checks;}
        if(!status){Result first=append(set.token);status=first.status;phase=first.phase;okay=first.appended&&!first.existing;++checks;}
        if(!status){Result second=append(set.token);status=second.status;phase=second.phase;okay=okay&&second.existing&&!second.appended;++checks;}
        if(!status){Root list;status=ehr_runtime_read_field(meta.filters,set.token,&list.token);int32_t length=0;if(!status)status=count(list.token,length);okay=okay&&length==1;++checks;}
        if(!status)status=emptyRegistration();++checks;
    }}catch(...){status=EHR_RUNTIME_LIMIT;}}@catch(__unused NSException *error){status=EHR_RUNTIME_NOT_READY;}
    if(!status)status=ehr_runtime_object_root_count(&after);
#endif
    return @{@"schema":@"ehr.lobby-search-owned-proof.v1",@"success":@(!status&&okay&&before==after),@"status":@(status),@"phase":@(phase),@"checks":@(checks),@"rootsBefore":@(before),@"rootsAfter":@(after),@"realSearchRequests":@0,@"accountActions":@0,@"globalRegistrationWrites":@0,@"hostPacketChanges":@0};
}
