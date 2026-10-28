#include "EHRNativePatchThunks.h"
#include "EHRRuntimeDiagnostics.h"
#include "EHRRuntimeMetadataPrivate.h"
#include "EHRRuntimeActionPrivate.h"
#include "EHRRuntimeIteratorPrivate.h"
#if EHR_HAS_FULL_SOURCE
#include "EHRFullSourceRuntime.h"
#endif
#include <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/vm_prot.h>
#include <dlfcn.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cstring>
#include <cstdlib>
#include <map>
#include <memory>
#include <vector>

namespace {
constexpr size_t MaxSites=512,MaxParameters=128,MaxValue=4096,MaxGenerations=32;
struct API {
    uint32_t (*method_get_param_count)(const void *),(*method_get_token)(const void *),(*method_get_flags)(const void *,uint32_t *);
    const void *(*method_get_param)(const void *,uint32_t),*(*method_get_return_type)(const void *),*(*class_get_type)(const void *);
    void *(*class_from_type)(const void *),*(*object_get_class)(void *);
    bool (*type_is_byref)(const void *),(*class_is_valuetype)(const void *),(*class_is_enum)(const void *),(*class_is_blittable)(const void *),(*class_has_references)(const void *),(*class_is_assignable_from)(const void *,const void *);
    bool (*method_is_generic)(const void *),(*method_is_inflated)(const void *),(*class_is_generic)(const void *),(*class_is_inflated)(const void *);
    uint32_t (*type_get_attrs)(const void *),(*object_header_size)(),(*field_get_offset)(const void *),(*field_get_flags)(const void *);
    int32_t (*class_value_size)(const void *,uint32_t *);
    const void *(*class_enum_basetype)(const void *),*(*field_get_type)(const void *);
    void *(*class_get_fields)(const void *,void **),*(*value_box)(const void *,void *),*(*object_unbox)(void *);
    const char *(*field_get_name)(const void *);char *(*type_get_name)(const void *);void (*free)(void *),(*raise_exception)(void *);
};
void *symbol(const char *name) {
    if(void *value=dlsym(RTLD_DEFAULT,name))return value;
    for(uint32_t i=0;i<_dyld_image_count();++i){const char *path=_dyld_get_image_name(i);if(!path||!strstr(path,"/UnityFramework.framework/UnityFramework"))continue;
        void *handle=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);if(!handle)continue;void *value=dlsym(handle,name);dlclose(handle);if(value)return value;}
    return nullptr;
}
API *api() {
    static API value{};static bool loaded=false;
    if(loaded)return &value;
#define LOAD(name) value.name=reinterpret_cast<decltype(value.name)>(symbol("il2cpp_" #name));if(!value.name)return nullptr
    LOAD(method_get_param_count);LOAD(method_get_token);LOAD(method_get_flags);LOAD(method_get_param);LOAD(method_get_return_type);LOAD(class_get_type);LOAD(class_from_type);LOAD(object_get_class);
    LOAD(type_is_byref);LOAD(class_is_valuetype);LOAD(class_is_enum);LOAD(class_is_blittable);LOAD(class_has_references);LOAD(class_is_assignable_from);LOAD(type_get_attrs);LOAD(object_header_size);
    LOAD(method_is_generic);LOAD(method_is_inflated);LOAD(class_is_generic);LOAD(class_is_inflated);
    LOAD(field_get_offset);LOAD(field_get_flags);LOAD(class_value_size);LOAD(class_enum_basetype);LOAD(field_get_type);LOAD(class_get_fields);LOAD(value_box);LOAD(object_unbox);LOAD(field_get_name);LOAD(type_get_name);LOAD(free);LOAD(raise_exception);
#undef LOAD
    loaded=true;return &value;
}
struct Mapping {
    uintptr_t base=0;const mach_header_64 *header=nullptr;
    bool range(uint64_t rva,size_t size,vm_prot_t protection)const {
        if(!header||!size||rva>UINTPTR_MAX-base||size>UINTPTR_MAX-(base+rva))return false;
        const uint8_t *cursor=reinterpret_cast<const uint8_t *>(header+1),*end=cursor+header->sizeofcmds;
        for(uint32_t i=0;i<header->ncmds;++i){if(size_t(end-cursor)<sizeof(load_command))return false;auto *c=reinterpret_cast<const load_command *>(cursor);if(c->cmdsize<sizeof(*c)||c->cmdsize>size_t(end-cursor))return false;
            if(c->cmd==LC_SEGMENT_64&&c->cmdsize>=sizeof(segment_command_64)){auto *s=reinterpret_cast<const segment_command_64 *>(c);
                // This app's preferred __TEXT base is0; require it rather than
                // silently treating arbitrary preferred addresses as RVAs.
                bool wxCompatible=!((protection&VM_PROT_EXECUTE)&&(s->initprot&VM_PROT_WRITE))&&!((protection&VM_PROT_WRITE)&&(s->initprot&VM_PROT_EXECUTE));
                if(wxCompatible&&(s->initprot&protection)==protection&&s->filesize<=s->vmsize&&rva>=s->vmaddr&&rva-s->vmaddr<=s->filesize&&size<=s->filesize-(rva-s->vmaddr))return true;}
            cursor+=c->cmdsize;}
        return false;
    }
};
Mapping mapping(const uint8_t *uuid) {
    Mapping result;size_t matches=0;
    if(!uuid)return result;
    for(uint32_t i=0;i<_dyld_image_count();++i){const char *path=_dyld_get_image_name(i);if(!path||!strstr(path,"/UnityFramework.framework/UnityFramework"))continue;
        auto *h=reinterpret_cast<const mach_header_64 *>(_dyld_get_image_header(i));if(!h||h->magic!=MH_MAGIC_64||h->ncmds>16384||h->sizeofcmds>16*1024*1024)continue;
        const uint8_t *cursor=reinterpret_cast<const uint8_t *>(h+1),*end=cursor+h->sizeofcmds;bool match=false,zeroText=false;
        for(uint32_t n=0;n<h->ncmds;++n){if(size_t(end-cursor)<sizeof(load_command))break;auto *c=reinterpret_cast<const load_command *>(cursor);if(c->cmdsize<sizeof(*c)||c->cmdsize>size_t(end-cursor))break;
            if(c->cmd==LC_UUID&&c->cmdsize==sizeof(uuid_command))match=memcmp(reinterpret_cast<const uuid_command *>(c)->uuid,uuid,16)==0;
            if(c->cmd==LC_SEGMENT_64&&c->cmdsize>=sizeof(segment_command_64)){auto *s=reinterpret_cast<const segment_command_64 *>(c);if(strncmp(s->segname,"__TEXT",16)==0)zeroText=s->vmaddr==0&&s->fileoff==0;}
            cursor+=c->cmdsize;}
        if(match&&zeroText){result={reinterpret_cast<uintptr_t>(h),h};++matches;}}
    return matches==1?result:Mapping{};
}
bool hashMatches(const void *bytes,size_t count,const uint8_t *expected) {
    if(count>UINT32_MAX)return false;uint8_t digest[32];CC_SHA256(bytes,CC_LONG(count),digest);return memcmp(digest,expected,32)==0;
}
const void *installedOriginal(const EHRNativePatchSiteV1 &site) {
    const auto *i=site.install;if(!i||i->method_rva!=site.method_rva||i->trampoline_bytes<8||i->trampoline_bytes>48||i->trampoline_bytes%4||i->trampoline_rva!=i->stub_rva+16)return nullptr;
    Mapping m=mapping(site.framework_uuid);if(!m.base||!m.range(i->method_rva,4,VM_PROT_READ|VM_PROT_EXECUTE)||!m.range(i->stub_rva,16,VM_PROT_READ|VM_PROT_EXECUTE)||!m.range(i->trampoline_rva,i->trampoline_bytes,VM_PROT_READ|VM_PROT_EXECUTE)||!m.range(i->got_rva,8,VM_PROT_READ|VM_PROT_WRITE))return nullptr;
    uint32_t entry=0;memcpy(&entry,reinterpret_cast<void *>(m.base+i->method_rva),4);
    if(entry!=i->entry_branch||(entry&0xFC000000)!=0x14000000)return nullptr;
    int64_t delta=int64_t(entry&0x03FFFFFF);if(delta&(1<<25))delta-=int64_t(1)<<26;
    if(int64_t(i->method_rva)+delta*4!=int64_t(i->stub_rva))return nullptr;
    void *handler=nullptr;memcpy(&handler,reinterpret_cast<void *>(m.base+i->got_rva),8);
    if(handler!=site.handler||!hashMatches(reinterpret_cast<void *>(m.base+i->stub_rva),16,i->stub_sha256)||!hashMatches(reinterpret_cast<void *>(m.base+i->trampoline_rva),i->trampoline_bytes,i->trampoline_sha256))return nullptr;
    return reinterpret_cast<void *>(m.base+i->trampoline_rva);
}
struct Prepared {const EHRNativePatchSiteV1 *site;EHRManagedPatchSignatureV1 signature;std::vector<EHRManagedPatchParameterV1> parameters;std::vector<const void *> classes;};
std::map<uint64_t,const EHRNativePatchSiteV1 *> compiled;
std::atomic<EHRSourcePatchFailureV1> sourceFailure{nullptr};
std::map<uint64_t,std::shared_ptr<const Prepared>> prepared;
using Active=std::vector<uint64_t>;std::vector<std::unique_ptr<Active>> generations;std::atomic<const Active *> active{nullptr};
bool typeName(API &a,const void *type,const char *expected) {
    if(!expected||!type)return false;char *value=a.type_get_name(type);bool same=value&&strnlen(value,4097)<=4096&&strcmp(value,expected)==0;if(value)a.free(value);return same;
}
bool typeMatches(API &a,const EHRNativePatchTypeV1 &expected,const void *klass) {
    if(!klass||!typeName(a,a.class_get_type(klass),expected.runtime_name))return false;
    if(a.class_is_generic(klass)&&!a.class_is_inflated(klass))return false;
    bool value=a.class_is_valuetype(klass);if((expected.kind==2)!=value)return false;if(!value)return expected.kind==1&&expected.size==8;
    uint32_t alignment=0;int32_t size=a.class_value_size(klass,&alignment);
    if(size<=0||uint32_t(size)!=expected.size||alignment!=expected.alignment||size>int32_t(MaxValue)||a.class_has_references(klass)!=bool(expected.flags&1)||((expected.flags&32)&&a.class_is_blittable(klass)!=bool(expected.flags&2))||a.class_is_enum(klass)!=bool(expected.flags&16))return false;
    if((expected.flags&1)==0&&!a.class_is_blittable(klass)&&!(expected.flags&(4|8)))return false;
    if((expected.flags&4)&&!(size==1&&alignment==1&&strcmp(expected.runtime_name,"System.Boolean")==0))return false;
    if((expected.flags&8)&&!(size==2&&alignment==2&&strcmp(expected.runtime_name,"System.Char")==0))return false;
    if((expected.flags&16)&&!typeName(a,a.class_enum_basetype(klass),expected.enum_underlying))return false;
    if(expected.field_count){uint32_t header=a.object_header_size();if(header!=16||!expected.fields||expected.field_count>4096)return false;
        void *iterator=nullptr;size_t index=0;bool complete=false;
        for(size_t n=0;n<4096;++n){const void *field=a.class_get_fields(klass,&iterator);if(!field){complete=true;break;}if(a.field_get_flags(field)&0x10)continue;
            if(index>=expected.field_count)return false;const auto &f=expected.fields[index++];const char *name=a.field_get_name(field);uint32_t offset=a.field_get_offset(field);
            if(!name||strcmp(name,f.name)||offset<header||offset-header!=f.value_offset||!typeName(a,a.field_get_type(field),f.runtime_type))return false;}
        if(!complete||index!=expected.field_count)return false;}
    return true;
}
int32_t validate(uint64_t id) {
    struct FailureDeactivates {bool success=false;~FailureDeactivates(){if(!success)active.store(nullptr,std::memory_order_release);}} guard;
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    auto it=compiled.find(id);if(it==compiled.end())return EHR_RUNTIME_NOT_FOUND;const auto &s=*it->second;
    if(!s.source_binding_supported)return EHR_RUNTIME_UNSUPPORTED;
    if(!installedOriginal(s))return EHR_RUNTIME_NOT_READY;
    API *a=api();if(!a)return EHR_RUNTIME_NOT_FOUND;
    Prepared p{&s,{},std::vector<EHRManagedPatchParameterV1>(s.parameter_count),{}};
    auto status=ehr_source_patch_signature_v1(id,&p.signature,sizeof(p.signature),p.parameters.empty()?nullptr:p.parameters.data(),p.parameters.size());if(status)return status;
    auto &signature=p.signature;if(signature.abi_version!=1||signature.byte_size!=48||signature.parameter_count!=s.parameter_count||signature.flags!=s.signature_flags||signature.expected_rva!=s.method_rva)return EHR_RUNTIME_TYPE_MISMATCH;
    uint64_t observed=0;status=ehr_runtime_validate_native_method(signature.method,s.method_rva,&observed);if(status)return status;
    const void *method=nullptr,*owner=nullptr,*ownerClass=nullptr;status=EHRRuntimeBorrowMethod(signature.method,&method,&owner);if(status)return status;
    if(a->method_is_generic(method)&&!a->method_is_inflated(method))return EHR_RUNTIME_UNSUPPORTED;
    if(EHRRuntimeBorrowClass(signature.owner_class,&ownerClass)!=EHR_RUNTIME_OK||ownerClass!=owner||a->method_get_token(method)!=s.metadata_token||a->method_get_param_count(method)!=s.parameter_count)return EHR_RUNTIME_TYPE_MISMATCH;
    uint32_t ignored=0;bool isStatic=(a->method_get_flags(method,&ignored)&0x10)!=0;if(isStatic==bool(s.signature_flags&1))return EHR_RUNTIME_TYPE_MISMATCH;
    if(s.owner&&!typeMatches(*a,*s.owner,owner))return EHR_RUNTIME_TYPE_MISMATCH;
    for(size_t i=0;i<s.parameter_count;++i){const auto &expected=s.parameters[i];const auto &actual=p.parameters[i];const void *klass=nullptr,*type=a->method_get_param(method,uint32_t(i));
        if(actual.reserved||actual.flags!=(expected.flags&7)||!type||a->type_is_byref(type)!=bool(expected.flags&2)||bool(a->type_get_attrs(type)&2)!=bool(expected.flags&4)||EHRRuntimeBorrowClass(actual.value_class,&klass)!=EHR_RUNTIME_OK||a->class_from_type(type)!=klass||!typeMatches(*a,*expected.type,klass))return EHR_RUNTIME_TYPE_MISMATCH;
        if((expected.flags&2)&&(expected.type->flags&1))return EHR_RUNTIME_UNSUPPORTED;p.classes.push_back(klass);}
    const void *returnType=a->method_get_return_type(method),*returnClass=a->class_from_type(returnType);
    if(s.result->kind==0){if(signature.result_class||!typeName(*a,returnType,"System.Void"))return EHR_RUNTIME_TYPE_MISMATCH;}
    else {const void *klass=nullptr;if(EHRRuntimeBorrowClass(signature.result_class,&klass)!=EHR_RUNTIME_OK||klass!=returnClass||!typeMatches(*a,*s.result,klass))return EHR_RUNTIME_TYPE_MISMATCH;if(s.result->flags&1)return EHR_RUNTIME_UNSUPPORTED;}
    try{auto immutable=std::make_shared<const Prepared>(std::move(p));prepared.insert_or_assign(id,std::move(immutable));guard.success=true;return EHR_RUNTIME_OK;}catch(...){return EHR_RUNTIME_LIMIT;}
}
int32_t deactivate(){active.store(nullptr,std::memory_order_release);if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;return EHR_RUNTIME_OK;}
int32_t activate(const uint64_t *ids,size_t count) {
    active.store(nullptr,std::memory_order_release);
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    if(count>MaxSites||(count&&!ids))return EHR_RUNTIME_BAD_ARGUMENT;if(generations.size()>=MaxGenerations)return EHR_RUNTIME_LIMIT;
    try{auto next=std::make_unique<Active>();if(count)next->assign(ids,ids+count);std::sort(next->begin(),next->end());if(std::adjacent_find(next->begin(),next->end())!=next->end())return EHR_RUNTIME_BAD_ARGUMENT;
        for(uint64_t id:*next){auto status=validate(id);if(status)return status;}auto *published=next.get();generations.push_back(std::move(next));active.store(published,std::memory_order_release);return EHR_RUNTIME_OK;
    }catch(...){return EHR_RUNTIME_LIMIT;}
}
struct Roots {std::vector<EHRRuntimeToken> tokens;~Roots(){for(auto token:tokens)if(token)ehr_runtime_object_release(token);}void add(EHRRuntimeToken t){if(t)tokens.push_back(t);}};
bool overlap(const void *left,size_t n,const void *right,size_t m){auto l=reinterpret_cast<uintptr_t>(left),r=reinterpret_cast<uintptr_t>(right);return n&&m&&l<r+m&&r<l+n;}
bool valid(const void *pointer,size_t count,size_t alignment){auto p=reinterpret_cast<uintptr_t>(pointer);return pointer&&!(p&(alignment-1))&&count<=UINTPTR_MAX-p;}
int32_t rootReference(API &a,void *value,const void *expected,EHRRuntimeToken *out){if(value&&(!a.class_is_assignable_from(expected,a.object_get_class(value))))return EHR_RUNTIME_TYPE_MISMATCH;return EHRRuntimeActionRootBorrowed(value,out);}
}

EHRRuntimeStatus EHRNativePatchRegisterCompiled(const EHRNativePatchSiteV1 *const *sites,size_t count) {
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;if(!compiled.empty()||count>MaxSites||(count&&!sites))return EHR_RUNTIME_BAD_ARGUMENT;
    try {std::map<uint64_t,const EHRNativePatchSiteV1 *> next;for(size_t i=0;i<count;++i){auto *s=sites[i];if(!s||!s->target_id||!s->handler||!s->framework_uuid||!s->result||s->parameter_count>MaxParameters||(s->parameter_count&&!s->parameters)||!next.emplace(s->target_id,s).second)return EHR_RUNTIME_BAD_ARGUMENT;}compiled.swap(next);return EHR_RUNTIME_OK;}catch(...){return EHR_RUNTIME_LIMIT;}
}
void EHRNativePatchMakeTargetsTable(EHRManagedPatchTargetsV1 *table){if(table)*table={1,sizeof(*table),validate,activate,deactivate};}
EHRRuntimeStatus EHRNativePatchBindFailureDiagnostics(EHRSourcePatchFailureV1 callback) {
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    if(!callback)return EHR_RUNTIME_BAD_ARGUMENT;
    auto previous=sourceFailure.load(std::memory_order_acquire);
    if(previous&&previous!=callback)return EHR_RUNTIME_BAD_ARGUMENT;
    sourceFailure.store(callback,std::memory_order_release);return EHR_RUNTIME_OK;
}
uintptr_t EHRNativePatchOriginal(const EHRNativePatchSiteV1 &site){const void *value=installedOriginal(site);if(!value)abort();return reinterpret_cast<uintptr_t>(value);}
bool EHRNativePatchShouldDispatch(const EHRNativePatchSiteV1 &site){
    if(!NSThread.isMainThread){ehr_diagnostics::state().checked(EHRDiagnosticTick(),site.target_id,site.method_rva,false,false);return false;}
#if EHR_HAS_FULL_SOURCE
    EHRFullSourceBeforeTarget(site.target_id);
#endif
    const auto *set=active.load(std::memory_order_acquire);const bool enabled=set&&std::binary_search(set->begin(),set->end(),site.target_id);
    ehr_diagnostics::state().checked(EHRDiagnosticTick(),site.target_id,site.method_rva,enabled,true);return enabled;
}

EHRNativePatchOutcomeV1 EHRNativePatchInvokePrepared(const EHRNativePatchSiteV1 &site,void *receiver,const EHRNativePatchArgumentV1 *arguments,size_t count,void *result,size_t resultBytes) {
    EHRNativePatchOutcomeV1 outcome{EHR_RUNTIME_NOT_READY,false,0,{}};
    struct Trace {EHRDiagnosticRouteScope scope;EHRNativePatchOutcomeV1 &value;
        Trace(const EHRNativePatchSiteV1 &s,EHRNativePatchOutcomeV1 &v):scope(s.target_id,s.method_rva),value(v){}
        ~Trace(){scope.status=value.status;scope.flags=(value.dispatcher_entered?1:0)|(value.exception?2:0)|
            (value.proof.original_attempted?4:0)|(value.proof.runtime_entered?8:0)|(value.proof.permit_consumed?16:0)|
            (value.proof.hook_consumptions?32:0)|(value.proof.target_found?64:0);}} trace(site,outcome);
    trace.scope.at(1);
    if(!NSThread.isMainThread){outcome.status=EHR_RUNTIME_WRONG_THREAD;return outcome;}
    trace.scope.at(2);
    auto it=prepared.find(site.target_id);if(it==prepared.end()||it->second->site!=&site)return outcome;
    trace.scope.at(3);
    if(count!=site.parameter_count||(count&&!arguments)||count>MaxParameters){outcome.status=EHR_RUNTIME_BAD_ARGUMENT;return outcome;}
    // A callback may reenter validation/activation. Keep this frame's immutable
    // metadata alive independently of subsequent registry publications.
    const auto immutable=it->second;const auto &p=*immutable;trace.scope.at(4);API *a=api();if(!a)return outcome;
    const size_t expectedResult=site.result->kind?site.result->size:0;
    trace.scope.at(5);
    if(resultBytes!=expectedResult||(expectedResult&&!valid(result,resultBytes,site.result->alignment))){outcome.status=EHR_RUNTIME_BAD_ARGUMENT;return outcome;}
    for(size_t i=0;i<count;++i){trace.scope.at(6,uint32_t(i+1));const auto &d=site.parameters[i];const auto &input=arguments[i];if(input.size!=d.type->size||!valid(input.input,input.size,d.type->alignment)||bool(input.output)!=bool((d.flags&2)&&!(d.flags&8))){outcome.status=EHR_RUNTIME_BAD_ARGUMENT;return outcome;}
        if(input.output){trace.scope.at(7,uint32_t(i+1));if(!valid(input.output,input.size,d.type->alignment)||overlap(input.output,input.size,result,resultBytes)){outcome.status=EHR_RUNTIME_BAD_ARGUMENT;return outcome;}for(size_t j=0;j<i;++j)if(arguments[j].output&&overlap(input.output,input.size,arguments[j].output,arguments[j].size)){outcome.status=EHR_RUNTIME_BAD_ARGUMENT;return outcome;}}}
    for(size_t i=0;i<count;++i)if(arguments[i].output)for(size_t j=0;j<count;++j)
        if(i!=j&&(site.parameters[j].flags&2)&&overlap(arguments[i].output,arguments[i].size,arguments[j].input,arguments[j].size)){trace.scope.at(8,uint32_t(i+1));outcome.status=EHR_RUNTIME_BAD_ARGUMENT;return outcome;}
    // Reserve ownership bookkeeping BEFORE allocations or source entry.
    trace.scope.at(9);
    Roots roots;std::vector<uint8_t> copies;std::array<size_t,MaxParameters> offsets{};size_t copyBytes=0;
    for(size_t i=0;i<count;++i)if(arguments[i].output){offsets[i]=copyBytes;copyBytes+=arguments[i].size;if(copyBytes>65536){EHRDiagnosticLimit(ehr_diagnostics::ThunkCopyBytes,copyBytes,65536);outcome.status=EHR_RUNTIME_LIMIT;return outcome;}}
    try{roots.tokens.reserve(2*count+4);copies.resize(copyBytes);}catch(...){EHRDiagnosticLimit(ehr_diagnostics::ThunkAllocation,0,0);outcome.status=EHR_RUNTIME_LIMIT;return outcome;}
    std::array<uint64_t,MaxParameters> inputs{},refs{};uint64_t owner=0,returned=0,error=0;
    if(site.signature_flags&1){const void *ownerClass=nullptr;trace.scope.at(10);if(!receiver){outcome.status=EHR_RUNTIME_TYPE_MISMATCH;return outcome;}trace.scope.at(11);if(EHRRuntimeBorrowClass(p.signature.owner_class,&ownerClass)!=EHR_RUNTIME_OK){outcome.status=EHR_RUNTIME_TYPE_MISMATCH;return outcome;}trace.scope.at(12);outcome.status=rootReference(*a,receiver,ownerClass,&owner);roots.add(owner);if(outcome.status)return outcome;}
    alignas(8) uint8_t zero[MaxValue]{};
    for(size_t i=0;i<count;++i){const auto &d=site.parameters[i];void *payload=(d.flags&4)?zero:arguments[i].input;
        if(d.type->kind==1){trace.scope.at(13,uint32_t(i+1));void *value=nullptr;memcpy(&value,payload,sizeof(value));outcome.status=rootReference(*a,value,p.classes[i],&inputs[i]);}
        else { // Public value_box copies from a real native invocation frame.
            // Reference-containing payloads never enter a CLR byte buffer.
            trace.scope.at(14,uint32_t(i+1));void *boxed=a->value_box(p.classes[i],payload);outcome.status=boxed?EHRRuntimeActionRootBorrowed(boxed,&inputs[i]):EHR_RUNTIME_NOT_READY;
        }
        roots.add(inputs[i]);if(outcome.status)return outcome;
    }
    trace.scope.at(15);
    outcome.status=ehr_source_patch_dispatch_v2(site.target_id,owner,count?inputs.data():nullptr,count,&returned,&error,count?refs.data():nullptr,count,&outcome.proof,sizeof(outcome.proof));
    outcome.dispatcher_entered=outcome.proof.dispatcher_entered!=0;roots.add(returned);for(size_t i=0;i<count;++i)roots.add(refs[i]);
    // The exception remains rooted until Finish raises it, after this helper
    // and every NativeAOT frame return. Copybacks happen even on that path.
    struct ExceptionRoot {uint64_t token;~ExceptionRoot(){if(token)ehr_runtime_object_release(token);}} exceptionRoot{error};
    outcome.exception=error;auto transfer=[&](){exceptionRoot.token=0;return outcome;};
    // Optional diagnostics cannot alter the saved outcome or escape past owned
    // output/exception roots, even if a faulty observer throws natively.
    if(outcome.status){@try{try{if(auto copy=sourceFailure.load(std::memory_order_acquire)){
        uint32_t words[12]{};if(copy(site.target_id,words,12)==0)EHRDiagnosticSourceFailure(site.target_id,outcome.status,words,12);
    }}catch(...) {}}@catch(__unused NSException *failure){}}
    if(!outcome.dispatcher_entered){outcome.exception=0;return outcome;}
    if(outcome.proof.abi_version!=2||outcome.proof.byte_size!=32||outcome.proof.target_found!=1||outcome.proof.dispatcher_entered!=1){trace.scope.at(16);outcome.status=EHR_RUNTIME_TYPE_MISMATCH;return transfer();}
    alignas(8) uint8_t returnedBytes[MaxValue]{};void *returnedObject=nullptr;
    for(size_t i=0;i<count;++i){if(!arguments[i].output)continue;trace.scope.at(17,uint32_t(i+1));if(!refs[i]){if(outcome.status!=EHR_RUNTIME_OK)continue;outcome.status=EHR_RUNTIME_TYPE_MISMATCH;return transfer();}uint64_t actual=0;size_t size=0;
        auto status=ehr_runtime_object_class(refs[i],&actual);if(status==EHR_RUNTIME_OK&&actual!=p.parameters[i].value_class)status=EHR_RUNTIME_TYPE_MISMATCH;
        if(status==EHR_RUNTIME_OK)status=ehr_runtime_copy_value(refs[i],copies.data()+offsets[i],arguments[i].size,&size);
        if(status!=EHR_RUNTIME_OK||size!=arguments[i].size){outcome.status=status==EHR_RUNTIME_OK?EHR_RUNTIME_TYPE_MISMATCH:status;return transfer();}
        if(site.parameters[i].type->flags&4)copies[offsets[i]]=copies[offsets[i]]?1:0;
    }
    if(outcome.status==EHR_RUNTIME_OK&&expectedResult){trace.scope.at(18);uint64_t actual=0;auto status=returned?ehr_runtime_object_class(returned,&actual):EHR_RUNTIME_OK;
        if(site.result->kind==1){const void *expected=nullptr;if(status==EHR_RUNTIME_OK)status=EHRRuntimeBorrowClass(p.signature.result_class,&expected);if(status==EHR_RUNTIME_OK)status=EHRRuntimeIteratorBorrow(returned,&returnedObject);if(status==EHR_RUNTIME_OK&&returnedObject&&!a->class_is_assignable_from(expected,a->object_get_class(returnedObject)))status=EHR_RUNTIME_TYPE_MISMATCH;}
        else {size_t size=0;if(!returned||actual!=p.signature.result_class)status=EHR_RUNTIME_TYPE_MISMATCH;if(status==EHR_RUNTIME_OK)status=ehr_runtime_copy_value(returned,returnedBytes,expectedResult,&size);if(status==EHR_RUNTIME_OK&&size!=expectedResult)status=EHR_RUNTIME_TYPE_MISMATCH;if(site.result->flags&4)returnedBytes[0]=returnedBytes[0]?1:0;}
        if(status!=EHR_RUNTIME_OK){outcome.status=status;return transfer();}}
    trace.scope.at(outcome.status==EHR_RUNTIME_OK?19:15);
    // Commit only after every ref/result conversion validates. No managed call
    // occurs between these writes and their completion.
    for(size_t i=0;i<count;++i)if(arguments[i].output&&refs[i])memcpy(arguments[i].output,copies.data()+offsets[i],arguments[i].size);
    if(outcome.status==EHR_RUNTIME_OK&&expectedResult){if(site.result->kind==1)memcpy(result,&returnedObject,8);else memcpy(result,returnedBytes,expectedResult);}
    return transfer();
}
void EHRNativePatchFinish(EHRNativePatchOutcomeV1 outcome) {
    if(!outcome.dispatcher_entered)abort();
    EHRNativeRaiseOwnedFailure(outcome.status,outcome.exception);
}
void EHRNativeRaiseOwnedFailure(int32_t status,EHRRuntimeToken owned_exception) {
    if(owned_exception){struct Release{uint64_t token;~Release(){ehr_runtime_object_release(token);}} release{owned_exception};void *exception=nullptr;API *a=api();if(!a||EHRRuntimeIteratorBorrow(owned_exception,&exception)!=EHR_RUNTIME_OK||!exception)abort();a->raise_exception(exception);abort();}
    if(status!=EHR_RUNTIME_OK)EHRRuntimeIteratorRaise(static_cast<EHRRuntimeStatus>(status));
}
EHRRuntimeStatus EHRNativePatchBoxBorrowedValue(EHRRuntimeToken token,const EHRNativePatchTypeV1 &expected,void *payload,size_t count,EHRRuntimeToken *owned) {
    if(!owned)return EHR_RUNTIME_BAD_ARGUMENT;*owned=0;
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    if(expected.kind!=2||!expected.alignment||count!=expected.size||count>MaxValue||!valid(payload,count,expected.alignment))return EHR_RUNTIME_BAD_ARGUMENT;
    const void *klass=nullptr;auto status=EHRRuntimeBorrowClass(token,&klass);if(status)return status;
    API *a=api();if(!a)return EHR_RUNTIME_NOT_FOUND;if(!typeMatches(*a,expected,klass))return EHR_RUNTIME_TYPE_MISMATCH;
    void *boxed=a->value_box(klass,payload);return boxed?EHRRuntimeActionRootBorrowed(boxed,owned):EHR_RUNTIME_NOT_READY;
}
NSDictionary *EHRNativePatchBoxedReferenceSelfTest(const EHRNativePatchTypeV1 &descriptor,const char *image,const char *space,const char *name,const char *referenceField) {
    if(!NSThread.isMainThread)return @{@"pass":@NO,@"status":@(EHR_RUNTIME_WRONG_THREAD)};
    API *a=api();if(!a||!(descriptor.flags&1))return @{@"pass":@NO,@"status":@(EHR_RUNTIME_UNSUPPORTED)};
    struct Root {uint64_t value=0;~Root(){if(value)ehr_runtime_object_release(value);}int release(){if(!value)return EHR_RUNTIME_OK;auto token=value;value=0;return ehr_runtime_object_release(token);}} original,text,pin,copy,read;
    uint64_t klass=0,field=0;int32_t status=ehr_runtime_find_class(image,space,name,&klass);std::vector<uint64_t> zero((descriptor.size+7)/8,0);
    if(status==EHR_RUNTIME_OK)status=EHRNativePatchBoxBorrowedValue(klass,descriptor,zero.data(),descriptor.size,&original.value);
    const uint16_t units[]={'E','H','R',0,'V'};if(status==EHR_RUNTIME_OK)status=ehr_runtime_string_create(units,5,&text.value);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_field(klass,referenceField,"System.String",0,&field);
    EHRRuntimeArgument string{EHR_RUNTIME_REFERENCE,0,text.value,nullptr,0};if(status==EHR_RUNTIME_OK)status=ehr_runtime_write_field(field,original.value,&string);
    void *object=nullptr;if(status==EHR_RUNTIME_OK)status=EHRRuntimeIteratorPin(original.value,&pin.value,&object);
    if(status==EHR_RUNTIME_OK){void *payload=a->object_unbox(object);status=payload?EHRNativePatchBoxBorrowedValue(klass,descriptor,payload,descriptor.size,&copy.value):EHR_RUNTIME_TYPE_MISMATCH;}
    bool inputsReleased=pin.release()==EHR_RUNTIME_OK&&original.release()==EHR_RUNTIME_OK&&text.release()==EHR_RUNTIME_OK;
    auto collect=reinterpret_cast<void (*)(int32_t)>(symbol("il2cpp_gc_collect"));auto generation=reinterpret_cast<int32_t (*)()>(symbol("il2cpp_gc_max_generation"));bool collected=false;
    if(status==EHR_RUNTIME_OK&&collect&&generation){collect(generation());collected=true;}
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_read_field(field,copy.value,&read.value);uint16_t returned[5]{};size_t length=0;
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_string_copy(read.value,returned,5,&length);
    bool stringExact=status==EHR_RUNTIME_OK&&length==5&&memcmp(units,returned,sizeof(units))==0;
    alignas(8) uint8_t forbidden[MaxValue];memset(forbidden,0xA7,sizeof(forbidden));size_t bytes=0;
    auto rawStatus=copy.value?ehr_runtime_copy_value(copy.value,forbidden,descriptor.size,&bytes):EHR_RUNTIME_NOT_READY;bool untouched=true;for(auto byte:forbidden)untouched&=byte==0xA7;
    bool rootsReleased=read.release()==EHR_RUNTIME_OK&&copy.release()==EHR_RUNTIME_OK;
    return @{@"pass":@(status==EHR_RUNTIME_OK&&inputsReleased&&rootsReleased&&stringExact&&rawStatus==EHR_RUNTIME_UNSUPPORTED&&untouched),@"status":@(status),@"inputRootsReleasedBeforeReadback":@(inputsReleased),@"stringReferencePreserved":@(stringExact),@"normalCollectionPerformed":@(collected),@"normalCollectionExportsAvailable":@(collect&&generation),@"rawReferencePayloadRejected":@(rawStatus==EHR_RUNTIME_UNSUPPORTED&&untouched),@"ownedRootsReleased":@(rootsReleased),@"targetInvocations":@0,@"referencePayloadBytesCrossedToCLR":@0};
}
