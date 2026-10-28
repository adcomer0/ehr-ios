// Included inside the gateway's private namespace, before object().
std::unordered_set<EHRRuntimeToken> &weakTokens() { static std::unordered_set<EHRRuntimeToken> tokens;return tokens; }
struct WeakTokenScope {
    struct Lease {EHRRuntimeToken token=0;uint32_t handle=0;};
    std::array<Lease,kMaxArguments+1> leases{};
    size_t count=0;
    WeakTokenScope *prior=nullptr;
    static thread_local WeakTokenScope *current;
    WeakTokenScope() noexcept:prior(current){current=this;}
    ~WeakTokenScope(){for(size_t i=count;i>0;--i)state().api.gchandle_free(leases[i-1].handle);current=prior;}
    WeakTokenScope(const WeakTokenScope &)=delete;
    WeakTokenScope &operator=(const WeakTokenScope &)=delete;
    EHRRuntimeStatus promote(EHRRuntimeToken token,uint32_t weakHandle,Object **value) {
        for(size_t i=0;i<count;++i)if(leases[i].token==token){
            *value=state().api.gchandle_get_target(leases[i].handle);return *value?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;}
        if(count==leases.size())return diagnosticLimit(ehr_diagnostics::WeakPromotionCapacity,count,leases.size());
        Object *borrowed=state().api.gchandle_get_target(weakHandle);
        if(!borrowed)return EHR_RUNTIME_INVALID_TOKEN;
        const uint32_t strong=state().api.gchandle_new(borrowed,false);
        if(!strong)return EHR_RUNTIME_NOT_READY;
        leases[count++]={token,strong};
        *value=state().api.gchandle_get_target(strong);
        return *value?EHR_RUNTIME_OK:EHR_RUNTIME_INVALID_TOKEN;
    }
};
thread_local WeakTokenScope *WeakTokenScope::current=nullptr;
