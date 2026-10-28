// Finite, native-only System.Action protocol proof. This is not a delegate
// ownership API. One immutable callback metadata record lives for the process;
// no object/class injection, runtime code generation, event registration, or
// executable memory mutation is performed.
namespace action_prototype {
struct alignas(8) PinnedMethodInfo2022 {
    void *methodPointer;
    void *virtualMethodPointer;
    void *invokerMethod;
    const char *name;
    void *klass;
    const void *returnType;
    const void *parameters;
    void *runtimeData;
    void *genericData;
    uint32_t token;
    uint16_t flags;
    uint16_t implementationFlags;
    uint16_t slot;
    uint8_t parameterCount;
    uint8_t bitfield;
};
static_assert(sizeof(PinnedMethodInfo2022)==88);
static_assert(offsetof(PinnedMethodInfo2022,slot)==80);
static_assert(offsetof(PinnedMethodInfo2022,parameterCount)==82);
static PinnedMethodInfo2022 callbackMetadata{};
static void *expectedSelf=nullptr;
static uint64_t callbacks=0;
static bool selfMatched=true, metadataMatched=true, mainThreadMatched=true;
static void callback(void *self,const void *method) noexcept {
    ++callbacks;
    selfMatched=selfMatched && self==expectedSelf;
    metadataMatched=metadataMatched && method==&callbackMetadata;
    mainThreadMatched=mainThreadMatched && pthread_main_np()!=0;
}

struct API {
    void *(*domain_get)();
    const void **(*domain_get_assemblies)(void *,size_t *);
    const void *(*assembly_get_image)(const void *);
    const char *(*image_get_name)(const void *);
    void *(*class_from_name)(const void *,const char *,const char *);
    const void *(*class_get_methods)(void *,void **);
    const char *(*method_get_name)(const void *);
    uint32_t (*method_get_param_count)(const void *);
    const void *(*method_get_param)(const void *,uint32_t);
    const void *(*method_get_return_type)(const void *);
    uint32_t (*method_get_flags)(const void *,uint32_t *);
    void *(*method_get_class)(const void *);
    char *(*type_get_name)(const void *);
    void (*free)(void *);
    void *(*object_new)(void *);
    void *(*runtime_invoke)(const void *,void *,void **,void **);
    void *(*method_get_object)(const void *,void *);
    void *(*class_get_field_from_name)(void *,const char *);
    const void *(*field_get_type)(void *);
    uint32_t (*field_get_flags)(void *);
    void (*field_set_value)(void *,void *,void *);
    void (*field_set_value_object)(void *,void *,void *);
    void (*field_get_value)(void *,void *,void *);
    uint32_t (*gchandle_new)(void *,bool);
    void *(*gchandle_get_target)(uint32_t);
    void (*gchandle_free)(uint32_t);
    bool load() {
#define ACTION_API(name) name=reinterpret_cast<decltype(name)>(bridgeExport("il2cpp_" #name)); if(!name) return false
        ACTION_API(domain_get);ACTION_API(domain_get_assemblies);ACTION_API(assembly_get_image);
        ACTION_API(image_get_name);ACTION_API(class_from_name);ACTION_API(class_get_methods);
        ACTION_API(method_get_name);ACTION_API(method_get_param_count);ACTION_API(method_get_param);
        ACTION_API(method_get_return_type);ACTION_API(method_get_flags);ACTION_API(method_get_class);
        ACTION_API(type_get_name);ACTION_API(free);ACTION_API(object_new);ACTION_API(runtime_invoke);
        ACTION_API(method_get_object);ACTION_API(class_get_field_from_name);ACTION_API(field_get_type);
        ACTION_API(field_get_flags);ACTION_API(field_set_value);ACTION_API(field_set_value_object);
        ACTION_API(field_get_value);ACTION_API(gchandle_new);ACTION_API(gchandle_get_target);ACTION_API(gchandle_free);
#undef ACTION_API
        return true;
    }
    bool typeEquals(const void *type,const char *expected) {
        if(!type) return false;
        char *name=type_get_name(type);
        const bool same=name && !strcmp(name,expected);
        if(name) free(name);
        return same;
    }
    const void *method(void *klass,const char *name,const std::vector<const char *> &parameters,const char *returns) {
        void *iterator=nullptr;
        const void *match=nullptr;
        for(size_t i=0;i<4096;++i) {
            const void *candidate=class_get_methods(klass,&iterator);
            if(!candidate) return match;
            const char *candidateName=method_get_name(candidate);
            uint32_t impl=0;
            if(!candidateName || strcmp(candidateName,name) || method_get_class(candidate)!=klass ||
               method_get_param_count(candidate)!=parameters.size() || (method_get_flags(candidate,&impl)&0x10) ||
               !typeEquals(method_get_return_type(candidate),returns)) continue;
            bool exact=true;
            for(size_t p=0;p<parameters.size();++p)
                exact=exact && typeEquals(method_get_param(candidate,static_cast<uint32_t>(p)),parameters[p]);
            if(exact) { if(match) return nullptr; match=candidate; }
        }
        return nullptr;
    }
    void *field(void *klass,const char *name,const char *type) {
        void *result=class_get_field_from_name(klass,name);
        return result && !(field_get_flags(result)&0x10) && typeEquals(field_get_type(result),type) ? result : nullptr;
    }
};
}

NSDictionary *exerciseNativeActionDelegatePrototype() {
    using namespace action_prototype;
    NSMutableDictionary *proof=[NSMutableDictionary dictionary];
    bool passed=true;
    auto check=[&](NSString *name,bool value){proof[name]=@(value);passed=passed && value;};
    if(!NSThread.isMainThread) return @{ @"success":@NO,@"error":@"Unity main thread required" };
    // This full framework SHA/UUID validation must succeed before the private
    // version-specific callback metadata protocol is initialized or consumed.
#define ACTION_GATEWAY(name) auto name=reinterpret_cast<decltype(&ehr_runtime_##name)>(bridgeExport("ehr_runtime_" #name)); if(!name) return @{ @"success":@NO,@"missingExport":@#name }
    ACTION_GATEWAY(find_class);ACTION_GATEWAY(find_method);ACTION_GATEWAY(validate_native_method);
#undef ACTION_GATEWAY
    EHRRuntimeToken constants=0,version=0;
    uint64_t observedRva=0;
    const bool pinned=find_class("Assembly-CSharp.dll","","Constants",&constants)==EHR_RUNTIME_OK &&
        find_method(constants,"GetBroadcastVersion",nullptr,0,"System.Int32",1,&version)==EHR_RUNTIME_OK &&
        validate_native_method(version,30734292,&observedRva)==EHR_RUNTIME_OK;
    check(@"fullSignedFrameworkHashUuidAndVersionAssociationGate",pinned);
    if(!pinned) {proof[@"success"]=@NO;return proof;}
    if(callbacks || expectedSelf) return @{ @"success":@NO,@"error":@"Finite prototype already consumed" };
    API api{};
    if(!api.load()) return @{ @"success":@NO,@"error":@"Required public IL2CPP exports missing" };
    void *domain=api.domain_get();size_t assemblyCount=0;
    const void **assemblies=domain ? api.domain_get_assemblies(domain,&assemblyCount) : nullptr;
    const void *coreImage=nullptr;
    if(assemblies && assemblyCount<=4096) for(size_t i=0;i<assemblyCount;++i) {
        const void *image=api.assembly_get_image(assemblies[i]);
        const char *name=image ? api.image_get_name(image) : nullptr;
        if(name && !strcmp(name,"mscorlib.dll")) { if(coreImage) return @{ @"success":@NO,@"error":@"Ambiguous core image" };coreImage=image; }
    }
    void *actionClass=coreImage ? api.class_from_name(coreImage,"System","Action") : nullptr;
    void *objectClass=coreImage ? api.class_from_name(coreImage,"System","Object") : nullptr;
    void *delegateClass=coreImage ? api.class_from_name(coreImage,"System","Delegate") : nullptr;
    const void *actionCtor=actionClass ? api.method(actionClass,".ctor",{"System.Object","System.IntPtr"},"System.Void") : nullptr;
    const void *actionInvoke=actionClass ? api.method(actionClass,"Invoke",{},"System.Void") : nullptr;
    const void *objectCtor=objectClass ? api.method(objectClass,".ctor",{},"System.Void") : nullptr;
    check(@"exactActualObjectActionConstructorAndInvokeMetadata",actionCtor && actionInvoke && objectCtor && delegateClass);
    if(!actionCtor || !actionInvoke || !objectCtor || !delegateClass) {proof[@"success"]=@NO;return proof;}
    void *methodPtrField=api.field(delegateClass,"method_ptr","System.IntPtr");
    void *invokeImplField=api.field(delegateClass,"invoke_impl","System.IntPtr");
    void *methodField=api.field(delegateClass,"method","System.IntPtr");
    void *methodCodeField=api.field(delegateClass,"method_code","System.IntPtr");
    void *targetField=api.field(delegateClass,"m_target","System.Object");
    void *methodInfoField=api.field(delegateClass,"method_info","System.Reflection.MethodInfo");
    check(@"exactPublicDelegateFieldMetadata",methodPtrField && invokeImplField && methodField && methodCodeField && targetField && methodInfoField);
    if(![proof[@"exactPublicDelegateFieldMetadata"] boolValue]) {proof[@"success"]=@NO;return proof;}
    std::vector<uint32_t> roots;
    auto root=[&](void *object) {
        const uint32_t handle=object ? api.gchandle_new(object,true) : 0;
        if(handle) roots.push_back(handle);
        return handle ? api.gchandle_get_target(handle) : nullptr;
    };
    auto cleanup=[&]() {for(const auto handle:roots) api.gchandle_free(handle);proof[@"ownRootAllocations"]=@(roots.size());proof[@"ownRootReleases"]=@(roots.size());roots.clear();expectedSelf=nullptr;};
    callbackMetadata.methodPointer=reinterpret_cast<void *>(&callback);
    callbackMetadata.virtualMethodPointer=reinterpret_cast<void *>(&callback);
    callbackMetadata.slot=UINT16_MAX;
    callbackMetadata.parameterCount=0;
    void *exception=nullptr;
    void *holder=root(api.object_new(objectClass));
    check(@"realNativeSystemObjectCarrierAllocatedAndPinned",holder!=nullptr);
    if(holder) api.runtime_invoke(objectCtor,holder,nullptr,&exception);
    check(@"realSystemObjectConstructorCaught",holder && !exception);
    if(exception || !holder) {root(exception);cleanup();proof[@"success"]=@NO;return proof;}
    void *delegate=root(api.object_new(actionClass));
    void *metadata=&callbackMetadata;
    void *ctorArguments[]={holder,&metadata};
    if(delegate) api.runtime_invoke(actionCtor,delegate,ctorArguments,&exception);
    check(@"realActionObjectIntPtrConstructorCaught",delegate && !exception);
    if(exception || !delegate) {root(exception);cleanup();proof[@"success"]=@NO;return proof;}
    void *reflection=root(api.method_get_object(actionInvoke,nullptr));
    check(@"realActionInvokeReflectionMethodInfo",reflection!=nullptr);
    if(!reflection) {cleanup();proof[@"success"]=@NO;return proof;}
    void *entry=reinterpret_cast<void *>(&callback);
    api.field_set_value(delegate,methodPtrField,&entry);
    api.field_set_value(delegate,invokeImplField,&entry);
    api.field_set_value(delegate,methodField,&metadata);
    api.field_set_value(delegate,methodCodeField,&holder);
    api.field_set_value_object(delegate,targetField,holder);
    api.field_set_value_object(delegate,methodInfoField,reflection);
    auto fieldEquals=[&](void *field,void *expected) {void *value=nullptr;api.field_get_value(delegate,field,&value);return value==expected;};
    check(@"publicFieldWritesRoundTrip",fieldEquals(methodPtrField,entry) && fieldEquals(invokeImplField,entry) &&
        fieldEquals(methodField,metadata) && fieldEquals(methodCodeField,holder) && fieldEquals(targetField,holder) && fieldEquals(methodInfoField,reflection));
    expectedSelf=holder;
    void *returned=api.runtime_invoke(actionInvoke,delegate,nullptr,&exception);
    check(@"actualActionInvokeEnteredStaticCompiledCallback",!returned && !exception && callbacks==1);
    if(exception) root(exception);
    check(@"callbackReceivedExactPinnedCarrierSelf",selfMatched);
    check(@"callbackReceivedOwnHiddenMethodMetadata",metadataMatched);
    check(@"callbackRemainedOnUnityMainThread",mainThreadMatched);
    exception=nullptr;
    returned=api.runtime_invoke(actionInvoke,delegate,nullptr,&exception);
    check(@"repeatInvocationUsesSameDelegateAndCarrier",!returned && !exception && callbacks==2 && selfMatched && metadataMatched);
    if(exception) root(exception);
    proof[@"callbackCount"]=@(callbacks);
    cleanup();
    proof[@"metadataRecordBytes"]=@(sizeof(PinnedMethodInfo2022));
    proof[@"metadataLifetime"]=@"One process-lived immutable native record; finite proof only";
    proof[@"classInjectionPerformed"]=@NO;proof[@"runtimeCodeGenerationPerformed"]=@NO;
    proof[@"eventSubscriptionPerformed"]=@NO;proof[@"gameplayMutationPerformed"]=@NO;
    proof[@"success"]=@(passed);
    return proof;
}
