#import "EHRFullSourceRuntime.h"
#include "EHRRuntimeDiagnostics.h"
#include "EHRAppleAuthDiagnostics.h"
#if EHR_HAS_ITCH_AUTH
#include "EHRItchAuthProvider.h"
#endif
#if EHR_HAS_LOBBY_SEARCH
#include "EHRLobbySearch.h"
#endif
#if EHR_HAS_AUTH_HANDOFF
#include "EHRAuthHandoffDiagnostics.h"
#endif
#if EHR_HAS_GAME_START_ITERATOR
#include "EHRGameStartIteratorAdapter.h"
#endif
#if EHR_HAS_AUTH_RETRY_GUARD
#include "EHRAuthRetryGuard.h"
#endif
#if EHR_HAS_EOS_LOGIN_DIAGNOSTICS
#include "EHREOSLoginDiagnostics.h"
#endif
#include "EHRSourceFailureCleanup.inc"
#include "EHRManagedFacadeTables.h"
#include "EHRManagedActionAdapter.h"
#include "EHRManagedTypedActionAdapter.h"
#include "EHRManagedComplexDelegateAdapter.h"
#include "EHRManagedOriginalV1.h"
#include "EHRManagedPatchHostV1.h"
#include "EHRSourceHostRuntime.h"
#include "EHRSourceComponents.h"
#include "EHRStaticComponents.h"
#include "EHRTouchUI.h"
#include "EHRRuntimeGateway.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <limits.h>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#if EHR_HAS_FULL_SOURCE
#include "EHRNativePatchThunks.h"
#include "EHRManagedPatchTargetsV1.h"
#include "EHRSourceApplication.h"
#include "EHRManagedIteratorProductionV1.h"
#include "EHRManagedIteratorProduction.h"
#include "EHRFullSourceStartup.generated.h"
EHRRuntimeStatus EHRNativeGeneratedRegisterCompiled();
namespace {
struct BindState {bool attempted=false,ready=false,prepareAttempted=false,loadAttempted=false,starting=false,directoryBound=false;uint32_t flags=0;int32_t status=1,eosObserverStatus=EHR_RUNTIME_UNSUPPORTED,directoryTickStatus=0;uint64_t directoryTicks=0;int32_t(*directoryTick)(void)=nullptr;const void *image=nullptr;void *handle=nullptr;NSString *stage=@"waiting";NSString *module=nil;NSDictionary *failure=nil;NSDictionary *failureCleanup=nil;};
BindState &state(){static BindState value;return value;}
void diagnosticStage(uint32_t stage){auto app=ehr_diagnostics::state().snapshot().application;
    app.stage=stage;app.status=state().status;app.flags=state().flags;ehr_diagnostics::state().application(EHRDiagnosticTick(),app);}
void *fullExport(const char *name) {
    auto &s=state();void *value=s.handle?dlsym(s.handle,name):nullptr;Dl_info info{};
    return value&&dladdr(value,&info)&&info.dli_fbase==s.image?value:nullptr;
}
template<class Function> Function required(const char *name) {
    auto result=reinterpret_cast<Function>(fullExport(name));
    if(!result)throw std::runtime_error(name);return result;
}
template<class Table> int32_t bindTable(const char *name,const Table &table) {
    return required<int32_t(*)(const Table *,size_t)>(name)(&table,sizeof(table));
}
void check(int32_t status) {state().status=status;if(status)throw std::runtime_error("native source binding failed");}
int32_t mainThread(){return NSThread.isMainThread?1:0;}
#if EHR_HAS_EHR_DIRECTORY
int32_t directoryAllowed(){return EHRItchAuthProviderDirectoryAllowed()?1:0;}
#endif
#if EHR_HAS_LOBBY_SEARCH
int32_t lobbySearchAllowed(){return EHRItchAuthProviderDirectoryAllowed()?1:0;}
#endif
void sourceLog(int32_t level,const uint8_t *bytes,size_t count) {
    if(!bytes||count>1024*1024)return;
    NSString *text=[[NSString alloc] initWithBytes:bytes length:count encoding:NSUTF8StringEncoding];
    if(text)NSLog(@"[EHR source %d] %@",level,text);
}
void *publicRuntimeSymbol(const char *name) {
    if(!name)return nullptr;
    // The read-only layout gate also needs these exact own gateway exports.
    // IL2CPP symbols still come only from the verified game image below.
    if(!strcmp(name,"ehr_runtime_find_class"))return reinterpret_cast<void *>(&ehr_runtime_find_class);
    if(!strcmp(name,"ehr_runtime_find_method"))return reinterpret_cast<void *>(&ehr_runtime_find_method);
    if(!strcmp(name,"ehr_runtime_validate_native_method"))return reinterpret_cast<void *>(&ehr_runtime_validate_native_method);
    if(strncmp(name,"il2cpp_",7))return nullptr;
    for(uint32_t i=0;i<_dyld_image_count();++i){const char *path=_dyld_get_image_name(i);
        if(!path||!strstr(path,"/UnityFramework.framework/UnityFramework"))continue;
        void *handle=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);if(!handle)return nullptr;
        void *value=dlsym(handle,name);Dl_info info{};
        bool exact=value&&dladdr(value,&info)&&info.dli_fbase==_dyld_get_image_header(i);
        dlclose(handle);return exact?value:nullptr;}
    return nullptr;
}
int32_t requireReady(uint32_t flags) {
    if(!NSThread.isMainThread)return EHR_RUNTIME_WRONG_THREAD;
    return (state().flags&flags)==flags?0:EHR_RUNTIME_NOT_READY;
}
bool locateOwnImage() {
    NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"NativeSourceReuse.framework/NativeSourceReuse"];
    char expected[PATH_MAX]{};if(!realpath(path.fileSystemRepresentation,expected))return false;
    for(uint32_t i=0;i<_dyld_image_count();++i){const char *name=_dyld_get_image_name(i);char actual[PATH_MAX]{};
        if(name&&realpath(name,actual)&&!strcmp(expected,actual)){
            state().image=_dyld_get_image_header(i);state().handle=dlopen(name,RTLD_NOW|RTLD_NOLOAD);state().module=[NSString stringWithUTF8String:expected];return state().handle!=nullptr;}}
    return false;
}
}
#endif
NSDictionary *EHRFullSourceCopyRuntimeStatus(void) {
#if EHR_HAS_FULL_SOURCE
    if(!NSThread.isMainThread)return @{@"bindingsReady":@NO,@"status":@(EHR_RUNTIME_WRONG_THREAD)};
    EHRRuntimeGatewayPublishDiagnosticSnapshot();
    const auto &s=state();NSMutableDictionary *result=[@{@"bindingsReady":@(s.ready),@"attempted":@(s.attempted),@"readyFlags":@(s.flags),@"status":@(s.status),@"stage":s.stage,
        @"productionCoroutinesReady":@((s.flags&16)!=0),@"sourceCoroutineFailureDiagnosticsBound":@(EHRManagedIteratorProductionFailureDiagnosticsBound()),@"fullMainLoadRequested":@(s.loadAttempted)} mutableCopy];
    if(s.failure)result[@"bindingFailure"]=s.failure;
    if(s.failureCleanup)result[@"failureCleanup"]=s.failureCleanup;
#if EHR_HAS_LOBBY_SEARCH
    result[@"lobbySearch"]=EHRLobbySearchCopyStatus();
#endif
    using Status=int32_t(*)(EHRSourceApplicationStatusV1 *,size_t);
    auto status=reinterpret_cast<Status>(fullExport("ehr_source_application_status_v1"));
    if(status){EHRSourceApplicationStatusV1 app{};if(status(&app,sizeof(app))==0){
        auto diagnostic=ehr_diagnostics::state().snapshot().application;
        diagnostic.status=s.status;diagnostic.flags=s.flags;diagnostic.state=app.state;diagnostic.load_attempts=app.load_attempts;
        diagnostic.options_loaded=app.options_is_loaded_observed;diagnostic.options=app.option_count;diagnostic.active=app.active_bindings;
        diagnostic.candidates=app.candidates;diagnostic.post_load=app.options_post_load_completed;
        ehr_diagnostics::state().application(EHRDiagnosticTick(),diagnostic);
        result[@"application"]=@{@"state":@(app.state),@"status":@(app.status),@"sourceTypes":@(app.source_types),@"roleDeclarations":@(app.role_types),
            @"callbacks":@(app.callbacks),@"candidates":@(app.candidates),@"unavailableTargets":@(app.unavailable_targets),
            @"activeBindings":@(app.active_bindings),@"loadAttempts":@(app.load_attempts),@"dynamicCodeFlags":@(app.dynamic_code_flags),
            @"optionsLoaded":@(app.options_is_loaded_observed),@"optionCount":@(app.option_count),@"postLoadTasksComplete":@(app.options_post_load_completed)};}}
    result[@"numericDiagnostics"]=EHRRuntimeDiagnosticsCopyStatus();
#if EHR_HAS_ITCH_AUTH
    result[@"itchAuthentication"]=EHRItchAuthProviderCopyStatus();
#endif
#if EHR_HAS_EHR_DIRECTORY
    result[@"websiteDirectory"]=@{@"compiled":@YES,@"bound":@(s.directoryBound),@"allowed":@(directoryAllowed()==1),@"ticks":@(s.directoryTicks),@"tickStatus":@(s.directoryTickStatus)};
#endif
#if EHR_HAS_GAME_START_ITERATOR
    result[@"gameStartIterator"]=EHRGameStartIteratorCopyStatus();
#endif
#if EHR_HAS_AUTH_RETRY_GUARD
    // Own counters only. Do not prepare/activate a guard or read an account.
    result[@"authRetryGuard"]=EHRAuthRetryGuardCopyStatus();
#endif
    result[@"eosLoginObserverStatus"]=@(s.eosObserverStatus);
#if EHR_HAS_AUTH_HANDOFF
    result[@"authHandoff"]=EHRAuthHandoffDiagnosticsCopyStatus();
#endif
    if(s.status){
        auto copy=reinterpret_cast<int32_t(*)(uint8_t *,size_t,size_t *)>(fullExport("ehr_source_application_copy_error_v1"));
        uint8_t error[8192]{};size_t needed=0;
        if(copy&&copy(error,sizeof(error),&needed)==0&&needed>1&&needed<=sizeof(error))
            result[@"startupError"]=[[NSString alloc] initWithBytes:error length:needed-1 encoding:NSUTF8StringEncoding]?:@"invalid_error_text";
    }
    return result;
#else
    return @{@"bindingsReady":@NO,@"status":@(EHR_RUNTIME_UNSUPPORTED),@"stage":@"full_source_profile_not_compiled"};
#endif
}
void EHRFullSourceRefreshDirectory(void) {
#if EHR_HAS_FULL_SOURCE && EHR_HAS_EHR_DIRECTORY
    if(!NSThread.isMainThread)return;
    auto &s=state();
    if(!s.ready||s.status||!s.loadAttempted||!s.directoryBound||!s.directoryTick||directoryAllowed()!=1)return;
    ++s.directoryTicks;s.directoryTickStatus=s.directoryTick();
#endif
}
NSDictionary *EHRFullSourceBindRuntime(void) {
#if EHR_HAS_FULL_SOURCE
    if(!NSThread.isMainThread)return @{@"bindingsReady":@NO,@"status":@(EHR_RUNTIME_WRONG_THREAD)};
    EHRRuntimeDiagnosticsStart();auto &s=state();if(s.attempted)return EHRFullSourceCopyRuntimeStatus();
    diagnosticStage(1);
    const auto initialized=ehr_runtime_initialize();
    if(initialized!=EHR_RUNTIME_OK)return @{@"bindingsReady":@NO,@"status":@(initialized),@"stage":@"game_runtime_not_ready"};
    EHRRuntimeDiagnosticsRecordAuthInstall(EHRAppleAuthDiagnosticsInstall());
#if EHR_HAS_ITCH_AUTH
    // Prepares the selected provider only. No credential or login is requested.
    (void)EHRItchAuthProviderStart();
#endif
#if EHR_HAS_EOS_LOGIN_DIAGNOSTICS
    s.eosObserverStatus=EHREOSLoginDiagnosticsPrepare();
#endif
#if EHR_HAS_AUTH_HANDOFF
    // Passive metadata preparation must never change game/auth startup outcome.
    (void)EHRAuthHandoffDiagnosticsPrepare();
#endif
#if EHR_HAS_AUTH_RETRY_GUARD
    // Signed opt-in controls only the retry UX guard; no auth is started here.
    EHRAuthRetryGuardStart([NSBundle.mainBundle.infoDictionary[@"EHRAuthRetryGuardActivationRequested"] boolValue]?1:0);
#endif
    s.attempted=true;s.stage=@"full_source_module";diagnosticStage(2);
    try {
        if(!locateOwnImage()){s.status=EHR_RUNTIME_NOT_FOUND;throw std::runtime_error("full source image missing");}
        // This export distinguishes the full assembly from the small proof image.
        required<int32_t(*)(void)>("ehr_source_application_load_v1");
        check(EHRNativePatchBindFailureDiagnostics(required<EHRSourcePatchFailureV1>("ehr_source_patch_failure_v1")));
        s.stage=@"facade_tables";diagnosticStage(3);EHRManagedFacadeTables f{};EHRManagedFacadeMakeTables(&f);
        check(bindTable("ehr_generated_bind_gateway",f.gateway));check(bindTable("ehr_generated_bind_extensions",f.extensions));
        check(bindTable("ehr_generated_bind_reflection",f.reflection));check(bindTable("ehr_generated_bind_lifetime",f.lifetime));
        check(bindTable("ehr_generated_bind_type_names",f.typeNames));check(bindTable("ehr_generated_bind_methods",f.methods));
        check(bindTable("ehr_generated_bind_engine_colors",f.engineColors));
        const EHRSourceHostV1 core={1,sizeof(EHRSourceHostV1),mainThread,sourceLog};check(bindTable("ehr_source_host_bind_v1",core));s.flags|=1;
#if EHR_HAS_EHR_DIRECTORY
        // The optional directory stays denied until this app's real account
        // completion and same-credential ownership proof both hold. Binding
        // installs only the predicate; it never reads a key or sends a request.
        s.directoryTick=required<int32_t(*)(void)>("ehr_source_directory_tick_v1");
        check(required<int32_t(*)(int32_t(*)(void))>("ehr_source_directory_bind_v1")(directoryAllowed));s.directoryBound=true;
#endif
        s.stage=@"native_callbacks";diagnosticStage(4);EHRManagedActionHostV1 action{};EHRManagedActionCallbacksV1 actionCallbacks{};EHRManagedActionMakeTable(&action);
        check(required<decltype(&ehr_action_bind_gateway)>("ehr_action_bind_gateway")(&action,sizeof(action),&actionCallbacks,sizeof(actionCallbacks)));check(EHRManagedActionSetCallbacks(&actionCallbacks));
        EHRManagedActionFamiliesV1 families{};EHRManagedActionMakeFamiliesTable(&families);check(bindTable("ehr_action_bind_families",families));
        EHRManagedTypedActionHostV1 typed{};EHRManagedTypedActionCallbacksV1 typedCallbacks{};EHRManagedTypedActionMakeTable(&typed);
        check(required<decltype(&ehr_typed_action_bind_gateway)>("ehr_typed_action_bind_gateway")(&typed,sizeof(typed),&typedCallbacks,sizeof(typedCallbacks)));check(EHRManagedTypedActionSetCallbacks(&typedCallbacks));
        EHRComplexDelegateHostV1 complex{};EHRComplexDelegateCallbacksV1 complexCallbacks{};EHRComplexDelegateMakeTable(&complex);
        check(required<decltype(&ehr_complex_delegate_bind_gateway)>("ehr_complex_delegate_bind_gateway")(&complex,sizeof(complex),&complexCallbacks,sizeof(complexCallbacks)));check(EHRComplexDelegateSetCallbacks(&complexCallbacks));
        EHRManagedOriginalV1 original{};EHRManagedOriginalMakeTable(&original);check(bindTable("ehr_original_bind_gateway",original));
        EHRManagedPatchHostV1 patches{};EHRManagedPatchMakeTable(&patches);check(bindTable("ehr_source_bind_patch_host",patches));s.flags|=2;
        s.stage=@"production_coroutines";diagnosticStage(5);EHRManagedIteratorProductionV1 coroutines{};EHRManagedIteratorProductionMakeTable(&coroutines);
        check(bindTable("ehr_source_bind_coroutines_v1",coroutines));
        check(EHRManagedIteratorProductionSetFailureDiagnostics(required<EHRSourceCoroutineFailureReader>("ehr_source_coroutine_failure_v1"),EHRRuntimeDiagnosticsFlushIteratorFailure));s.flags|=16;
#if EHR_HAS_LOBBY_SEARCH
        check(EHRLobbySearchPrepare(lobbySearchAllowed));
#endif
        s.stage=@"source_components";diagnosticStage(6);NSDictionary *registered=EHRStaticComponentsRegister(publicRuntimeSymbol);
        if(![registered[@"success"] boolValue]){s.failure=registered;s.status=EHR_RUNTIME_UNSUPPORTED;throw std::runtime_error("source native type registration failed");}
        NSDictionary *components=EHRSourceComponentsBind(fullExport("ehr_generated_bind_source_components"));
        if(![components[@"success"] boolValue]){s.failure=components;s.status=EHR_RUNTIME_UNSUPPORTED;throw std::runtime_error("source component callbacks unavailable");}
        uint32_t componentProfile=0;check(required<int32_t(*)(uint32_t *)>("ehr_generated_source_component_profile_v1")(&componentProfile));
        if(componentProfile!=255){s.status=EHR_RUNTIME_UNSUPPORTED;throw std::runtime_error("full source component factories not compiled");}s.flags|=4;
        s.stage=@"touch_renderer";diagnosticStage(7);check(bindTable("ehr_touch_ui_bind_v1",*EHRTouchUIGetV1()));s.flags|=8;
        s.stage=@"compiled_native_targets";diagnosticStage(8);check(EHRNativeGeneratedRegisterCompiled());EHRManagedPatchTargetsV1 targets{};EHRNativePatchMakeTargetsTable(&targets);
        check(bindTable("ehr_source_bind_patch_targets_v1",targets));s.flags|=32;
        s.stage=@"source_application_host";diagnosticStage(9);const EHRSourceApplicationHostV1 app={1,sizeof(EHRSourceApplicationHostV1),requireReady};check(bindTable("ehr_source_application_bind_v1",app));
        s.ready=true;s.status=0;s.stage=@"bound_production_tables";diagnosticStage(10);
    } catch(const std::exception &error){if(!s.status)s.status=EHR_RUNTIME_UNSUPPORTED;NSLog(@"EHR production bind failed at %@: %s",s.stage,error.what());}
    diagnosticStage(s.ready?10:11);return EHRFullSourceCopyRuntimeStatus();
#else
    return EHRFullSourceCopyRuntimeStatus();
#endif
}

NSDictionary *EHRFullSourcePrepareApplication(void) {
#if EHR_HAS_FULL_SOURCE
    if(!NSThread.isMainThread)return @{@"status":@(EHR_RUNTIME_WRONG_THREAD)};
    EHRFullSourceBindRuntime();auto &s=state();if(!s.ready||s.prepareAttempted)return EHRFullSourceCopyRuntimeStatus();
    s.prepareAttempted=true;s.stage=@"prepare_source_application";diagnosticStage(12);
    NSError *error=nil;NSURL *support=[[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
    NSURL *root=[support URLByAppendingPathComponent:@"EHRSource" isDirectory:YES];
    if(!root||![[NSFileManager defaultManager] createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:&error]){s.status=EHR_RUNTIME_UNSUPPORTED;return EHRFullSourceCopyRuntimeStatus();}
    NSData *rootBytes=[root.path dataUsingEncoding:NSUTF8StringEncoding],*moduleBytes=[s.module dataUsingEncoding:NSUTF8StringEncoding];
    EHRSourceApplicationConfigV1 config={1,sizeof(config),static_cast<const uint8_t *>(rootBytes.bytes),rootBytes.length,
        static_cast<const uint8_t *>(moduleBytes.bytes),moduleBytes.length,nullptr,0};
    try{s.status=required<decltype(&ehr_source_application_prepare_v1)>("ehr_source_application_prepare_v1")(&config,sizeof(config));}
    catch(...){s.status=EHR_RUNTIME_UNSUPPORTED;}
    return EHRFullSourceCopyRuntimeStatus();
#else
    return EHRFullSourceCopyRuntimeStatus();
#endif
}
NSDictionary *EHRFullSourceLoadApplication(void) {
#if EHR_HAS_FULL_SOURCE
    if(!NSThread.isMainThread)return @{@"status":@(EHR_RUNTIME_WRONG_THREAD)};
    EHRFullSourcePrepareApplication();auto &s=state();if(!s.ready||s.status||s.loadAttempted)return EHRFullSourceCopyRuntimeStatus();
    s.loadAttempted=true;s.stage=@"load_source_application";diagnosticStage(13);
    try{
        s.status=required<decltype(&ehr_source_application_load_v1)>("ehr_source_application_load_v1")();
#if EHR_HAS_GAME_START_ITERATOR
        // The parent iterator hook may replace a yielded host factory only
        // while the complete source callback set is active.
        if(!s.status)s.status=EHRGameStartIteratorPrepare();
        if(!s.status)s.status=EHRGameStartIteratorSetEnabled(1);
#endif
    }
    catch(...){s.status=EHR_RUNTIME_UNSUPPORTED;}
    if(s.status){
        NSMutableDictionary *cleanup=[EHRFullSourceFailureCleanup() mutableCopy];
        // No source callback may add clips while the optional adapter retires
        // its own cache. Older reviewed source images have no audio adapter.
        auto closeAudio=reinterpret_cast<int32_t(*)(void)>(fullExport("ehr_source_audio_close_v1"));
        cleanup[@"audioAdapterPresent"]=@(closeAudio!=nullptr);
        if(closeAudio&&[cleanup[@"targetsDeactivated"] boolValue]){
            int32_t audioStatus=EHR_RUNTIME_MANAGED_EXCEPTION;
            try{audioStatus=closeAudio();}catch(...){audioStatus=EHR_RUNTIME_MANAGED_EXCEPTION;}
            cleanup[@"audioCloseAttempted"]=@YES;cleanup[@"audioCloseStatus"]=@(audioStatus);
            if(audioStatus)cleanup[@"success"]=@NO;
        }else cleanup[@"audioCloseAttempted"]=@NO;
        s.failureCleanup=cleanup;
    }
    s.stage=s.status?@"source_startup_failed":@"source_callbacks_active";diagnosticStage(s.status?14:15);
    return EHRFullSourceCopyRuntimeStatus();
#else
    return EHRFullSourceCopyRuntimeStatus();
#endif
}
void EHRFullSourceBeforeTarget(uint64_t target) {
#if EHR_HAS_FULL_SOURCE
    if(!NSThread.isMainThread||![NSBundle.mainBundle.infoDictionary[@"EHRFullSourceAutoLoad"] boolValue])return;
    bool eligible=false;for(uint64_t id:EHRFullSourceStartupTargets)eligible|=target==id;
    auto &s=state();if(!eligible||s.starting||s.loadAttempted)return;
    s.starting=true;EHRFullSourceLoadApplication();s.starting=false;
#else
    (void)target;
#endif
}
