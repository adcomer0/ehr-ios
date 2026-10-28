#import <XCTest/XCTest.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <cstring>
#include "native/EHRRuntimeGateway.h"
#ifndef EHR_EXERCISE_FAILURE_CLEANUP
#define EHR_EXERCISE_FAILURE_CLEANUP 0
#endif
#ifndef EHR_EXERCISE_AUDIO
#define EHR_EXERCISE_AUDIO 0
#endif
#ifndef EHR_EXERCISE_AUDIO_LOADER
#define EHR_EXERCISE_AUDIO_LOADER 0
#endif
#ifndef EHR_EXERCISE_SOURCE_ACTION
#define EHR_EXERCISE_SOURCE_ACTION 0
#endif
#ifndef EHR_EXERCISE_TOUCH_SHORTCUTS
#define EHR_EXERCISE_TOUCH_SHORTCUTS 0
#endif
#ifndef EHR_EXERCISE_ITERATOR_RETIREMENT
#define EHR_EXERCISE_ITERATOR_RETIREMENT 0
#endif

namespace {
void *helperExport(const char *name) {
    for(uint32_t i=0;i<_dyld_image_count();++i){
        const char *path=_dyld_get_image_name(i);
        if(!path||!strstr(path,"/EHRNativeHooks.dylib"))continue;
        void *handle=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);
        void *result=handle?dlsym(handle,name):nullptr;if(handle)dlclose(handle);return result;
    }
    return nullptr;
}
NSDictionary *applicationVersion() {
#define VERSION_API(name) auto name=reinterpret_cast<decltype(&ehr_runtime_##name)>(helperExport("ehr_runtime_" #name)); if(!name)return @{@"success":@NO}
    VERSION_API(find_class);VERSION_API(find_method);VERSION_API(invoke);VERSION_API(string_copy);VERSION_API(object_release);
#undef VERSION_API
    EHRRuntimeToken klass=0,method=0,result=0,exception=0;
    int32_t code=find_class("UnityEngine.CoreModule.dll","UnityEngine","Application",&klass);
    if(!code)code=find_method(klass,"get_version",nullptr,0,"System.String",1,&method);
    if(!code)code=invoke(method,0,nullptr,0,&result,&exception);
    uint16_t units[64]={};size_t length=0;
    if(!code)code=string_copy(result,units,64,&length);
    NSString *value=code?nil:[[NSString alloc] initWithCharacters:units length:length];
    if(result)object_release(result);if(exception)object_release(exception);
    NSString *expected=NSBundle.mainBundle.infoDictionary[@"EHRReferenceGameVersion"];
    bool matches=code==0&&value.length&&[value isEqualToString:expected]&&
        [value isEqualToString:NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]]&&![value isEqualToString:@"0.0.0"];
    return @{@"success":@(matches),@"status":@(code),@"value":value?:@"",@"expected":expected?:@""};
}
NSDictionary *status() {
    for(uint32_t i=0;i<_dyld_image_count();++i){
        const char *path=_dyld_get_image_name(i);
        if(!path||!strstr(path,"/EHRNativeHooks.dylib"))continue;
        void *handle=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);
        auto fn=reinterpret_cast<NSDictionary *(*)(void)>(handle?dlsym(handle,"EHRFullSourceCopyRuntimeStatus"):nullptr);
        NSDictionary *result=fn?fn():nil;if(handle)dlclose(handle);return result;
    }
    return nil;
}
}
#if EHR_EXERCISE_ITERATOR_RETIREMENT
#include "IteratorRetirementProof.inc"
#endif
@interface NativeRuntimeTests:XCTestCase
@end
@implementation NativeRuntimeTests
- (void)testSignedCandidateLoadsActualRuntime {
    XCTAssertTrue([NSBundle.mainBundle.infoDictionary[@"EHRFullSourceAutoLoad"] boolValue]);
    XCTestExpectation *finished=[self expectationWithDescription:@"Original EHR startup and options initialization"];
    __block NSDictionary *last=nil;__block bool fulfilled=false;
    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),100*NSEC_PER_MSEC,10*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{
        last=status();NSDictionary *app=last[@"application"];
        bool failed=[app[@"state"] unsignedIntValue]==4 || ([last[@"attempted"] boolValue]&&[last[@"status"] intValue]!=0);
        bool complete=[app[@"state"] unsignedIntValue]==3&&[app[@"postLoadTasksComplete"] boolValue];
        if(!fulfilled&&(failed||complete)) {fulfilled=true;dispatch_source_cancel(timer);[finished fulfill];}
    });
    dispatch_resume(timer);[self waitForExpectations:@[finished] timeout:45];dispatch_source_cancel(timer);
    last=status()?:last?:@{};NSDictionary *app=last[@"application"]?:@{};
    NSDictionary *version=applicationVersion();
    NSDictionary *proof=@{@"schema":@"ehr.full-source-startup-proof.v1",@"status":last,@"startupReachedTerminalObservation":@(fulfilled),
        @"applicationVersion":version,
        @"startupInvokedByTest":@NO,@"termsAcceptedByTest":@NO,@"accountActionsPerformed":@NO,@"multiplayerVerified":@NO};
    NSData *data=[NSJSONSerialization dataWithJSONObject:proof options:NSJSONWritingPrettyPrinted error:nil];
    NSLog(@"EHR_NATIVE_RUNTIME_TEST %@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    XCTAttachment *attachment=[XCTAttachment attachmentWithData:data uniformTypeIdentifier:@"public.json"];
    attachment.name=@"EHRNativeXCTestProof.json";attachment.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:attachment];
    XCTAssertTrue([last[@"bindingsReady"] boolValue],@"%@",last);
    XCTAssertTrue([version[@"success"] boolValue],@"%@",version);
    NSDictionary *diagnostics=last[@"numericDiagnostics"];
    XCTAssertEqualObjects(diagnostics[@"schema"],@"ehr.numeric-runtime-diagnostics.v1");
    XCTAssertEqualObjects(diagnostics[@"writeStatus"],@0);
    XCTAssertGreaterThan([diagnostics[@"writtenSequence"] unsignedLongLongValue],0ULL);
    XCTAssertGreaterThan([diagnostics[@"routes"] count],0u);
    XCTAssertEqualObjects(diagnostics[@"guardLimit"],@32);
    XCTAssertEqualObjects(diagnostics[@"failureDetailLimit"],@32);
    XCTAssertNotNil(diagnostics[@"failureDetailTotal"]);
    XCTAssertTrue([diagnostics[@"failureDetails"] isKindOfClass:NSArray.class]);
    XCTAssertLessThanOrEqual([diagnostics[@"failureDetails"] count],32u);
    XCTAssertEqualObjects(diagnostics[@"gateway"][@"loaded"],@1);
    XCTAssertEqualObjects(diagnostics[@"gateway"][@"rootLimit"],@65536);
    XCTAssertGreaterThan([diagnostics[@"gateway"][@"samples"] unsignedLongLongValue],0ULL);
    XCTAssertGreaterThan([diagnostics[@"gateway"][@"monotonicNs"] unsignedLongLongValue],0ULL);
    XCTAssertEqualObjects(diagnostics[@"productionIterators"][@"entryLimit"],@256);
    XCTAssertGreaterThan([diagnostics[@"productionIterators"][@"monotonicNs"] unsignedLongLongValue],0ULL);
    for(NSDictionary *route in diagnostics[@"routes"]){
        XCTAssertNotNil(route[@"lastPhase"]);
        XCTAssertNotNil(route[@"lastArgument"]);
    }
    XCTAssertEqualObjects(diagnostics[@"appleAuth"][@"installStatus"],@0);
    if([NSBundle.mainBundle.infoDictionary[@"EHREOSLoginDiagnosticsEnabled"] boolValue])
        XCTAssertEqualObjects(last[@"eosLoginObserverStatus"],@0);
    if([NSBundle.mainBundle.infoDictionary[@"EHRAuthRetryGuardActivationRequested"] boolValue]){
        NSDictionary *guard=last[@"authRetryGuard"];
        XCTAssertTrue([guard[@"startupRequested"] boolValue]);
        XCTAssertEqualObjects(guard[@"preparedStatus"],@0);
        XCTAssertEqualObjects(guard[@"startupPrepareStatus"],@0);
        XCTAssertEqualObjects(guard[@"startupEnableStatus"],@0);
        XCTAssertTrue([guard[@"enabled"] boolValue]);
        XCTAssertEqualObjects(guard[@"failureHandlerEntries"],@0);
        XCTAssertEqualObjects(guard[@"failureHandlerCompleted"],@0);
    }
    XCTAssertEqual([last[@"status"] intValue],0,@"%@",last);
    XCTAssertEqual([app[@"state"] unsignedIntValue],3u,@"%@",last);
    XCTAssertEqual([app[@"loadAttempts"] unsignedIntValue],1u);
    XCTAssertEqual([app[@"candidates"] unsignedIntValue],298u);
    XCTAssertEqual([app[@"unavailableTargets"] unsignedIntValue],0u);
    XCTAssertGreaterThan([app[@"activeBindings"] unsignedIntValue],0u);
    XCTAssertEqual([app[@"dynamicCodeFlags"] unsignedIntValue],0u);
    XCTAssertTrue([app[@"optionsLoaded"] boolValue],@"%@",last);
    XCTAssertGreaterThan([app[@"optionCount"] unsignedIntValue],0u);
    XCTAssertTrue([app[@"postLoadTasksComplete"] boolValue],@"%@",last);
#if EHR_EXERCISE_ITERATOR_RETIREMENT
    // Own native ArrayList carriers only; warm the fixed marker before later
    // ownership baselines. No Unity scheduling, account or network action.
    NSDictionary *retirement=EHRRuntimeIteratorRetirementProof();
    NSData *retirementData=[NSJSONSerialization dataWithJSONObject:retirement options:NSJSONWritingPrettyPrinted error:nil];
    NSLog(@"EHR_ITERATOR_RETIREMENT_PROOF %@",[[NSString alloc] initWithData:retirementData encoding:NSUTF8StringEncoding]);
    XCTAttachment *retirementAttachment=[XCTAttachment attachmentWithData:retirementData uniformTypeIdentifier:@"public.json"];
    retirementAttachment.name=@"EHRIteratorRetirementProof.json";retirementAttachment.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:retirementAttachment];
    XCTAssertTrue([retirement[@"success"] boolValue],@"%@",retirement);
#endif
#if EHR_EXERCISE_TOUCH_SHORTCUTS
    void *touchModule=nullptr,*touchHelper=nullptr;
    for(uint32_t i=0;i<_dyld_image_count();++i){const char *path=_dyld_get_image_name(i);if(!path)continue;
        if(strstr(path,"/NativeSourceReuse.framework/NativeSourceReuse"))touchModule=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);
        if(strstr(path,"/EHRNativeHooks.dylib"))touchHelper=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);}
    auto scalarProbe=reinterpret_cast<int32_t(*)(int32_t *,size_t)>(touchModule?dlsym(touchModule,"ehr_ios_touch_shortcuts_self_test_v1"):nullptr);
    auto identityProbe=reinterpret_cast<int32_t(*)(int32_t *,size_t)>(touchModule?dlsym(touchModule,"ehr_ios_touch_identity_self_test_v1"):nullptr);
    auto rootCount=reinterpret_cast<int32_t(*)(size_t *)>(touchHelper?dlsym(touchHelper,"ehr_runtime_object_root_count"):nullptr);
    int32_t scalarWords[12]={},identityWords[8]={};size_t rootsBefore=0,rootsAfter=0;
    int32_t scalarStatus=scalarProbe?scalarProbe(scalarWords,12):-1;
    int32_t rootsBeforeStatus=rootCount?rootCount(&rootsBefore):-1;
    int32_t identityStatus=identityProbe?identityProbe(identityWords,8):-1;
    int32_t rootsAfterStatus=rootCount?rootCount(&rootsAfter):-1;
    XCTAssertEqual(scalarStatus,0);for(size_t i=0;i<12;++i)XCTAssertEqual(scalarWords[i],i==11?0:1);
    XCTAssertEqual(identityStatus,0);XCTAssertEqual(identityWords[0],1);XCTAssertEqual(identityWords[1],1);
    XCTAssertNotEqual(identityWords[2],0);XCTAssertEqual(identityWords[3],identityWords[2]);XCTAssertEqual(identityWords[4],identityWords[2]);
    XCTAssertEqual(identityWords[5],1);XCTAssertEqual(identityWords[6],1);XCTAssertEqual(identityWords[7],0);
    XCTAssertEqual(rootsBeforeStatus,0);XCTAssertEqual(rootsAfterStatus,0);XCTAssertEqual(rootsAfter,rootsBefore);
    NSMutableArray *scalarValues=[NSMutableArray array],*identityValues=[NSMutableArray array];
    for(int32_t value:scalarWords)[scalarValues addObject:@(value)];for(int32_t value:identityWords)[identityValues addObject:@(value)];
    NSDictionary *touchProof=@{@"schema":@"ehr.full-source-touch-shortcuts-proof.v1",@"scalarStatus":@(scalarStatus),@"scalarWords":scalarValues,
        @"identityStatus":@(identityStatus),@"identityWords":identityValues,@"rootsBeforeStatus":@(rootsBeforeStatus),@"rootsAfterStatus":@(rootsAfterStatus),
        @"ownedObjectTokensBefore":@(rootsBefore),@"ownedObjectTokensAfter":@(rootsAfter),@"accountActionsPerformed":@NO,@"ownGameObjectOnly":@YES};
    if(touchModule)dlclose(touchModule);if(touchHelper)dlclose(touchHelper);
    NSData *touchData=[NSJSONSerialization dataWithJSONObject:touchProof options:NSJSONWritingPrettyPrinted error:nil];
    XCTAttachment *touchAttachment=[XCTAttachment attachmentWithData:touchData uniformTypeIdentifier:@"public.json"];
    touchAttachment.name=@"EHRSourceTouchShortcutsProof.json";touchAttachment.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:touchAttachment];
    // Allow the normal Unity loop to process the own probe's deferred Destroy.
    XCTestExpectation *touchFrame=[self expectationWithDescription:@"Unity frame after own identity probe"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[touchFrame fulfill];});
    [self waitForExpectations:@[touchFrame] timeout:2];
#endif
#if EHR_EXERCISE_SOURCE_ACTION
    void *actionModule=nullptr;
    for(uint32_t i=0;i<_dyld_image_count();++i){const char *path=_dyld_get_image_name(i);
        if(path&&strstr(path,"/NativeSourceReuse.framework/NativeSourceReuse")){actionModule=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);break;}}
    auto actionProbe=reinterpret_cast<int32_t(*)(int32_t *,size_t)>(actionModule?dlsym(actionModule,"ehr_source_unity_action_self_test"):nullptr);
    int32_t actionWords[10]={};int32_t actionStatus=actionProbe?actionProbe(actionWords,10):-1;
    const int32_t expectedAction[]={1,0,1,1,1,1,1,1,1,0};
    NSMutableArray *actionValues=[NSMutableArray array];
    for(size_t i=0;i<10;++i){[actionValues addObject:@(actionWords[i])];XCTAssertEqual(actionWords[i],expectedAction[i],@"action word %zu",i);}
    NSDictionary *actionProof=@{@"schema":@"ehr.full-source-action-ownership-proof.v1",@"status":@(actionStatus),
        @"words":actionValues,@"accountActionsPerformed":@NO,@"independentNativeUnityEvent":@YES};
    XCTAssertEqual(actionStatus,0,@"%@",actionProof);if(actionModule)dlclose(actionModule);
    NSData *actionData=[NSJSONSerialization dataWithJSONObject:actionProof options:NSJSONWritingPrettyPrinted error:nil];
    XCTAttachment *actionAttachment=[XCTAttachment attachmentWithData:actionData uniformTypeIdentifier:@"public.json"];
    actionAttachment.name=@"EHRSourceActionOwnershipProof.json";actionAttachment.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:actionAttachment];
#endif
#if EHR_EXERCISE_AUDIO
    NSMutableDictionary *audioProof=[@{@"schema":@"ehr.full-source-audio-proof.v1",@"startup":last,
        @"accountActionsPerformed":@NO,@"playbackVolume":@0} mutableCopy];
    void *module=nullptr;
    for(uint32_t i=0;i<_dyld_image_count();++i){const char *path=_dyld_get_image_name(i);
        if(path&&strstr(path,"/NativeSourceReuse.framework/NativeSourceReuse")){module=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);break;}}
    const char *audioProbes[]={"ehr_source_audio_data_probe_v1","ehr_source_muted_sound_probe_v1"};
    for(const char *name:audioProbes){
        int32_t words[16]={};auto probe=reinterpret_cast<int32_t(*)(int32_t *,size_t)>(module?dlsym(module,name):nullptr);
        int32_t result=probe?probe(words,16):-1;
        NSMutableArray *values=[NSMutableArray array];for(int32_t word:words)[values addObject:@(word)];
        audioProof[[NSString stringWithUTF8String:name]]=@{@"status":@(result),@"words":values};
        XCTAssertEqual(result,0,@"%@",audioProof);
        XCTAssertEqual(words[0],1,@"%@",audioProof);XCTAssertEqual(words[1],0);
    }
    if(module)dlclose(module);
    NSData *audioData=[NSJSONSerialization dataWithJSONObject:audioProof options:NSJSONWritingPrettyPrinted error:nil];
    NSLog(@"EHR_NATIVE_AUDIO_PROOF %@",[[NSString alloc] initWithData:audioData encoding:NSUTF8StringEncoding]);
    XCTAttachment *audioAttachment=[XCTAttachment attachmentWithData:audioData uniformTypeIdentifier:@"public.json"];
    audioAttachment.name=@"EHRSourceAudioProof.json";audioAttachment.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:audioAttachment];
#endif
#if EHR_EXERCISE_AUDIO_LOADER
    void *audioModule=nullptr;
    for(uint32_t i=0;i<_dyld_image_count();++i){const char *path=_dyld_get_image_name(i);
        if(path&&strstr(path,"/NativeSourceReuse.framework/NativeSourceReuse")){audioModule=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);break;}}
    auto loader=reinterpret_cast<int32_t(*)(int32_t *,size_t)>(audioModule?dlsym(audioModule,"ehr_source_ios_audio_loader_probe_v1"):nullptr);
    int32_t loaderWords[16]={};int32_t loaderStatus=loader?loader(loaderWords,16):-1;
    const int32_t expectedLoader[]={1,0,6,18,19,18,1,1,18,18,1,0,0,18,0,0};
    NSMutableArray *loaderValues=[NSMutableArray array];
    for(size_t i=0;i<16;++i){[loaderValues addObject:@(loaderWords[i])];XCTAssertEqual(loaderWords[i],expectedLoader[i],@"loader word %zu",i);}
    NSDictionary *loaderProof=@{@"schema":@"ehr.full-source-audio-loader-proof.v1",@"startup":last,
        @"status":@(loaderStatus),@"words":loaderValues,@"accountActionsPerformed":@NO,@"playbackPerformed":@NO};
    XCTAssertEqual(loaderStatus,0,@"%@",loaderProof);
    if(audioModule)dlclose(audioModule);
    NSData *loaderData=[NSJSONSerialization dataWithJSONObject:loaderProof options:NSJSONWritingPrettyPrinted error:nil];
    NSLog(@"EHR_NATIVE_AUDIO_LOADER_PROOF %@",[[NSString alloc] initWithData:loaderData encoding:NSUTF8StringEncoding]);
    XCTAttachment *loaderAttachment=[XCTAttachment attachmentWithData:loaderData uniformTypeIdentifier:@"public.json"];
    loaderAttachment.name=@"EHRSourceAudioLoaderProof.json";loaderAttachment.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:loaderAttachment];
#endif
#if EHR_EXERCISE_FAILURE_CLEANUP
    // Diagnostic copied host only: deliberately retire the successfully loaded
    // source, exercising the same native cleanup called on real load failure.
    NSDictionary *cleanup=nil;
    for(uint32_t i=0;i<_dyld_image_count();++i){
        const char *path=_dyld_get_image_name(i);
        if(!path||!strstr(path,"/EHRNativeHooks.dylib"))continue;
        void *handle=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);
        auto fn=reinterpret_cast<NSDictionary *(*)(void)>(handle?dlsym(handle,"EHRFullSourceFailureCleanup"):nullptr);
        cleanup=fn?fn():nil;if(handle)dlclose(handle);break;
    }
    XCTAssertTrue([cleanup[@"success"] boolValue],@"%@",cleanup);
    XCTAssertTrue([cleanup[@"targetsDeactivated"] boolValue]);
    XCTAssertTrue([cleanup[@"sourceTouchHidden"] boolValue]);
    XCTAssertTrue([cleanup[@"sourceStatesReleased"] boolValue]);
    XCTAssertTrue([cleanup[@"registrationSealed"] boolValue]);
    XCTAssertEqual([cleanup[@"activeSources"] unsignedLongLongValue],0ULL);
    XCTAssertEqual([cleanup[@"currentRoots"] unsignedLongLongValue],0ULL);
    XCTAssertEqual([cleanup[@"associationWeakRoots"] unsignedLongLongValue],0ULL);
    NSDictionary *cleanupProof=@{@"schema":@"ehr.full-source-failure-cleanup-proof.v1",@"cleanup":cleanup?:@{},
        @"startup":last,@"accountActionsPerformed":@NO,@"copiedDiagnosticHostOnly":@YES};
    NSData *cleanupData=[NSJSONSerialization dataWithJSONObject:cleanupProof options:NSJSONWritingPrettyPrinted error:nil];
    NSLog(@"EHR_NATIVE_FAILURE_CLEANUP %@",[[NSString alloc] initWithData:cleanupData encoding:NSUTF8StringEncoding]);
    XCTAttachment *cleanupAttachment=[XCTAttachment attachmentWithData:cleanupData uniformTypeIdentifier:@"public.json"];
    cleanupAttachment.name=@"EHRFullSourceFailureCleanupProof.json";cleanupAttachment.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:cleanupAttachment];
#endif
}
@end
