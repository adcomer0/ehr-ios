// Include after helperExport(), with Foundation and EHRRuntimeGateway.h.
// The default requires the new native implementation. Only the separate
// exploratory old-candidate overlay passes false to test the public API first.
namespace ehr_iterator_factory_probe {
struct API {
    void *(*corlib)()=nullptr;
    void *(*create)(const void *,const char *,const char *,const char *)=nullptr;
    void (*raise)(void *)=nullptr;
    const char *(*imageName)(const void *)=nullptr;
    void *(*findClass)(const void *,const char *,const char *)=nullptr;
    bool (*assignable)(void *,void *)=nullptr;
    void *(*objectClass)(void *)=nullptr;
    uint32_t (*newHandle)(void *,bool)=nullptr;
    void *(*target)(uint32_t)=nullptr;
    void (*freeHandle)(uint32_t)=nullptr;
};
void *engineExport(const char *name){
    for(uint32_t i=0;i<_dyld_image_count();++i){
        const char *path=_dyld_get_image_name(i);
        if(!path||!strstr(path,"/UnityFramework.framework/UnityFramework"))continue;
        void *handle=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);
        void *result=handle?dlsym(handle,name):nullptr;if(handle)dlclose(handle);return result;
    }
    return nullptr;
}
struct Counts {uint64_t created=0,released=0;};
struct Pin {
    API *api=nullptr;Counts *counts=nullptr;uint32_t handle=0;
    ~Pin(){if(handle){api->freeHandle(handle);++counts->released;}}
};
struct Failed {int32_t status;};
void require(bool ok,int32_t status=EHR_RUNTIME_TYPE_MISMATCH){if(!ok)throw Failed{status};}
}
static NSDictionary *EHRRuntimeIteratorExceptionFactoryProof(bool requireBridge=true){
    using namespace ehr_iterator_factory_probe;
    auto bridge=reinterpret_cast<NSDictionary *(*)()>(helperExport("EHRRuntimeIteratorExceptionSelfTest"));
    if(bridge)return bridge();
    if(requireBridge||!NSThread.isMainThread)return @{@"schema":@"ehr.iterator-exception-factory-proof.v1",@"success":@NO,@"status":@(NSThread.isMainThread?EHR_RUNTIME_NOT_FOUND:EHR_RUNTIME_WRONG_THREAD)};
    API api;Counts counts;size_t before=0,after=0;uint32_t made=0,types=0,caught=0,returned=0;int32_t status=0;
    auto rootCount=reinterpret_cast<decltype(&ehr_runtime_object_root_count)>(helperExport("ehr_runtime_object_root_count"));
    // Same existing whole-image/UUID gate used by the tested63 helper. This is
    // an exported C++ native capability, not a raw pointer supplied by C#.
    auto validate=reinterpret_cast<EHRRuntimeStatus(*)(const void *)>(helperExport("_ZN10ehr_pinned21validate_engine_entryEPKv"));
    @try{try{
        require(rootCount&&validate,EHR_RUNTIME_NOT_FOUND);require(rootCount(&before)==0);
#define FACTORY_API(member,name) api.member=reinterpret_cast<decltype(api.member)>(engineExport(name));require(api.member!=nullptr,EHR_RUNTIME_NOT_FOUND);require(validate(reinterpret_cast<const void *>(api.member))==EHR_RUNTIME_OK)
        FACTORY_API(corlib,"il2cpp_get_corlib");FACTORY_API(create,"il2cpp_exception_from_name_msg");
        FACTORY_API(raise,"il2cpp_raise_exception");FACTORY_API(imageName,"il2cpp_image_get_name");
        FACTORY_API(findClass,"il2cpp_class_from_name");FACTORY_API(assignable,"il2cpp_class_is_assignable_from");
        FACTORY_API(objectClass,"il2cpp_object_get_class");FACTORY_API(newHandle,"il2cpp_gchandle_new");
        FACTORY_API(target,"il2cpp_gchandle_get_target");FACTORY_API(freeHandle,"il2cpp_gchandle_free");
#undef FACTORY_API
        void *core=api.corlib();require(core!=nullptr,EHR_RUNTIME_NOT_READY);const char *image=api.imageName(core);require(image&&!strcmp(image,"mscorlib.dll"));
        void *base=api.findClass(core,"System","Exception");require(base!=nullptr,EHR_RUNTIME_NOT_FOUND);
        const char *names[]={"InvalidOperationException","NotSupportedException"};
        for(size_t i=0;i<2;++i){
            void *expected=api.findClass(core,"System",names[i]);require(expected&&api.assignable(base,expected));
            void *value=api.create(core,"System",names[i],"EHR source iterator failed.");require(value!=nullptr,EHR_RUNTIME_NOT_READY);
            Pin pin;pin.api=&api;pin.counts=&counts;pin.handle=api.newHandle(value,true);require(pin.handle!=0,EHR_RUNTIME_NOT_READY);++counts.created;
            value=api.target(pin.handle);require(value!=nullptr);made|=uint32_t(1)<<i;
            require(api.objectClass(value)==expected);types|=uint32_t(1)<<i;
            try{api.raise(value);returned|=uint32_t(1)<<i;}catch(...){caught|=uint32_t(1)<<i;}
            require(api.target(pin.handle)==value&&api.objectClass(value)==expected);
        }
    }catch(const Failed &failure){status=failure.status;}catch(...){status=EHR_RUNTIME_MANAGED_EXCEPTION;}}
    @catch(__unused NSException *error){status=EHR_RUNTIME_MANAGED_EXCEPTION;}
    if(!rootCount||rootCount(&after)!=0)status=EHR_RUNTIME_NOT_READY;
    const bool success=!status&&made==3&&types==3&&caught==3&&!returned&&counts.created==2&&counts.released==2&&before==after;
    return @{@"schema":@"ehr.iterator-exception-factory-proof.v1",@"success":@(success),@"status":@(status),
        @"constructedMask":@(made),@"exactTypeMask":@(types),@"caughtMask":@(caught),@"returnedMask":@(returned),
        @"nativeHandlesCreated":@(counts.created),@"nativeHandlesReleased":@(counts.released),
        @"rootsBefore":@(before),@"rootsAfter":@(after),@"rootAccountingBalanced":@(before==after&&counts.created==counts.released),
        @"reflectionActivatorUsed":@NO,@"nativeAotCallbackEntered":@NO,@"gameOwnerInvoked":@NO,@"accountOrNetworkActions":@NO,
        @"directPublicApiExploratoryProbe":@YES};
}
