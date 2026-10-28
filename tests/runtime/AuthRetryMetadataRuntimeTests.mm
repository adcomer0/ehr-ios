#import <XCTest/XCTest.h>
#include <dlfcn.h>
#include <thread>
#include "native/EHRRuntimeGateway.h"
#include "AuthRetryMetadataProof.inc"

@interface NativeRuntimeTests : XCTestCase
@end
@implementation NativeRuntimeTests
- (void)testSignedCandidateLoadsActualRuntime {
    XCTAssertTrue(NSThread.isMainThread);
    XCTAssertEqualObjects(NSBundle.mainBundle.bundleIdentifier,@"__EHR_TEST_APP_BUNDLE_ID__");
    XCTAssertTrue([NSBundle.mainBundle.infoDictionary[@"EHRAuthRetryGuardCompiled"] boolValue]);
    XCTAssertFalse([NSBundle.mainBundle.infoDictionary[@"EHRAuthRetryGuardEnabled"] boolValue]);
    XCTAssertFalse([NSBundle.mainBundle.infoDictionary[@"EHRAuthRetryGuardActivationRequested"] boolValue]);
    XCTAssertFalse([NSBundle.mainBundle.infoDictionary[@"EHRFullSourceAutoLoad"] boolValue]);
    auto initialize=reinterpret_cast<int32_t(*)(void)>(dlsym(RTLD_DEFAULT,"ehr_runtime_initialize"));
    auto prepare=reinterpret_cast<int32_t(*)(void)>(dlsym(RTLD_DEFAULT,"EHRAuthRetryGuardPrepare"));
    XCTAssertTrue(initialize&&prepare);
    if(!initialize||!prepare)return;
    XCTestExpectation *ready=[self expectationWithDescription:@"Actual IL2CPP metadata ready"];
    __block bool fulfilled=false;
    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),250*NSEC_PER_MSEC,25*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{
        if(!fulfilled&&initialize()==EHR_RUNTIME_OK){fulfilled=true;dispatch_source_cancel(timer);[ready fulfill];}
    });
    dispatch_resume(timer);[self waitForExpectations:@[ready] timeout:45];dispatch_source_cancel(timer);
    if(!fulfilled)return;
    int32_t workerStatus=EHR_RUNTIME_OK;
    std::thread worker([&]{workerStatus=prepare();});worker.join();
    XCTAssertEqual(workerStatus,EHR_RUNTIME_WRONG_THREAD);
    NSDictionary *first=EHRAuthRetryMetadataProof();
    NSDictionary *second=EHRAuthRetryMetadataProof();
    XCTAssertTrue([first[@"pass"] boolValue],@"%@",first);
    XCTAssertTrue([second[@"pass"] boolValue],@"%@",second);
    NSDictionary *proof=@{@"schema":@"ehr.auth-retry-metadata-proof.v1",@"first":first,@"second":second,
        @"workerStatus":@(workerStatus),@"guardActivationAttempted":@NO,
        @"MainLoadExecutedByTest":@NO,@"nativeAuthTargetsInvokedByTest":@0,
        @"accountOperationsInitiatedByTest":@0,@"authRequestsInitiatedByTest":@0};
    NSData *data=[NSJSONSerialization dataWithJSONObject:proof options:NSJSONWritingPrettyPrinted error:nil];
    XCTAssertNotNil(data);
    XCTAttachment *attachment=[XCTAttachment attachmentWithData:data uniformTypeIdentifier:@"public.json"];
    attachment.name=@"EHRAuthRetryMetadataProof.json";attachment.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:attachment];
}
@end
