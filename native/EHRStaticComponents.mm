#import "EHRStaticComponents.h"
#include "EHRSourceComponents.h"
#include "EHRStaticTypeRegistry.hpp"
#include "EHRReferenceLayoutCore.hpp"
#include "EHRClassLayoutPreflight.mm"
#include "EHRRuntimeCollections.h"
#include "EHRRuntimeReflection.h"
#include "EHRRuntimeIteratorPrivate.h"
#include "EHRRuntimePinnedAssociation.h"
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <vector>

// Original narrow static registration experiment. Class/header facts and the
// ordinary private call ABIs were proved against this exact source build before
// this code was prepared. This does not allocate an Il2CppImage/Assembly, run a
// JIT, modify existing metadata, or write executable memory. The new classes
// deliberately borrow the real CoreModule image. They are native-only shells;
// no claim of CLR EHR object construction or source assembly identity is made.
namespace ehr_static_components {
using namespace ehr_class_layout_runtime;
using Callback = void (*)(void *, P);
static_assert(sizeof(P)==8&&sizeof(uintptr_t)==8);
static_assert(sizeof(std::array<P,2>)==16);
struct Counters {
    std::atomic<uint64_t> ctor{0}, awake{0}, update{0}, destroy{0}, ping{0}, wrongThread{0}, wrongSelf{0}, badInvoker{0};
    std::atomic<uintptr_t> firstSelf{0};
};
struct Storage {
    void *klass = nullptr;
    size_t bytes = 0;
    alignas(8) std::array<std::array<uint8_t,128>,9> methods{};
    std::array<P,9> methodPointers{};
    std::vector<P> hierarchy;
    uint16_t methodCount = 0;
};
struct State {
    API api{};
    P (*method_get_return_type)(P) = nullptr;
    P (*object_get_class)(P) = nullptr;
    uint32_t (*class_get_bitmap_size)(P) = nullptr;
    void (*class_get_bitmap)(P,uint64_t *) = nullptr;
    const char *(*field_get_name)(P) = nullptr;
    P (*field_get_type)(P) = nullptr;
    uint32_t (*field_get_flags)(P) = nullptr;
    size_t (*field_get_offset)(P) = nullptr;
    P image = nullptr, mono = nullptr, voidType = nullptr;
    uintptr_t imageBase = 0;
    uintptr_t inheritedDescriptor = 0;
    uint64_t inheritedBitmap = 0;
    ehr_static_types::RegistryOf<8> registry;
    std::array<Storage,8> storage{};
    std::array<Counters,8> counters{};
    std::array<std::atomic<uint64_t>,3> hookCalls{};
    NSDictionary *registration = nil;
    NSMutableDictionary *probe = nil;
    std::vector<EHRRuntimeToken> roots;
    EHRRuntimeToken gameObject = 0, destroyMethod = 0;
    std::array<EHRRuntimeToken,2> components{};
    NSTimer *timer = nil;
    CFAbsoluteTime deadline = 0;
    bool ready = false, running = false, destroyRequested = false;
};
State &state() { static State *value = new State; return *value; }
template<class T> void put(void *storage, size_t offset, T value) {
    memcpy(static_cast<uint8_t *>(storage)+offset,&value,sizeof(value));
}
template<class T> T get(const void *storage,size_t offset) {
    T result{};memcpy(&result,static_cast<const uint8_t *>(storage)+offset,sizeof(result));return result;
}
bool observe(unsigned which,unsigned kind,void *self,P method) noexcept {
    auto &s=state();auto &c=s.counters[which];
    if(!NSThread.isMainThread){c.wrongThread.fetch_add(1);return false;}
    if(!self||!s.object_get_class||s.object_get_class(self)!=s.storage[which].klass){c.wrongSelf.fetch_add(1);return false;}
    const auto &storage=s.storage[which];
    const unsigned methodIndex=which==0&&kind==3?1:kind;
    if(method&&method!=storage.methodPointers[methodIndex]){c.badInvoker.fetch_add(1);return false;}
    uintptr_t zero=0;c.firstSelf.compare_exchange_strong(zero,reinterpret_cast<uintptr_t>(self));
    switch(kind){case 0:c.ctor.fetch_add(1);break;case 1:c.awake.fetch_add(1);break;case 2:c.update.fetch_add(1);break;case 3:c.destroy.fetch_add(1);break;case 4:c.ping.fetch_add(1);break;default:break;}return true;
}
void coroutinesCtor(void *self,P method) noexcept {if(observe(0,0,self,method))EHRSourceComponentConstruct(1,self);}
void coroutinesDestroy(void *self,P method) noexcept {if(observe(0,3,self,method))EHRSourceComponentEvent(1,3,self);}
void lifecycleCtor(void *self,P method) noexcept {if(observe(1,0,self,method))EHRSourceComponentConstruct(8,self);}
void lifecycleAwake(void *self,P method) noexcept {if(observe(1,1,self,method))EHRSourceComponentEvent(8,1,self);}
void lifecycleUpdate(void *self,P method) noexcept {if(observe(1,2,self,method))EHRSourceComponentEvent(8,2,self);}
void lifecycleDestroy(void *self,P method) noexcept {if(observe(1,3,self,method))EHRSourceComponentEvent(8,3,self);}
void lifecyclePing(void *self,P method) noexcept {if(observe(1,4,self,method))EHRSourceComponentEvent(8,4,self);}
const std::array<Callback,5> lifecycleCallbacks={lifecycleCtor,lifecycleAwake,lifecycleUpdate,lifecycleDestroy,lifecyclePing};

// Metadata-v29+ invoker ABI: a void-return method leaves return storage alone.
// Only our exact records and precompiled callbacks can be dispatched here.
void invokeStatic(void *entry,P method,void *self,void **args,void *result) noexcept {
    (void)args;(void)result;auto &s=state();
    for(unsigned which=0;which<2;++which)for(unsigned i=0;i<s.storage[which].methodCount;++i)
        if(s.storage[which].methodPointers[i]==method){
            Callback callback=which==0?(i?coroutinesDestroy:coroutinesCtor):lifecycleCallbacks[i];
            if(reinterpret_cast<uintptr_t>(entry)!=reinterpret_cast<uintptr_t>(callback)){s.counters[which].badInvoker.fetch_add(1);return;}
            callback(self,method);return;
        }
    s.counters[0].badInvoker.fetch_add(1);
}

bool gate(void *(*lookup)(const char *),NSMutableDictionary *report) {
    EHRRuntimeToken klass=0,method=0;uint64_t observed=0;
    auto status=ehr_runtime_find_class("Assembly-CSharp.dll","","Constants",&klass);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(klass,"GetBroadcastVersion",nullptr,0,"System.Int32",1,&method);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_validate_native_method(method,30734292,&observed);
    report[@"candidateAssociationStatus"]=@(status);
    if(status!=EHR_RUNTIME_OK||!lookup)return false;
    // The index-only private API has no image argument: require the exact
    // official metadata in the launcher's actual default Data bundle first.
    if([NSBundle.mainBundle objectForInfoDictionaryKey:@"EHRUnityDataBundleIdentifier"])return false;
    NSString *metadataPath=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Data/Managed/Metadata/global-metadata.dat"];
    NSData *metadata=[NSData dataWithContentsOfFile:metadataPath options:NSDataReadingMappedIfSafe error:nil];
    if(metadata.length!=15888204)return false;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]{};CC_SHA256(metadata.bytes,static_cast<CC_LONG>(metadata.length),digest);
    const uint8_t expected[]={0x22,0xdd,0x82,0x4b,0x10,0x84,0x90,0xc4,0x99,0x62,0xb7,0xe3,0x1c,0x30,0xea,0xe0,0x05,0x5c,0xe0,0xb7,0x2e,0x39,0xaa,0xc3,0xfa,0x15,0x93,0x24,0xd6,0xdd,0x52,0x9c};
    if(memcmp(digest,expected,sizeof(expected)))return false;
    report[@"exactMainBundleMetadataHashVerified"]=@YES;
    NSDictionary *layout=EHRClassLayoutPreflightWithLookup(lookup);
    report[@"freshReadOnlyClassLayout"]=layout;
    if(![layout[@"success"] boolValue]||![layout[@"fullCandidateHashUUIDGatePassed"] boolValue])return false;
    auto &s=state();if(!load(s.api,lookup))return false;
    s.object_get_class=reinterpret_cast<decltype(s.object_get_class)>(lookup("il2cpp_object_get_class"));
    s.method_get_return_type=reinterpret_cast<decltype(s.method_get_return_type)>(lookup("il2cpp_method_get_return_type"));
    s.class_get_bitmap_size=reinterpret_cast<decltype(s.class_get_bitmap_size)>(lookup("il2cpp_class_get_bitmap_size"));
    s.class_get_bitmap=reinterpret_cast<decltype(s.class_get_bitmap)>(lookup("il2cpp_class_get_bitmap"));
    s.field_get_name=reinterpret_cast<decltype(s.field_get_name)>(lookup("il2cpp_field_get_name"));
    s.field_get_type=reinterpret_cast<decltype(s.field_get_type)>(lookup("il2cpp_field_get_type"));
    s.field_get_flags=reinterpret_cast<decltype(s.field_get_flags)>(lookup("il2cpp_field_get_flags"));
    s.field_get_offset=reinterpret_cast<decltype(s.field_get_offset)>(lookup("il2cpp_field_get_offset"));
    Dl_info info{};void *anchor=lookup("il2cpp_class_from_type");
    if(!s.object_get_class||!s.method_get_return_type||!s.class_get_bitmap_size||!s.class_get_bitmap||!s.field_get_name||
        !s.field_get_type||!s.field_get_flags||!s.field_get_offset||!anchor||!dladdr(anchor,&info)||!info.dli_fbase||
        !info.dli_fname||!strstr(info.dli_fname,"/UnityFramework.framework/UnityFramework"))return false;
    s.imageBase=reinterpret_cast<uintptr_t>(info.dli_fbase);
    if(reinterpret_cast<uintptr_t>(anchor)!=s.imageBase+0x195e8a4)return false;
    s.mono=find(s.api,"UnityEngine.CoreModule.dll","UnityEngine","MonoBehaviour");
    const P voidClass=find(s.api,"mscorlib.dll","System","Void");
    if(!s.mono||!voidClass)return false;
    s.image=s.api.class_get_image(s.mono);s.voidType=s.api.class_get_type(voidClass);
    if(!s.image||!s.voidType)return false;
    // The same positive class/index inputs as actual proof21. This time entry
    // counters also prove the new signed candidate really routes all wrappers.
    using FromType=P(*)(P,bool);using FromName=P(*)(P,const char*,const char*);using Index=P(*)(int32_t);
    const std::array<uintptr_t,3> rvas={0x19c1970,0x19b7bf0,0x19ad6a0};
    for(auto rva:rvas)if(ehr_pinned::validate_engine_entry(reinterpret_cast<P>(s.imageBase+rva))!=EHR_RUNTIME_OK)return false;
    const uint64_t before[]={s.hookCalls[0].load(),s.hookCalls[1].load(),s.hookCalls[2].load()};
    const P byType=reinterpret_cast<FromType>(s.imageBase+rvas[0])(s.api.class_get_type(s.mono),true);
    const P byName=reinterpret_cast<FromName>(s.imageBase+rvas[1])(s.image,"UnityEngine","MonoBehaviour");
    const P byIndex=reinterpret_cast<Index>(s.imageBase+rvas[2])(13847);
    bool routed=byType==s.mono&&byName==s.mono&&byIndex==s.mono;
    for(size_t i=0;i<3;++i)routed=s.hookCalls[i].load()>before[i]&&routed;
    report[@"ordinaryPrivateCallsAndAllThreeEntryWrappersVerified"]=@(routed);
    return routed;
}

struct Root {
    EHRRuntimeToken token=0;
    ~Root(){if(token)ehr_runtime_object_release(token);}
};
EHRRuntimeStatus invoke(EHRRuntimeToken method,EHRRuntimeToken receiver,const EHRRuntimeArgument *args,size_t count,Root &result) {
    Root exception;return ehr_runtime_invoke(method,receiver,args,count,&result.token,&exception.token);
}
bool methodFacts(P method,uint16_t slot) {
    auto &s=state();std::array<uint8_t,88> raw{};
    if(!copy(reinterpret_cast<uintptr_t>(method),raw.data(),raw.size()))return false;
    uint32_t impl=0;const uint32_t flags=s.api.method_get_flags(method,&impl);
    if(get<P>(raw.data(),24)!=s.api.method_get_name(method)||get<P>(raw.data(),32)!=s.api.method_get_declaring_type(method)||
        get<P>(raw.data(),40)!=s.method_get_return_type(method)||get<uint32_t>(raw.data(),72)!=s.api.method_get_token(method)||
        get<uint16_t>(raw.data(),76)!=flags||get<uint16_t>(raw.data(),78)!=impl||get<uint8_t>(raw.data(),82)!=s.api.method_get_param_count(method)||
        get<uint16_t>(raw.data(),80)!=slot||(flags&0x410))return false;
    return get<P>(raw.data(),8)&&ehr_pinned::validate_engine_entry(get<P>(raw.data(),8))==EHR_RUNTIME_OK;
}
bool bitmap(P klass,uint64_t &value) {
    auto &s=state();if(s.class_get_bitmap_size(klass)!=8)return false;
    struct Bounded {uint64_t before=0xbef0bef0bef0bef0;std::array<uint64_t,8> words{};uint64_t after=0xafe0afe0afe0afe0;} bounded;
    s.class_get_bitmap(klass,bounded.words.data());
    if(bounded.before!=0xbef0bef0bef0bef0||bounded.after!=0xafe0afe0afe0afe0)return false;
    for(size_t i=1;i<bounded.words.size();++i)if(bounded.words[i])return false;
    value=bounded.words[0];return true;
}
bool gcCodePins(NSMutableDictionary *report) {
    // Reviewed exact source paths: common bitmap walk -> descriptor creation
    // -> class+8; GCJ allocation stores class pointer in object word0. These
    // functions are not among this candidate's three private entry hooks.
    const struct Pin{uintptr_t rva;size_t count;const char *sha,*name;} pins[]={
        {0x19c41ac,224,"adb813538ad17482e0af336f289b0fc17e6bda56fe7344ecccaf8a0b736c23d1","descriptor_construction"},
        {0x19c4b04,32,"3d7c93956aaa92ca26d93fdcd92fe12dca16b241fd5f63621e7b1150f249c9b0","public_bitmap_size"},
        {0x1997d10,160,"bf57b1332e4b3e24bd3bf99c3a8f28923c550c4d81a0848fd94a216bec37d28c","object_allocator_gcj_selection"},
        {0x123e098,148,"02744c80d71906f4e71eb02687b2a97a4020b4c347812f6d359001194851fcea","gcj_class_pointer_storage"},
        {0x196213c,40,"941d2b4d80856655ba1207698c765a2cefcd4be728713fed349a33f120f01933","descriptor_wrapper_small_bitmap_bound"},
        {0x124ba74,300,"98f50afc3cd2bf8f6d8003a76ad9807bf9f8c4af4a3619b1aeb3dc01c851d454","descriptor_inline_bit_reversal"}};
    NSMutableDictionary *checks=[NSMutableDictionary dictionary];
    for(const auto &pin:pins){std::array<uint8_t,384> bytes{};unsigned char hash[CC_SHA256_DIGEST_LENGTH]{};char text[65]{};const char *digits="0123456789abcdef";
        bool match=copy(state().imageBase+pin.rva,bytes.data(),pin.count);
        if(match){CC_SHA256(bytes.data(),static_cast<CC_LONG>(pin.count),hash);for(unsigned i=0;i<32;++i){text[i*2]=digits[hash[i]>>4];text[i*2+1]=digits[hash[i]&15];}match=!strcmp(text,pin.sha);}
        checks[@(pin.name)]=@(match);if(!match){report[@"inheritedGCCodePins"]=checks;return false;}}
    report[@"inheritedGCCodePins"]=checks;return true;
}
bool references(const ClassProof &base,const std::array<uint8_t,312> &raw,NSMutableDictionary *report){
    auto &s=state();report[@"basePublicHasReferences"]=@(base.facts.hasReferences);
    if(!base.facts.hasReferences||base.facts.instanceSize!=32||!gcCodePins(report))return false;
    unsigned referenceCount=0,nativePointerCount=0;bool fields=true;NSMutableArray *facts=[NSMutableArray array];
    for(auto address:base.facts.publicHierarchy){void *cursor=nullptr;
        for(unsigned i=0;i<128;++i){P value=s.api.class_get_fields(reinterpret_cast<P>(address),&cursor);if(!value)break;if(i==127){fields=false;break;}
            const auto flags=s.field_get_flags(value);if(flags&0x110)continue;
            P type=s.field_get_type(value);const auto offset=s.field_get_offset(value);const int kind=type?s.api.type_get_type(type):0;
            NSString *name=string(s.field_get_name(value));
            if(offset==16&&kind==24&&[name isEqualToString:@"m_CachedPtr"]){++nativePointerCount;}
            else if(offset==24&&kind==18&&[name isEqualToString:@"m_CancellationTokenSource"]){
                P klass=s.api.class_from_type(type);fields=klass&&[string(s.api.class_get_name(klass)) isEqualToString:@"CancellationTokenSource"]&&
                    [string(s.api.class_get_namespace(klass)) isEqualToString:@"System.Threading"]&&fields;++referenceCount;
            }else fields=false;
            [facts addObject:@{@"name":name,@"offset":@(offset),@"runtimeTypeKind":@(kind)}];}}
    uint64_t value=0;const uintptr_t descriptor=get<uintptr_t>(raw.data(),8);uintptr_t after=0;
    const bool verified=fields&&referenceCount==1&&nativePointerCount==1&&bitmap(s.mono,value)&&value==8&&
        copy(reinterpret_cast<uintptr_t>(s.mono)+8,&after,sizeof(after))&&after==descriptor&&
        ehr_reference_layout::simpleDescriptor(base.facts.instanceSize,value,descriptor);
    report[@"inheritedPublicInstanceFields"]=facts;report[@"inheritedPublicReferenceBitmap"]=@(value);report[@"inheritedGCDescriptorInlineBitmapVerified"]=@(verified);
    report[@"descriptorHeapOwnershipOrProcedureAssumed"]=@NO;
    if(verified){s.inheritedDescriptor=descriptor;s.inheritedBitmap=value;}return verified;
}
bool verifiedBase(std::vector<std::array<P,2>> &entries,ClassProof &base,NSMutableDictionary *report) {
    auto &s=state();base=inspect(s.api,s.mono);report[@"baseMonoBehaviourPublicClassProof"]=base.report;
    if(!base.checked.all()||!base.facts.initialized||base.facts.valueType||
        base.facts.publicHierarchy.size()>=32||base.facts.instanceSize<16||base.facts.instanceSize>4096||
        base.facts.instanceSize%8||(base.facts.flags&0x120))return false;
    std::array<uint8_t,312> raw{};
    if(!copy(reinterpret_cast<uintptr_t>(s.mono),raw.data(),raw.size()))return false;
    if(!references(base,raw,report))return false;
    const auto vcount=get<uint16_t>(raw.data(),298);
    report[@"baseNativeVtableCountCandidate"]=@(vcount);report[@"baseNativeInterfaceOffsetsCountCandidate"]=@(get<uint16_t>(raw.data(),302));
    report[@"baseNativeFinalizeBitCandidate"]=@((get<uint8_t>(raw.data(),310)&2)!=0);
    if(!vcount||vcount>128||get<uint16_t>(raw.data(),300)||get<uint16_t>(raw.data(),302)||
        (get<uint8_t>(raw.data(),310)&2)||!(get<uint8_t>(raw.data(),310)&32))return false;
    // This first subset refuses interfaces or an inherited finalizer. Its
    // inherited reference map is independently verified above and kept intact.
    std::set<P> publicMethods;
    for(auto address:base.facts.publicHierarchy){ehr_class_preflight::Collection c;
        if(!collect(reinterpret_cast<P>(address),s.api.class_get_methods,c))return false;
        for(auto entry:c.publicEntries)publicMethods.insert(reinterpret_cast<P>(entry));}
    entries.resize(vcount);
    if(!copy(reinterpret_cast<uintptr_t>(s.mono)+312,entries.data(),entries.size()*16))return false;
    for(uint16_t i=0;i<vcount;++i){
        const auto &entry=entries[i];
        if(!entry[0]||!entry[1]||!publicMethods.count(entry[1])||!methodFacts(entry[1],i)){
            report[@"failedBaseVtableSlot"]=@(i);report[@"failedBaseVtableMethodIsPublicEntry"]=@(publicMethods.count(entry[1])!=0);
            if(entry[1]&&publicMethods.count(entry[1]))report[@"failedBaseVtableMethodName"]=string(s.api.method_get_name(entry[1]));return false;}
        std::array<uint8_t,16> method{};
        if(!copy(reinterpret_cast<uintptr_t>(entry[1]),method.data(),method.size())||get<P>(method.data(),8)!=entry[0])return false;
    }
    // Independent public virtual resolution on a real existing MonoBehaviour.
    // Nothing is created while validating the base table.
    EHRRuntimeToken monoClass=0,objectClass=0,findAll=0;Root type,objects;
    auto status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","MonoBehaviour",&monoClass);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_class_type_object(monoClass,&type.token);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","Object",&objectClass);
    const char *types[]={"System.Type"};
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(objectClass,"FindObjectsOfType",types,1,"UnityEngine.Object[]",1,&findAll);
    const EHRRuntimeArgument argument{EHR_RUNTIME_REFERENCE,0,type.token,nullptr,0};
    if(status==EHR_RUNTIME_OK)status=invoke(findAll,0,&argument,1,objects);
    int32_t count=0;Root exception;
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_array_length(objects.token,&count,&exception.token);
    if(status!=EHR_RUNTIME_OK||count<0||count>4096)return false;
    bool witnessed=false;NSString *ownerName=@"";
    for(int32_t i=0;i<count&&i<256&&!witnessed;++i){Root candidate,raised;void *native=nullptr;
        status=ehr_runtime_array_get(objects.token,i,&candidate.token,&raised.token);
        if(status!=EHR_RUNTIME_OK||!candidate.token||EHRRuntimeIteratorBorrow(candidate.token,&native)!=EHR_RUNTIME_OK||!native)continue;
        bool match=true;for(const auto &entry:entries)match=s.api.object_get_virtual_method(native,entry[1])==entry[1]&&match;
        if(match){witnessed=true;ownerName=string(s.api.class_get_name(s.object_get_class(native)));}}
    report[@"baseMonoBehaviourVtableEntryCount"]=@(entries.size());report[@"baseVtableAllEntriesMatchPublicMethodFacts"]=@YES;
    report[@"baseVtableAllSlotsMatchActualObjectVirtualResolution"]=@(witnessed);report[@"baseVtableWitnessOwnerType"]=ownerName;
    report[@"baseVtableWitnessObjectsFound"]=@(count);report[@"baseNoInterfacesOrFinalizer"]=@YES;
    return witnessed;
}

constexpr std::array<const char *,8> sourceSpaces={"EHR","EHR.NativeProbes","EHR","EHR.Patches","EHR.Patches","EHR.Patches","EHR.Patches","EHR"};
constexpr std::array<const char *,8> sourceNames={"Coroutines","StaticLifecycleProbe","ErrorText","AbstractPagingBehaviour","MeetingHudPagingBehaviour","ShapeShifterPagingBehaviour","VitalsPagingBehaviour","ClientControlGUI"};
constexpr std::array<uint32_t,8> sourceIds={1,8,2,3,4,5,6,7};
constexpr std::array<const char *,9> messageNames={".ctor","Awake","Update","OnDestroy","Ping","Start","LateUpdate","FixedUpdate","OnGUI"};
struct ExtraPlan{uint16_t count;std::array<unsigned,6> messages;unsigned parent;};
constexpr std::array<ExtraPlan,8> extraPlans={ExtraPlan{},ExtraPlan{},ExtraPlan{6,{0,1,2,3,6,7},0},ExtraPlan{4,{0,2,3,5,0,0},0},ExtraPlan{4,{0,2,3,5,0,0},3},ExtraPlan{4,{0,2,3,5,0,0},3},ExtraPlan{4,{0,2,3,5,0,0},3},ExtraPlan{4,{0,1,3,8,0,0},0}};
template<unsigned Which,unsigned Message> void extraCallback(void *self,P method) noexcept{
 auto&s=state();auto&c=s.counters[Which];if(!NSThread.isMainThread){c.wrongThread.fetch_add(1);return;}
 if(!self||!s.object_get_class||s.object_get_class(self)!=s.storage[Which].klass){c.wrongSelf.fetch_add(1);return;}
 unsigned index=0;while(index<extraPlans[Which].count&&extraPlans[Which].messages[index]!=Message)++index;
 if(index==extraPlans[Which].count||(method&&method!=s.storage[Which].methodPointers[index])){c.badInvoker.fetch_add(1);return;}
 if constexpr(Message==0){c.ctor.fetch_add(1);EHRSourceComponentConstruct(sourceIds[Which],self);}
 else {if constexpr(Message==1)c.awake.fetch_add(1);if constexpr(Message==2)c.update.fetch_add(1);if constexpr(Message==3)c.destroy.fetch_add(1);EHRSourceComponentEvent(sourceIds[Which],Message,self);}
}
template<unsigned Which,size_t... Messages> constexpr std::array<Callback,9> extraCallbacks(std::index_sequence<Messages...>){return {extraCallback<Which,Messages>...};}
const std::array<std::array<Callback,9>,6> allExtraCallbacks={extraCallbacks<2>(std::make_index_sequence<9>{}),extraCallbacks<3>(std::make_index_sequence<9>{}),extraCallbacks<4>(std::make_index_sequence<9>{}),extraCallbacks<5>(std::make_index_sequence<9>{}),extraCallbacks<6>(std::make_index_sequence<9>{}),extraCallbacks<7>(std::make_index_sequence<9>{})};
void invokeExtra(void *entry,P method,void *self,void **args,void *result) noexcept{
 (void)args;(void)result;auto&s=state();for(unsigned which=2;which<8;++which)for(unsigned i=0;i<s.storage[which].methodCount;++i){
  if(s.storage[which].methodPointers[i]!=method)continue;const auto callback=allExtraCallbacks[which-2][extraPlans[which].messages[i]];
  if(reinterpret_cast<uintptr_t>(entry)!=reinterpret_cast<uintptr_t>(callback)){s.counters[which].badInvoker.fetch_add(1);return;}callback(self,method);return;}
 s.counters[2].badInvoker.fetch_add(1);
}
bool buildExtra(unsigned which,const ClassProof &monoBase,const std::vector<std::array<P,2>> &vtable){
 auto&s=state();auto&storage=s.storage[which];const auto &plan=extraPlans[which];
 // Full inspect() resolves class_from_type. A newly built parent's negative
 // definition index is deliberately unknown until the immutable registry is
 // published, so resolving it here would enter the ordinary private resolver.
 const P parent=plan.parent?s.storage[plan.parent].klass:s.mono;const auto &base=monoBase;
 if(!parent||!base.checked.all()||base.facts.publicHierarchy.size()>=31)return false;
 std::vector<P> parentHierarchy;for(auto p:base.facts.publicHierarchy)parentHierarchy.push_back(reinterpret_cast<P>(p));
 if(plan.parent){
  const auto &ownedParent=s.storage[plan.parent];
  if(plan.parent!=3||parent!=ownedParent.klass||!ownedParent.klass||s.registry.published())return false;
  parentHierarchy.push_back(parent);
  if(ownedParent.hierarchy!=parentHierarchy||parentHierarchy.size()>=32||
     s.api.class_get_parent(parent)!=s.mono||s.api.class_get_image(parent)!=s.image||
     s.api.class_get_type(parent)!=static_cast<const uint8_t*>(parent)+32||
     s.api.class_get_element_class(parent)!=parent||s.api.class_instance_size(parent)!=base.facts.instanceSize||
     s.api.class_get_flags(parent)!=(base.facts.flags&~uint32_t(0x80))||s.api.class_num_fields(parent)!=0||
     strcmp(s.api.class_get_name(parent),sourceNames[plan.parent])||strcmp(s.api.class_get_namespace(parent),sourceSpaces[plan.parent])||
     !s.api.class_is_inited(parent)||s.api.class_is_valuetype(parent)||!s.api.class_has_references(parent))return false;
  // Corroborate the entire owned parent hierarchy through bounded public parent
  // reads; no copied Type/negative index is passed to a runtime type resolver.
  P current=parent;for(size_t n=parentHierarchy.size();n>0;--n){if(current!=parentHierarchy[n-1])return false;current=s.api.class_get_parent(current);}if(current)return false;
 }
 uint64_t baseBitmap=0;if(!bitmap(parent,baseBitmap)||baseBitmap!=s.inheritedBitmap||get<uintptr_t>(parent,8)!=s.inheritedDescriptor)return false;
 storage.methodCount=plan.count;storage.bytes=312+vtable.size()*16;storage.klass=calloc(1,storage.bytes);if(!storage.klass)return false;
 storage.hierarchy=parentHierarchy;storage.hierarchy.push_back(storage.klass);
 void*k=storage.klass;put(k,0,s.image);put(k,8,s.inheritedDescriptor);put(k,16,sourceNames[which]);put(k,24,sourceSpaces[which]);
 const intptr_t index=-3-static_cast<intptr_t>(which);put(k,32,index);put(k,40,uint32_t(0x00120000));put(k,48,index);put(k,56,uint32_t(0x20120000));
 put(k,64,static_cast<P>(k));put(k,72,static_cast<P>(k));put(k,88,parent);put(k,120,static_cast<P>(k));put(k,152,storage.methodPointers.data());put(k,200,storage.hierarchy.data());put(k,224,uint32_t(1));
 put(k,248,base.facts.instanceSize);put(k,256,base.facts.instanceSize);put(k,264,int32_t(-1));put(k,280,base.facts.flags&~uint32_t(0x80));put(k,288,storage.methodCount);put(k,298,static_cast<uint16_t>(vtable.size()));put(k,304,static_cast<uint8_t>(storage.hierarchy.size()));put(k,309,uint8_t(35));put(k,310,uint8_t(33));
 memcpy(static_cast<uint8_t*>(k)+312,vtable.data(),vtable.size()*16);
 for(unsigned i=0;i<plan.count;++i){void*m=storage.methods[i].data();storage.methodPointers[i]=m;const auto message=plan.messages[i];const auto callback=allExtraCallbacks[which-2][message];
  put(m,0,reinterpret_cast<uintptr_t>(callback));put(m,8,reinterpret_cast<uintptr_t>(callback));put(m,16,reinterpret_cast<uintptr_t>(invokeExtra));put(m,24,messageNames[message]);put(m,32,static_cast<P>(k));put(m,40,s.voidType);put(m,76,uint16_t(message?0x86:0x1886));put(m,80,uint16_t(0xffff));}
 if(s.api.class_get_image(k)!=s.image||s.api.class_get_parent(k)!=parent||s.api.class_get_element_class(k)!=k||s.api.class_instance_size(k)!=base.facts.instanceSize||s.api.class_get_type(k)!=static_cast<uint8_t*>(k)+32||strcmp(s.api.class_get_name(k),sourceNames[which])||strcmp(s.api.class_get_namespace(k),sourceSpaces[which])||s.api.class_num_fields(k)!=0||!s.api.class_is_inited(k)||s.api.class_is_valuetype(k)||!s.api.class_has_references(k))return false;
 uint64_t ownBitmap=0;if(!bitmap(k,ownBitmap)||ownBitmap!=s.inheritedBitmap||get<uintptr_t>(k,8)!=s.inheritedDescriptor)return false;
 ehr_class_preflight::Collection methods;if(!collect(k,s.api.class_get_methods,methods)||methods.publicEntries.size()!=plan.count)return false;
 for(unsigned i=0;i<plan.count;++i){P m=storage.methodPointers[i];uint32_t impl=0;if(methods.publicEntries[i]!=reinterpret_cast<uintptr_t>(m)||strcmp(s.api.method_get_name(m),messageNames[plan.messages[i]])||s.api.method_get_declaring_type(m)!=k||s.method_get_return_type(m)!=s.voidType||s.api.method_get_param_count(m)||s.api.method_get_flags(m,&impl)!=(plan.messages[i]?0x86u:0x1886u)||impl||s.api.method_get_token(m))return false;}
 return true;
}

bool build(unsigned which,const ClassProof &base,const std::vector<std::array<P,2>> &vtable) {
    auto &s=state();auto &storage=s.storage[which];
    storage.methodCount=which?5:2;storage.bytes=312+vtable.size()*16;storage.klass=calloc(1,storage.bytes);
    if(!storage.klass)return false;
    storage.hierarchy.reserve(base.facts.publicHierarchy.size()+1);
    for(auto p:base.facts.publicHierarchy)storage.hierarchy.push_back(reinterpret_cast<P>(p));
    storage.hierarchy.push_back(storage.klass);
    const char *space=which?"EHR.NativeProbes":"EHR",*name=which?"StaticLifecycleProbe":"Coroutines";
    void *k=storage.klass;
    put(k,0,s.image);put(k,8,s.inheritedDescriptor);put(k,16,name);put(k,24,space);
    const intptr_t index=-3-static_cast<intptr_t>(which);
    put(k,32,index);put(k,40,uint32_t(0x00120000));
    put(k,48,index);put(k,56,uint32_t(0x20120000));
    put(k,64,static_cast<P>(k));put(k,72,static_cast<P>(k));put(k,88,s.mono);put(k,120,static_cast<P>(k));
    put(k,152,storage.methodPointers.data());put(k,200,storage.hierarchy.data());
    put(k,224,uint32_t(1)); // No managed static constructor exists for either shell.
    put(k,248,base.facts.instanceSize);put(k,256,base.facts.instanceSize);put(k,264,int32_t(-1));
    put(k,280,base.facts.flags&~uint32_t(0x80));put(k,288,storage.methodCount);put(k,298,static_cast<uint16_t>(vtable.size()));
    put(k,304,static_cast<uint8_t>(storage.hierarchy.size()));put(k,309,uint8_t(35));put(k,310,uint8_t(33));
    memcpy(static_cast<uint8_t *>(k)+312,vtable.data(),vtable.size()*16);
    const char *lifecycleNames[]={".ctor","Awake","Update","OnDestroy","Ping"};
    const char *coroutinesNames[]={".ctor","OnDestroy"};const char *const *names=which?lifecycleNames:coroutinesNames;
    for(unsigned i=0;i<storage.methodCount;++i){void *method=storage.methods[i].data();storage.methodPointers[i]=method;
        const Callback callback=which?lifecycleCallbacks[i]:(i?coroutinesDestroy:coroutinesCtor);
        put(method,0,reinterpret_cast<uintptr_t>(callback));put(method,8,reinterpret_cast<uintptr_t>(callback));put(method,16,reinterpret_cast<uintptr_t>(invokeStatic));
        put(method,24,names[i]);put(method,32,static_cast<P>(k));put(method,40,s.voidType);put(method,76,uint16_t(i?0x86:0x1886));put(method,80,uint16_t(0xffff));}
    // Public accessors validate all populated method/header facts before the
    // records become reachable through any runtime lookup hook.
    if(s.api.class_get_image(k)!=s.image||s.api.class_get_parent(k)!=s.mono||s.api.class_get_element_class(k)!=k||
        s.api.class_instance_size(k)!=base.facts.instanceSize||s.api.class_get_type(k)!=static_cast<uint8_t *>(k)+32||
        strcmp(s.api.class_get_name(k),name)||strcmp(s.api.class_get_namespace(k),space)||s.api.class_num_fields(k)!=0||
        !s.api.class_is_inited(k)||s.api.class_is_valuetype(k)||!s.api.class_has_references(k))return false;
    uint64_t ownBitmap=0;
    if(!bitmap(k,ownBitmap)||ownBitmap!=s.inheritedBitmap||get<uintptr_t>(k,8)!=s.inheritedDescriptor||
        !ehr_reference_layout::simpleDescriptor(base.facts.instanceSize,ownBitmap,s.inheritedDescriptor))return false;
    ehr_class_preflight::Collection methods;if(!collect(k,s.api.class_get_methods,methods)||methods.publicEntries.size()!=storage.methodCount)return false;
    for(unsigned i=0;i<storage.methodCount;++i){P method=storage.methodPointers[i];uint32_t impl=0;
        if(methods.publicEntries[i]!=reinterpret_cast<uintptr_t>(method)||strcmp(s.api.method_get_name(method),names[i])||
            s.api.method_get_declaring_type(method)!=k||s.method_get_return_type(method)!=s.voidType||s.api.method_get_param_count(method)||
            s.api.method_get_flags(method,&impl)!=(i?0x86u:0x1886u)||impl||s.api.method_get_token(method))return false;}
    return true;
}
void discardUnpublished() noexcept {
    auto &s=state();if(s.registry.published())return;
    for(auto &storage:s.storage){free(storage.klass);storage.klass=nullptr;storage.bytes=0;storage.methodCount=0;}
}
NSDictionary *counters() {
    auto &s=state();NSMutableArray *values=[NSMutableArray array];
    for(const auto &c:s.counters)[values addObject:@{@"constructors":@(c.ctor.load()),@"awake":@(c.awake.load()),@"update":@(c.update.load()),
        @"destroy":@(c.destroy.load()),@"ping":@(c.ping.load()),@"wrongThread":@(c.wrongThread.load()),@"wrongSelf":@(c.wrongSelf.load()),@"badInvoker":@(c.badInvoker.load())}];
    return @{@"coroutines":values[0],@"lifecycle":values[1],@"allNativeTypes":values};
}
void keep(EHRRuntimeToken token){if(token)state().roots.push_back(token);}
EHRRuntimeStatus call(EHRRuntimeToken method,EHRRuntimeToken receiver,const EHRRuntimeArgument *arguments,size_t count,EHRRuntimeToken *result){
    EHRRuntimeToken exception=0;const auto status=ehr_runtime_invoke(method,receiver,arguments,count,result,&exception);keep(*result);keep(exception);return status;
}
EHRRuntimeStatus destroy(){auto &s=state();if(!s.gameObject||s.destroyRequested)return EHR_RUNTIME_OK;
    EHRRuntimeToken result=0;const EHRRuntimeArgument argument{EHR_RUNTIME_REFERENCE,0,s.gameObject,nullptr,0};
    const auto status=call(s.destroyMethod,0,&argument,1,&result);if(status==EHR_RUNTIME_OK)s.destroyRequested=true;return status;
}
void finish(NSString *message,bool success,int32_t status){auto &s=state();[s.timer invalidate];s.timer=nil;
    const auto cleanup=destroy();bool released=cleanup==EHR_RUNTIME_OK;
    if(released){for(auto token:s.roots)released=ehr_runtime_object_release(token)==EHR_RUNTIME_OK&&released;s.roots.clear();}
    s.probe[@"success"]=@(success&&released);s.probe[@"complete"]=@YES;s.probe[@"state"]=message;s.probe[@"status"]=@(status);
    s.probe[@"rootCleanupSucceeded"]=@(released);s.probe[@"remainingOwnedObjectRoots"]=@(s.roots.size());s.probe[@"counters"]=counters();s.running=false;
}
void tick(){auto &s=state();if(!s.running)return;auto &c=s.counters[1];
    if(c.wrongThread.load()||c.wrongSelf.load()||c.badInvoker.load()){finish(@"callback_contract_failed",false,EHR_RUNTIME_TYPE_MISMATCH);return;}
    if(!s.destroyRequested&&c.awake.load()==1&&c.update.load()>=2){
        const auto status=destroy();s.probe[@"actualDestroyRequested"]=@(status==EHR_RUNTIME_OK);
        if(status!=EHR_RUNTIME_OK){finish(@"destroy_failed",false,status);return;}}
    if(s.destroyRequested&&c.destroy.load()==1){
        const auto &empty=s.counters[0];const bool expected=c.ctor.load()==1&&c.awake.load()==1&&c.update.load()>=2&&c.ping.load()==1&&empty.ctor.load()==1&&
            !empty.wrongThread.load()&&!empty.wrongSelf.load()&&!empty.badInvoker.load();
        finish(@"unity_lifecycle_observed",expected,expected?EHR_RUNTIME_OK:EHR_RUNTIME_TYPE_MISMATCH);return;}
    if(CFAbsoluteTimeGetCurrent()>s.deadline)finish(@"lifecycle_timed_out",false,EHR_RUNTIME_LIMIT);
}
}

bool EHRStaticComponentsType(const void *type,const void **result) noexcept {
    auto &s=ehr_static_components::state();if(!result||!type||!s.registry.published())return false;
    if(const void *known=s.registry.exactType(type)){*result=known;return true;}
    // IL2CPP guarantees this argument is a readable runtime Type. Copies of
    // our type are accepted only for the two exact owned class-kind tokens.
    intptr_t data=0;uint8_t kind=0;memcpy(&data,type,sizeof(data));memcpy(&kind,static_cast<const uint8_t *>(type)+10,1);
    if(const void *known=s.registry.copiedType(kind,data)){*result=known;return true;}return false;
}
bool EHRStaticComponentsName(const void *image,const char *space,const char *name,const void **result) noexcept {
    if(!result)return false;if(const void *known=ehr_static_components::state().registry.name(image,space,name)){*result=known;return true;}return false;
}
bool EHRStaticComponentsIndex(int32_t index,const void **result) noexcept {
    if(!result)return false;if(const void *known=ehr_static_components::state().registry.index(index)){*result=known;return true;}return false;
}
void EHRStaticComponentsRecordHook(unsigned hook) noexcept {if(hook<3)ehr_static_components::state().hookCalls[hook].fetch_add(1);}

NSDictionary *EHRStaticComponentsRegister(void *(*lookup)(const char *)) {
    using namespace ehr_static_components;auto &s=state();
    if(!NSThread.isMainThread)return @{@"success":@NO,@"state":@"wrong_thread"};
    if(s.registration)return s.registration;
    NSMutableDictionary *report=[@{@"success":@NO,@"state":@"starting",@"fullEHRAvailable":@NO,@"runtimeExecutableWrites":@NO,
        @"sourceManagedAssemblyIdentityImplemented":@NO,@"clrSourceObjectConstructionImplemented":@NO,@"nativeOnlyComponentShells":@YES,
        @"fakeImageOrAssemblyAllocated":@NO,@"registrationPerformed":@NO,@"type16OrMethod88ExactAllocationSizeClaimed":@NO,
        @"allClassFieldsVerified":@NO,@"allRuntimeVtablesVerified":@NO} mutableCopy];
    s.registration=report;
    @try {try {
        if(!gate(lookup,report)){report[@"state"]=@"pinned_layout_and_live_entry_gate_failed";return report;}
        ClassProof base;std::vector<std::array<P,2>> vtable;
        if(!verifiedBase(vtable,base,report)){report[@"state"]=@"complete_base_vtable_or_minimal_inheritance_contract_unverified";return report;}
        for(unsigned i=0;i<8;++i)if(s.api.class_from_name(s.image,sourceSpaces[i],sourceNames[i])){report[@"state"]=@"scoped_native_name_already_exists";return report;}
        if(!build(0,base,vtable)||!build(1,base,vtable)){report[@"state"]=@"owned_metadata_public_fact_validation_failed";discardUnpublished();return report;}
        for(unsigned i=2;i<8;++i)if(!buildExtra(i,base,vtable)){report[@"state"]=@"source_component_metadata_public_fact_validation_failed";report[@"failedSourceType"]=string(sourceNames[i]);discardUnpublished();return report;}
        std::array<ehr_static_types::Record,8> records{};
        for(unsigned i=0;i<8;++i){auto k=static_cast<uint8_t *>(s.storage[i].klass);records[i]={k,s.image,k+32,k+48,-3-static_cast<int32_t>(i),sourceSpaces[i],sourceNames[i]};}
        if(s.registry.publish(records)!=ehr_static_types::Publish::Ok){report[@"state"]=@"immutable_registry_publication_failed";discardUnpublished();return report;}
        // Published metadata is process-lifetime even if a later check fails.
        report[@"registrationPerformed"]=@YES;report[@"registeredNativeTypes"]=@8;report[@"unpublishedParentFullTypeRoundtripDeferredUntilRegistryPublication"]=@YES;report[@"nativeSourceComponentMetadataCount"]=@7;report[@"allSevenSourceClrFactoriesBound"]=@NO;
        report[@"newClassesPreserveVerifiedInheritedGCBitmapAndDescriptor"]=@YES;
        report[@"inheritedReferenceGCStressTested"]=@NO;
        bool all=true;NSMutableArray *facts=[NSMutableArray array];
        for(unsigned i=0;i<8;++i){const auto checked=inspect(s.api,s.storage[i].klass);[facts addObject:checked.report];
            all=checked.checked.all()&&s.api.class_from_name(s.image,records[i].nameSpace,records[i].name)==records[i].klass&&all;}
        report[@"publishedClassPublicFactChecks"]=facts;report[@"borrowedNativeImage"]=@"UnityEngine.CoreModule.dll";
        NSMutableArray *parents=[NSMutableArray array];bool exactParents=true;
        for(unsigned i=0;i<8;++i){const P expected=i>=4&&i<=6?s.storage[3].klass:s.mono;const bool matched=s.api.class_get_parent(s.storage[i].klass)==expected;exactParents=matched&&exactParents;
            [parents addObject:@{@"sourceTypeId":@(sourceIds[i]),@"name":string(sourceNames[i]),@"expectedParent":i>=4&&i<=6?@"EHR.Patches.AbstractPagingBehaviour":@"UnityEngine.MonoBehaviour",@"publicParentMatched":@(matched)}];}
        report[@"sourceNativeParentContracts"]=parents;report[@"allSourceNativeParentContractsVerified"]=@(exactParents);report[@"nativeAddedInstanceFields"]=@0;report[@"nativeMetadataContainsOnlyUnityCallbackShims"]=@YES;
        all=exactParents&&all;
        report[@"success"]=@(all);report[@"state"]=all?@"registered_native_only_shells":@"published_type_roundtrip_failed";s.ready=all;
        return report;
    }catch(...){discardUnpublished();report[@"state"]=@"contained_cpp_exception";return report;}}
    @catch(__unused NSException *exception){discardUnpublished();report[@"state"]=@"contained_objc_exception";return report;}
}

NSDictionary *EHRStaticComponentsProbeBegin(void) {
    using namespace ehr_static_components;auto &s=state();
    if(!NSThread.isMainThread)return @{@"success":@NO,@"state":@"wrong_thread"};
    if(s.probe)return EHRStaticComponentsProbeCopyStatus();
    s.probe=[@{@"complete":@NO,@"success":@NO,@"state":@"starting",@"nativeOnlyComponentShells":@YES,@"fullEHRAvailable":@NO} mutableCopy];
    @try {try {
    if(!s.ready){finish(@"registration_not_ready",false,EHR_RUNTIME_NOT_READY);return s.probe;}
    s.roots.reserve(64); // Bounded proof needs fewer than16 roots; avoid growth after allocation.
    EHRRuntimeToken gameClass=0,unityObject=0,add=0,getComponent=0,result=0,exception=0;
    auto status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","GameObject",&gameClass);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_class("UnityEngine.CoreModule.dll","UnityEngine","Object",&unityObject);
    const char *destroyTypes[]={"UnityEngine.Object"};
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(unityObject,"Destroy",destroyTypes,1,"System.Void",1,&s.destroyMethod);
    const char *typeTypes[]={"System.Type"};
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(gameClass,"AddComponent",typeTypes,1,"UnityEngine.Component",0,&add);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(gameClass,"GetComponent",typeTypes,1,"UnityEngine.Component",0,&getComponent);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_construct(gameClass,nullptr,0,&s.gameObject,&exception);keep(s.gameObject);keep(exception);
    for(unsigned i=0;status==EHR_RUNTIME_OK&&i<2;++i){EHRRuntimeToken klass=0,type=0;
        status=ehr_runtime_find_class("UnityEngine.CoreModule.dll",i?"EHR.NativeProbes":"EHR",i?"StaticLifecycleProbe":"Coroutines",&klass);
        if(status==EHR_RUNTIME_OK)status=ehr_runtime_class_type_object(klass,&type);keep(type);
        const EHRRuntimeArgument argument{EHR_RUNTIME_REFERENCE,0,type,nullptr,0};
        if(status==EHR_RUNTIME_OK)status=call(add,s.gameObject,&argument,1,&s.components[i]);
        EHRRuntimeToken actual=0,converted=0;
        if(status==EHR_RUNTIME_OK)status=ehr_runtime_object_class(s.components[i],&actual);
        if(status==EHR_RUNTIME_OK&&actual!=klass)status=EHR_RUNTIME_TYPE_MISMATCH;
        if(status==EHR_RUNTIME_OK)status=ehr_runtime_class_from_type_object(type,&converted);
        if(status==EHR_RUNTIME_OK&&converted!=klass)status=EHR_RUNTIME_TYPE_MISMATCH;
        if(status==EHR_RUNTIME_OK)status=call(getComponent,s.gameObject,&argument,1,&result);
        int32_t same=0;if(status==EHR_RUNTIME_OK)status=ehr_runtime_object_same(result,s.components[i],&same);
        if(status==EHR_RUNTIME_OK&&same!=1)status=EHR_RUNTIME_TYPE_MISMATCH;
    }
    s.probe[@"actualAddAndGetComponentTypesAndIdentityMatch"]=@(status==EHR_RUNTIME_OK);
    EHRRuntimeToken probeClass=0,ping=0;
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_object_class(s.components[1],&probeClass);
    if(status==EHR_RUNTIME_OK)status=ehr_runtime_find_method(probeClass,"Ping",nullptr,0,"System.Void",0,&ping);
    if(status==EHR_RUNTIME_OK)status=call(ping,s.components[1],nullptr,0,&result);
    s.probe[@"actualRuntimeInvokeStaticInvokerPing"]=@(status==EHR_RUNTIME_OK&&s.counters[1].ping.load()==1);
    if(status==EHR_RUNTIME_OK&&s.counters[1].ping.load()!=1)status=EHR_RUNTIME_TYPE_MISMATCH;
    if(status!=EHR_RUNTIME_OK){finish(@"create_or_component_roundtrip_failed",false,status);return s.probe;}
    s.deadline=CFAbsoluteTimeGetCurrent()+10;s.running=true;s.probe[@"state"]=@"waiting_for_unity_update";
    s.timer=[NSTimer scheduledTimerWithTimeInterval:0.025 repeats:YES block:^(__unused NSTimer *timer){tick();}];
    return EHRStaticComponentsProbeCopyStatus();
    }catch(...){finish(@"contained_probe_cpp_exception",false,EHR_RUNTIME_LIMIT);return s.probe;}}
    @catch(__unused NSException *exception){finish(@"contained_probe_objc_exception",false,EHR_RUNTIME_UNSUPPORTED);return s.probe;}
}
NSDictionary *EHRStaticComponentsProbeCopyStatus(void) {
    using namespace ehr_static_components;auto &s=state();if(!NSThread.isMainThread)return @{@"complete":@NO,@"success":@NO,@"state":@"wrong_thread"};
    if(!s.probe)return @{@"complete":@NO,@"success":@NO,@"state":@"not_started"};
    NSMutableDictionary *copy=[s.probe mutableCopy];copy[@"counters"]=counters();copy[@"remainingOwnedObjectRoots"]=@(s.roots.size());return copy;
}
NSDictionary *EHRStaticComponentsProbeCancel(void) {
    using namespace ehr_static_components;if(!NSThread.isMainThread)return @{@"success":@NO,@"state":@"wrong_thread"};
    if(state().probe&&state().running)finish(@"cancelled",false,EHR_RUNTIME_BAD_ARGUMENT);return EHRStaticComponentsProbeCopyStatus();
}
