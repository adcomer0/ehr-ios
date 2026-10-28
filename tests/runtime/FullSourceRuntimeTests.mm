#import <XCTest/XCTest.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <cstdint>
#include <cstring>

namespace {
void *lookup(const char *name) {
    for (uint32_t i=0;i<_dyld_image_count();++i) {
        const char *path=_dyld_get_image_name(i);
        if (!path || (!strstr(path,"/EHRNativeHooks.dylib") &&
                      !strstr(path,"/NativeSourceReuse.framework/NativeSourceReuse"))) continue;
        void *handle=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);
        void *value=handle?dlsym(handle,name):nullptr;
        if(handle)dlclose(handle);
        if(value)return value;
    }
    return nullptr;
}
NSDictionary *operation(const char *name) {
    NSLog(@"EHR_FULL_SOURCE_PHASE %s",name);
    auto fn=reinterpret_cast<NSDictionary *(*)(void)>(lookup(name));
    return fn?fn():@{@"missingExport":[NSString stringWithUTF8String:name]};
}
}

@interface NativeRuntimeTests : XCTestCase
@end
@implementation NativeRuntimeTests
- (void)testSignedCandidateLoadsActualRuntime {
    XCTAssertEqualObjects(NSBundle.mainBundle.bundleIdentifier,@"__EHR_TEST_APP_BUNDLE_ID__");
    XCTAssertFalse([NSBundle.mainBundle.infoDictionary[@"EHRFullSourceAutoLoad"] boolValue]);
    XCTestExpectation *ready=[self expectationWithDescription:@"Actual game metadata ready"];
    __block bool fulfilled=false;
    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),250*NSEC_PER_MSEC,25*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{
        auto snapshot=reinterpret_cast<NSDictionary *(*)(void)>(lookup("EHRLiveBridgeCopySnapshot"));
        NSDictionary *value=snapshot?snapshot():nil;
        if(!fulfilled && [value[@"status"] isEqual:@"live_sample"] && [value[@"runtime"][@"gameAssemblyFound"] boolValue]) {
            fulfilled=true;dispatch_source_cancel(timer);[ready fulfill];
        }
    });
    dispatch_resume(timer);[self waitForExpectations:@[ready] timeout:45];dispatch_source_cancel(timer);
    if(!fulfilled)return;
    NSDictionary *bound=operation("EHRFullSourceBindRuntime");
    XCTAssertTrue([bound[@"bindingsReady"] boolValue],@"%@",bound);
    XCTAssertEqual([bound[@"readyFlags"] unsignedIntValue],63u);
    if(![bound[@"bindingsReady"] boolValue])return;
    NSDictionary *boxed=operation("ehr_native_patch_value_box_selftest");
    XCTAssertTrue([boxed[@"pass"] boolValue],@"%@",boxed);
    NSLog(@"EHR_FULL_SOURCE_PHASE pure_json");
    uint32_t json[10]={};
    auto jsonTest=reinterpret_cast<int32_t(*)(uint32_t *,size_t)>(lookup("ehr_source_json_self_test_v1"));
    int32_t jsonStatus=jsonTest?jsonTest(json,10):-1;
    XCTAssertEqual(jsonStatus,0);
    NSMutableArray *jsonWords=[NSMutableArray array];for(uint32_t word:json){[jsonWords addObject:@(word)];XCTAssertEqual(word,1u);}
    NSLog(@"EHR_FULL_SOURCE_PHASE source_unity_actions");
    int32_t actions[10]={};
    auto actionsTest=reinterpret_cast<int32_t(*)(int32_t *,size_t)>(lookup("ehr_source_unity_action_self_test"));
    int32_t actionsStatus=actionsTest?actionsTest(actions,10):-1;
    XCTAssertEqual(actionsStatus,0);
    NSMutableArray *actionWords=[NSMutableArray array];
    for(size_t i=0;i<10;++i){[actionWords addObject:@(actions[i])];XCTAssertEqual(actions[i],i==1||i==9?0:1);}
    NSLog(@"EHR_FULL_SOURCE_PHASE production_coroutines");
    int32_t coroutine[16]={};
    auto coroutineTest=reinterpret_cast<int32_t(*)(int32_t *,size_t)>(lookup("ehr_source_coroutines_self_test"));
    int32_t coroutineStatus=coroutineTest?coroutineTest(coroutine,16):-1;
    XCTAssertEqual(coroutineStatus,0);
    NSMutableArray *coroutineWords=[NSMutableArray array];
    for(size_t i=0;i<16;++i){[coroutineWords addObject:@(coroutine[i])];XCTAssertEqual(coroutine[i],i==1||i==15?0:1);}
    NSDictionary *prepared=operation("EHRFullSourcePrepareApplication");
    NSDictionary *app=prepared[@"application"];
    XCTAssertEqual([prepared[@"status"] intValue],0,@"%@",prepared);
    XCTAssertEqual([app[@"state"] intValue],1,@"%@",prepared);
    XCTAssertEqual([app[@"candidates"] unsignedIntValue],298u);
    XCTAssertEqual([app[@"unavailableTargets"] unsignedIntValue],0u);
    XCTAssertEqual([app[@"activeBindings"] unsignedIntValue],0u);
    XCTAssertEqual([app[@"loadAttempts"] unsignedIntValue],0u);
    XCTAssertEqual([app[@"dynamicCodeFlags"] unsignedIntValue],0u);
    XCTAssertEqual([app[@"optionsLoaded"] unsignedIntValue],0u);
    XCTAssertEqual([app[@"optionCount"] unsignedIntValue],0u);
    NSDictionary *proof=@{@"schema":@"ehr.full-source-runtime-proof.v1",@"scope":@"Full iOS source image production tables and passive installed-target validation",
        @"bound":bound,@"nativeReferenceValueBox":boxed,@"jsonStatus":@(jsonStatus),@"jsonProof":jsonWords,
        @"sourceActionStatus":@(actionsStatus),@"sourceActionProof":actionWords,
        @"coroutineStatus":@(coroutineStatus),@"coroutineProof":coroutineWords,@"prepared":prepared,
        @"MainLoadExecuted":@NO,@"accountActionsPerformed":@NO,@"multiplayerVerified":@NO};
    NSData *data=[NSJSONSerialization dataWithJSONObject:proof options:NSJSONWritingPrettyPrinted error:nil];
    NSLog(@"EHR_NATIVE_RUNTIME_TEST %@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    XCTAttachment *attachment=[XCTAttachment attachmentWithData:data uniformTypeIdentifier:@"public.json"];
    attachment.name=@"EHRNativeXCTestProof.json";attachment.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:attachment];
}
@end
