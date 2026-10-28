#import "EHRClassLayoutPreflight.h"
#include "EHRClassLayoutCore.hpp"
#include "EHRRuntimeGateway.h"
#include <algorithm>
#include <dlfcn.h>
#include <mach/mach.h>
#include <set>

namespace ehr_class_layout_runtime {
using P = const void *;
using Iterator = P (*)(P, void **);
struct API {
    P (*domain_get)();
    const P *(*domain_get_assemblies)(P, size_t *);
    P (*assembly_get_image)(P);
    const char *(*image_get_name)(P);
    P (*class_from_name)(P, const char *, const char *);
    P (*class_get_image)(P), (*class_get_type)(P), (*class_get_parent)(P), (*class_get_declaring_type)(P), (*class_get_element_class)(P);
    const char *(*class_get_name)(P), *(*class_get_namespace)(P);
    uint32_t (*class_instance_size)(P), (*class_get_flags)(P), (*class_get_type_token)(P), (*class_num_fields)(P), (*class_get_rank)(P);
    bool (*class_has_references)(P), (*class_is_inited)(P), (*class_is_valuetype)(P);
    bool (*class_is_assignable_from)(P,P);
    Iterator class_get_methods, class_get_fields, class_get_properties, class_get_events, class_get_nested_types, class_get_interfaces;
    int (*type_get_type)(P);
    uint32_t (*type_get_attrs)(P);
    bool (*type_is_byref)(P);
    P (*class_from_type)(P);
    const char *(*method_get_name)(P);
    P (*method_get_declaring_type)(P), (*object_get_virtual_method)(P, P);
    uint32_t (*method_get_token)(P), (*method_get_param_count)(P), (*method_get_flags)(P, uint32_t *);
    P (*string_new_utf16)(const uint16_t *,int32_t),(*value_box)(P,void *);
    uint32_t (*gchandle_new)(P,bool);
    P (*gchandle_get_target)(uint32_t);
    void (*gchandle_free)(uint32_t);
};
bool copy(uintptr_t address, void *output, size_t size) {
    if (!address || !output || size > 65536 || size > UINTPTR_MAX-address) return false;
    static_assert(sizeof(vm_address_t)==sizeof(uintptr_t));
    vm_size_t actual = 0;
    return vm_read_overwrite(mach_task_self(), static_cast<vm_address_t>(address), size,
        reinterpret_cast<vm_address_t>(output), &actual) == KERN_SUCCESS && actual == size;
}
NSString *string(P address) {
    if (!address) return @"";
    char value[257]{};
    for(size_t i=0;i<sizeof(value)-1;++i) {
        if(!copy(reinterpret_cast<uintptr_t>(address)+i,&value[i],1))return @"<unreadable>";
        if(!value[i])return [NSString stringWithUTF8String:value] ?: @"<invalid_utf8>";
    }
    return @"<over_limit>";
}
bool load(API &api,void *(*lookup)(const char *)) {
    bool complete = true;
#define API_LOAD(name) api.name = reinterpret_cast<decltype(api.name)>(lookup("il2cpp_" #name)); complete = complete && api.name
    API_LOAD(domain_get); API_LOAD(domain_get_assemblies); API_LOAD(assembly_get_image); API_LOAD(image_get_name); API_LOAD(class_from_name);
    API_LOAD(class_get_image); API_LOAD(class_get_type); API_LOAD(class_get_parent); API_LOAD(class_get_declaring_type); API_LOAD(class_get_element_class);
    API_LOAD(class_get_name); API_LOAD(class_get_namespace); API_LOAD(class_instance_size); API_LOAD(class_get_flags); API_LOAD(class_get_type_token);
    API_LOAD(class_num_fields); API_LOAD(class_get_rank); API_LOAD(class_has_references); API_LOAD(class_is_inited); API_LOAD(class_is_valuetype);
    API_LOAD(class_is_assignable_from);
    API_LOAD(class_get_methods); API_LOAD(class_get_fields); API_LOAD(class_get_properties); API_LOAD(class_get_events); API_LOAD(class_get_nested_types); API_LOAD(class_get_interfaces);
    API_LOAD(type_get_type); API_LOAD(type_get_attrs); API_LOAD(type_is_byref); API_LOAD(class_from_type);
    API_LOAD(method_get_name); API_LOAD(method_get_declaring_type); API_LOAD(object_get_virtual_method); API_LOAD(method_get_token); API_LOAD(method_get_param_count); API_LOAD(method_get_flags);
    API_LOAD(string_new_utf16); API_LOAD(value_box); API_LOAD(gchandle_new); API_LOAD(gchandle_get_target); API_LOAD(gchandle_free);
#undef API_LOAD
    return complete;
}
P find(const API &api, const char *imageName, const char *space, const char *name, const char *nested = nullptr) {
    size_t count = 0; const auto assemblies = api.domain_get_assemblies(api.domain_get(), &count);
    if (!assemblies || count > 4096) return nullptr;
    P found = nullptr;
    for(size_t i=0;i<count;++i) {
        const P image=api.assembly_get_image(assemblies[i]);
        if(![string(api.image_get_name(image)) isEqualToString:@(imageName)])continue;
        if(found)return nullptr;
        found=api.class_from_name(image,space,name);
    }
    if(!found||!nested)return found;
    void *cursor=nullptr;
    for(size_t i=0;i<4096;++i) {
        P child=api.class_get_nested_types(found,&cursor); if(!child)return nullptr;
        if([string(api.class_get_name(child)) isEqualToString:@(nested)])return child;
    }
    return nullptr;
}
bool collect(P klass, Iterator iterator, ehr_class_preflight::Collection &collection) {
    collection.publicBase=0;
    collection.publicEntries.clear();
    void *cursor = nullptr;
    std::set<P> seen;
    for(size_t i=0;i<=4096;++i) {
        P entry=iterator(klass,&cursor); if(!entry)return true;
        if(i==4096||!cursor||!seen.insert(entry).second)return false;
        if(i==0)collection.publicBase=reinterpret_cast<uintptr_t>(cursor);
        collection.publicEntries.push_back(reinterpret_cast<uintptr_t>(entry));
    }
    return false;
}
struct ClassProof {
    ehr_class_preflight::Facts facts;
    ehr_class_preflight::Result checked;
    NSDictionary<NSString *, id> *report = nil;
};
struct OwnedToken {
    const API &api;
    uint32_t handle = 0;
    explicit OwnedToken(const API &value):api(value){}
    ~OwnedToken(){release();}
    void take(P object){if(object)handle=api.gchandle_new(object,true);}
    P get()const{return handle?api.gchandle_get_target(handle):nullptr;}
    bool release(){if(handle)api.gchandle_free(handle);handle=0;return true;}
};
ClassProof inspect(const API &api, P klass) {
    using namespace ehr_class_preflight;
    ClassProof proof;
    if(!klass){proof.report=@{@"success":@NO,@"status":@"class_not_found"};return proof;}
    auto &facts=proof.facts;
    facts.klass=reinterpret_cast<uintptr_t>(klass);
    facts.image=reinterpret_cast<uintptr_t>(api.class_get_image(klass));
    facts.name=reinterpret_cast<uintptr_t>(api.class_get_name(klass)); facts.nameSpace=reinterpret_cast<uintptr_t>(api.class_get_namespace(klass));
    facts.type=reinterpret_cast<uintptr_t>(api.class_get_type(klass)); facts.parent=reinterpret_cast<uintptr_t>(api.class_get_parent(klass));
    facts.declaring=reinterpret_cast<uintptr_t>(api.class_get_declaring_type(klass)); facts.element=reinterpret_cast<uintptr_t>(api.class_get_element_class(klass));
    facts.instanceSize=api.class_instance_size(klass); facts.flags=api.class_get_flags(klass); facts.token=api.class_get_type_token(klass);
    facts.fieldCount=api.class_num_fields(klass); facts.rank=static_cast<uint8_t>(api.class_get_rank(klass));
    facts.typeKind=static_cast<uint8_t>(api.type_get_type(reinterpret_cast<P>(facts.type)));
    facts.typeAttributes=api.type_get_attrs(reinterpret_cast<P>(facts.type)); facts.typeByRef=api.type_is_byref(reinterpret_cast<P>(facts.type));
    facts.valueType=api.class_is_valuetype(klass); facts.hasReferences=api.class_has_references(klass);
    facts.collections={
        {"methods",152,288,8,true,0,{}}, {"fields",128,292,32,false,0,{}},
        {"properties",144,290,40,false,0,{}}, {"events",136,294,56,false,0,{}},
        {"nested",160,296,8,true,0,{}}, {"interfaces",168,300,8,true,0,{}}};
    const Iterator iterators[]={api.class_get_methods,api.class_get_fields,api.class_get_properties,api.class_get_events,api.class_get_nested_types,api.class_get_interfaces};
    bool publicCollections=true;
    for(size_t i=0;i<facts.collections.size();++i)publicCollections=collect(klass,iterators[i],facts.collections[i])&&publicCollections;
    std::set<P> seen;
    for(P parent=klass;parent;parent=api.class_get_parent(parent)) {
        if(facts.publicHierarchy.size()==32||!seen.insert(parent).second){publicCollections=false;break;}
        facts.publicHierarchy.push_back(reinterpret_cast<uintptr_t>(parent));
    }
    std::reverse(facts.publicHierarchy.begin(),facts.publicHierarchy.end());
    const bool roundtrip=api.class_from_type(reinterpret_cast<P>(facts.type))==klass;
    bool hierarchyRelations=true;
    // Normal public relation queries may populate runtime-owned metadata
    // caches. No guessed class field is written or private initializer called.
    for(const auto parent:facts.publicHierarchy)hierarchyRelations=api.class_is_assignable_from(reinterpret_cast<P>(parent),klass)&&hierarchyRelations;
    // Relation queries may finish lazy metadata setup and replace a collection
    // cache. Sample its public cursors again before comparing the private header.
    // All existing bounds, count, pointer and endpoint checks still apply.
    for(size_t i=0;i<facts.collections.size();++i)publicCollections=collect(klass,iterators[i],facts.collections[i])&&publicCollections;
    facts.initialized=api.class_is_inited(klass); // After all public metadata queries.
    proof.checked=verify(publicCollections&&roundtrip&&hierarchyRelations,facts,copy);
    NSMutableDictionary *checks=[NSMutableDictionary dictionary];
    for(const auto &check:proof.checked.checks)checks[@(check.name.c_str())]=@(check.pass);
    NSMutableDictionary *collections=[NSMutableDictionary dictionary];
    for(const auto &collection:facts.collections)collections[@(collection.name.c_str())]=@{
        @"publicCount":@(collection.publicEntries.size()),@"emptyPointerUnverified":@(collection.publicEntries.empty()),
        @"strideCandidate":@(collection.stride),@"multiplePublicEntriesForStrideCheck":@(!collection.pointerArray&&collection.publicEntries.size()>1)};
    proof.report=@{@"success":@(proof.checked.all()),@"publicEnumerationsBounded":@(publicCollections),@"publicTypeRoundtrip":@(roundtrip),@"publicHierarchyRelations":@(hierarchyRelations),
        @"name":string(reinterpret_cast<P>(facts.name)),@"namespace":string(reinterpret_cast<P>(facts.nameSpace)),
        @"image":string(api.image_get_name(reinterpret_cast<P>(facts.image))),@"checks":checks,@"collections":collections,
        @"publicInstanceSize":@(facts.instanceSize),@"publicInitialized":@(facts.initialized),@"privateReadCount":@(proof.checked.privateReads),
        @"headerFactsVerified":@(proof.checked.header),@"collectionEndpointsVerified":@(proof.checked.collections),@"hierarchyVerified":@(proof.checked.hierarchy),
        @"vtableCountCandidate":@(proof.checked.vtableCount),@"vtableCountFullyVerified":@NO,
        @"classAllocationSize312ProvenByThisCheck":@NO,@"methodAllocationSize88ProvenByThisCheck":@NO,@"typeAllocationSize16ProvenByThisCheck":@NO};
    return proof;
}
P findMethod(const API &api, const ClassProof &proof, const char *name) {
    if(!proof.checked.all()||proof.facts.collections.empty())return nullptr;
    P found=nullptr;
    for(const uintptr_t pointer:proof.facts.collections[0].publicEntries) {
        P method=reinterpret_cast<P>(pointer);
        uint32_t impl=0;
        if([string(api.method_get_name(method)) isEqualToString:@(name)] && api.method_get_param_count(method)==0 && !(api.method_get_flags(method,&impl)&16)) {
            if(found)return nullptr;found=method;
        }
    }
    return found;
}
NSDictionary *vtableWitness(const API &api, const ClassProof &base, const ClassProof &target, P object) {
    if(!base.checked.all()||!target.checked.all())return @{@"verified":@NO,@"state":@"class_prerequisites_failed"};
    if(!object)return @{@"verified":@NO,@"state":@"probe_object_unavailable"};
    P original=findMethod(api,base,"ToString");
    if(!original)return @{@"verified":@NO,@"state":@"unique_public_virtual_method_missing"};
    P resolved=api.object_get_virtual_method(object,original);
    const auto &methods=target.facts.collections[0].publicEntries;
    if(!resolved||std::find(methods.begin(),methods.end(),reinterpret_cast<uintptr_t>(resolved))==methods.end())
        return @{@"verified":@NO,@"state":@"virtual_result_not_in_exact_public_target_methods"};
    std::array<uint8_t,88> originalBytes{},resolvedBytes{};
    if(!copy(reinterpret_cast<uintptr_t>(original),originalBytes.data(),originalBytes.size())||!copy(reinterpret_cast<uintptr_t>(resolved),resolvedBytes.data(),resolvedBytes.size()))
        return @{@"verified":@NO,@"state":@"method_bytes_unreadable"};
    auto get=[&](const auto &bytes,size_t offset,auto *value){memcpy(value,bytes.data()+offset,sizeof(*value));};
    uintptr_t name=0,owner=0,virtualPointer=0;uint32_t token=0;uint16_t slot=0,flags=0;uint8_t count=255;
    get(resolvedBytes,24,&name);get(resolvedBytes,32,&owner);get(resolvedBytes,72,&token);get(resolvedBytes,8,&virtualPointer);get(resolvedBytes,76,&flags);get(resolvedBytes,82,&count);
    uint32_t impl=0;
    const bool methodFacts=name==reinterpret_cast<uintptr_t>(api.method_get_name(resolved)) && owner==reinterpret_cast<uintptr_t>(api.method_get_declaring_type(resolved)) &&
        token==api.method_get_token(resolved) && flags==api.method_get_flags(resolved,&impl) && count==api.method_get_param_count(resolved) && virtualPointer;
    uintptr_t baseName=0,baseOwner=0;uint32_t baseToken=0;uint16_t baseFlags=0;uint8_t baseCount=255;
    get(originalBytes,24,&baseName);get(originalBytes,32,&baseOwner);get(originalBytes,72,&baseToken);get(originalBytes,76,&baseFlags);get(originalBytes,82,&baseCount);
    const bool baseMethodFacts=baseName==reinterpret_cast<uintptr_t>(api.method_get_name(original)) && baseOwner==reinterpret_cast<uintptr_t>(api.method_get_declaring_type(original)) &&
        baseToken==api.method_get_token(original) && baseFlags==api.method_get_flags(original,&impl) && baseCount==api.method_get_param_count(original);
    get(originalBytes,80,&slot);
    // Refresh a second public-fact sample after virtual lookup. It must agree
    // before looking at any vtable slot, including initialized bits/counts.
    const ClassProof refreshed=inspect(api,reinterpret_cast<P>(target.facts.klass));
    if(!methodFacts||!baseMethodFacts||!refreshed.checked.all()||!refreshed.facts.initialized || !(refreshed.checked.initializedBits&2) ||
        !(refreshed.checked.extraBits&32) || !refreshed.checked.vtableCount || refreshed.checked.vtableCount>4096 || slot>=refreshed.checked.vtableCount)
        return @{@"verified":@NO,@"state":@"method_or_initialized_vtable_prerequisites_unverified",@"methodFacts":@(methodFacts),@"publicInitialized":@(refreshed.facts.initialized)};
    uintptr_t address=0; std::array<uintptr_t,2> entry{};
    const bool readable=ehr_class_preflight::add(target.facts.klass,312+size_t(slot)*16,address)&&copy(address,entry.data(),sizeof(entry));
    const bool verified=readable&&entry[0]==virtualPointer&&entry[1]==reinterpret_cast<uintptr_t>(resolved);
    return @{@"verified":@(verified),@"state":verified?@"known_virtual_slot_matches":@"slot_mismatch_or_unreadable",@"slot":@(slot),
        @"vtableOffsetCandidate":@312,@"entryStrideCandidate":@16,@"publicVirtualResultMatchesEntryMethod":@(readable&&entry[1]==reinterpret_cast<uintptr_t>(resolved)),
        @"entryCodeMatchesValidatedMethodVirtualPointer8":@(readable&&entry[0]==virtualPointer),@"wholeVtableVerified":@NO};
}
}

NSDictionary<NSString *, id> *EHRClassLayoutPreflightWithLookup(void *(*lookup)(const char *)) {
    using namespace ehr_class_layout_runtime;
    if(!NSThread.isMainThread)return @{@"success":@NO,@"status":@(EHR_RUNTIME_WRONG_THREAD),@"privateReadsPerformed":@NO};
    if(!lookup)return @{@"success":@NO,@"status":@"lookup_missing",@"privateReadsPerformed":@NO};
    auto findClass=reinterpret_cast<decltype(&ehr_runtime_find_class)>(lookup("ehr_runtime_find_class"));
    auto findMethodGate=reinterpret_cast<decltype(&ehr_runtime_find_method)>(lookup("ehr_runtime_find_method"));
    auto validateMethod=reinterpret_cast<decltype(&ehr_runtime_validate_native_method)>(lookup("ehr_runtime_validate_native_method"));
    if(!findClass||!findMethodGate||!validateMethod)return @{@"success":@NO,@"status":@"gate_export_missing",@"privateReadsPerformed":@NO};
    EHRRuntimeToken constants=0,method=0;uint64_t observed=0;
    auto status=findClass("Assembly-CSharp.dll","","Constants",&constants);
    if(status==EHR_RUNTIME_OK)status=findMethodGate(constants,"GetBroadcastVersion",nullptr,0,"System.Int32",1,&method);
    if(status==EHR_RUNTIME_OK)status=validateMethod(method,UINT64_C(30734292),&observed);
    if(status!=EHR_RUNTIME_OK)return @{@"success":@NO,@"status":@(status),@"fullCandidateHashUUIDGatePassed":@NO,@"privateReadsPerformed":@NO};
    API api{};if(!load(api,lookup))return @{@"success":@NO,@"status":@"required_public_export_missing",@"fullCandidateHashUUIDGatePassed":@YES,@"privateReadsPerformed":@NO};
    @try { try {
        const struct Spec{const char *image,*space,*name,*nested,*label;} specs[]={
            {"mscorlib.dll","System","Object",nullptr,"System.Object"},{"mscorlib.dll","System","String",nullptr,"System.String"},
            {"mscorlib.dll","System","Int32",nullptr,"System.Int32"},{"mscorlib.dll","System.Collections","ArrayList",nullptr,"System.Collections.ArrayList"},
            {"mscorlib.dll","System.Collections","ArrayList","ArrayListEnumeratorSimple","System.Collections.ArrayList+ArrayListEnumeratorSimple"},
            {"UnityEngine.CoreModule.dll","UnityEngine","Object",nullptr,"UnityEngine.Object"},{"UnityEngine.CoreModule.dll","UnityEngine","MonoBehaviour",nullptr,"UnityEngine.MonoBehaviour"}};
        std::vector<ClassProof> proofs;NSMutableDictionary *rows=[NSMutableDictionary dictionary];bool all=true;size_t reads=0;
        for(const auto &spec:specs) {
            auto proof=inspect(api,find(api,spec.image,spec.space,spec.name,spec.nested));
            rows[@(spec.label)]=proof.report;all=proof.checked.all()&&all;reads+=proof.checked.privateReads;proofs.push_back(std::move(proof));
        }
        OwnedToken stringObject(api),intObject(api);const uint16_t ownText[]={'e','h','r'};int32_t ownValue=7;
        stringObject.take(api.string_new_utf16(ownText,3));
        if(proofs[2].checked.all())intObject.take(api.value_box(reinterpret_cast<P>(proofs[2].facts.klass),&ownValue));
        NSDictionary *stringWitness=vtableWitness(api,proofs[0],proofs[1],stringObject.get());
        NSDictionary *intWitness=vtableWitness(api,proofs[0],proofs[2],intObject.get());
        const bool stringReleased=stringObject.release(),intReleased=intObject.release();
        const bool rootsReleased=stringReleased&&intReleased;
        const bool witnesses=[stringWitness[@"verified"] boolValue]&&[intWitness[@"verified"] boolValue];
        return @{@"success":@(all&&witnesses&&rootsReleased),@"status":@0,@"fullCandidateHashUUIDGatePassed":@YES,@"versionObservedRVA":@(observed),
            @"privateReadsPerformed":@(reads!=0),@"initialClassPrivateReadCount":@(reads),@"classCount":@7,@"classes":rows,
            @"vtableStringWitness":stringWitness,@"vtableInt32Witness":intWitness,@"probeValueRootsReleased":@(rootsReleased),
            @"privateClassWritesPerformed":@NO,@"typeMetadataAllocationRequested":@NO,@"classRegistrationPerformed":@NO,
            @"methodInfo88AllocationSizeVerified":@NO,@"type16AllocationSizeVerified":@NO,@"allClassFieldsVerified":@NO,@"fullEHRAvailable":@NO};
    } catch(...) { return @{@"success":@NO,@"status":@"contained_native_error",@"fullCandidateHashUUIDGatePassed":@YES}; }
    } @catch(__unused NSException *exception) { return @{@"success":@NO,@"status":@"contained_objc_error",@"fullCandidateHashUUIDGatePassed":@YES}; }
}
