#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <thread>
#include <cstring>
#include "EHRRuntimePinnedAssociation.h"
namespace ehr_pinned {
EHRRuntimeStatus validate_engine_entry(const void *) { return EHR_RUNTIME_NOT_READY; }
}
static uint32_t recordedDomain;
static int32_t recordedCode;
static uint64_t recordedCount;
static uint64_t recordedRequests, recordedSuccesses, recordedErrors, recordedOverlaps;
static bool writerThrows;
void EHRRuntimeDiagnosticsRecordAuthCounters(uint64_t requestCount,uint64_t successCount,uint64_t errorCount,uint64_t overlapCount) {
    recordedRequests=requestCount; recordedSuccesses=successCount;
    recordedErrors=errorCount; recordedOverlaps=overlapCount;
}
void EHRRuntimeDiagnosticsRecordAuth(uint32_t domain, int32_t code, uint64_t count) {
    recordedDomain=domain; recordedCode=code; recordedCount=count;
    if(writerThrows) @throw [NSException exceptionWithName:@"OwnWriterFailure" reason:nil userInfo:nil];
}
#define EHR_APPLE_AUTH_OBSERVER_FIXTURE 1
#include "EHRAppleAuthDiagnostics.mm"

static uint32_t originalRequests, originalErrors, originalSuccesses, lastRequestID;
static id lastController, lastError, lastAuthorization;
@interface OwnAppleAuthFixture : NSObject
-(void)performAuthorizationRequestsForController:(id)controller withRequestId:(uint32_t)requestID;
-(void)authorizationController:(id)controller didCompleteWithAuthorization:(id)authorization;
-(void)authorizationController:(id)controller didCompleteWithError:(id)nativeError;
@end
@implementation OwnAppleAuthFixture
-(void)performAuthorizationRequestsForController:(id)controller withRequestId:(uint32_t)requestID {
    ++originalRequests; lastController=controller; lastRequestID=requestID;
}
-(void)authorizationController:(id)controller didCompleteWithAuthorization:(id)authorization {
    ++originalSuccesses; lastController=controller; lastAuthorization=authorization;
}
-(void)authorizationController:(id)controller didCompleteWithError:(id)nativeError {
    ++originalErrors; lastController=controller; lastError=nativeError;
}
@end
static IMP expected[3];
static bool fixturePin(IMP imp,uint64_t rva) {
    for(size_t i=0;i<3;++i) if(imp==expected[i]&&rva==entries[i].rva) return true;
    return false;
}
static bool rejectSecond(IMP imp,uint64_t rva) {
    return rva!=entries[1].rva&&fixturePin(imp,rva);
}
int main() { @autoreleasepool {
    bool pass=true; unsigned checks=0;
    auto check=[&](bool value){pass&=value;++checks;};
    Class klass=OwnAppleAuthFixture.class;
    for(size_t i=0;i<3;++i)expected[i]=method_getImplementation(class_getInstanceMethod(klass,sel_registerName(entries[i].selector)));
    check(EHRAppleAuthDiagnosticsInstallForFixture(klass,rejectSecond)==2);
    for(size_t i=0;i<3;++i)check(method_getImplementation(class_getInstanceMethod(klass,sel_registerName(entries[i].selector)))==expected[i]);
    int worker=0;
    std::thread thread([&]{worker=EHRAppleAuthDiagnosticsInstallForFixture(klass,fixturePin);});thread.join();check(worker==1);
    check(EHRAppleAuthDiagnosticsInstallForFixture(NSObject.class,fixturePin)==4);
    check(EHRAppleAuthDiagnosticsInstallForFixture(klass,fixturePin)==0);
    check(EHRAppleAuthDiagnosticsInstallForFixture(klass,fixturePin)==0);
    OwnAppleAuthFixture *manager=[OwnAppleAuthFixture new];
    id first=[NSObject new],second=[NSObject new],authorization=[NSObject new];
    [manager performAuthorizationRequestsForController:first withRequestId:41];
    check(originalRequests==1&&lastController==first&&lastRequestID==41);
    [manager performAuthorizationRequestsForController:second withRequestId:42];
    check(originalRequests==2&&lastController==second&&lastRequestID==42);
    check([EHRAppleAuthDiagnosticsCopyStatus()[@"overlapObservations"] unsignedLongLongValue]==1);
    check([EHRAppleAuthDiagnosticsCopyStatus()[@"activeObserved"] unsignedLongLongValue]==2);
    NSError *failure=[NSError errorWithDomain:@"com.apple.AuthenticationServices.AuthorizationError" code:1004 userInfo:@{NSLocalizedDescriptionKey:@"SECRET-CREDENTIAL-CANARY",@"Token":@"SECRET-TOKEN-CANARY"}];
    [manager authorizationController:first didCompleteWithError:failure];
    check(originalErrors==1&&lastError==failure&&lastController==first);
    check(recordedDomain==1&&recordedCode==1004&&recordedCount==1);
    [manager authorizationController:second didCompleteWithAuthorization:authorization];
    check(originalSuccesses==1&&lastAuthorization==authorization&&lastController==second);
    check([EHRAppleAuthDiagnosticsCopyStatus()[@"activeObserved"] unsignedLongLongValue]==0);
    failure=[NSError errorWithDomain:@"SECRET-UNKNOWN-DOMAIN" code:-3200 userInfo:nil];
    [manager authorizationController:first didCompleteWithError:failure];
    check(recordedDomain==0&&recordedCode==-3200&&recordedCount==2&&lastError==failure&&originalErrors==2);
    [manager authorizationController:first didCompleteWithError:nil];
    check(recordedDomain==0&&recordedCode==0&&recordedCount==3&&lastError==nil&&originalErrors==3);
    failure=[NSError errorWithDomain:NSOSStatusErrorDomain code:NSIntegerMax userInfo:nil];
    [manager authorizationController:first didCompleteWithError:failure];
    check(recordedDomain==2&&recordedCode==0&&recordedCount==4&&originalErrors==4);
    writerThrows=true;
    [manager authorizationController:first didCompleteWithError:failure];
    check(originalErrors==5&&lastError==failure);
    check(recordedRequests==2&&recordedSuccesses==1&&recordedErrors==5&&recordedOverlaps==1);
    NSDictionary *snapshot=EHRAppleAuthDiagnosticsCopyStatus();
    check([snapshot[@"observerFaults"] unsignedLongLongValue]==1);
    check([snapshot[@"authSuppressed"] unsignedLongLongValue]==0);
    NSData *json=[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
    NSString *text=[[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding];
    check(![text containsString:@"SECRET"]);
    printf("{\"pass\":%s,\"checks\":%u,\"originalRequests\":%u,\"originalErrors\":%u,\"originalSuccesses\":%u,\"gameAuthCalls\":0,\"networkRequests\":0,\"suppressed\":0}\n",pass?"true":"false",checks,originalRequests,originalErrors,originalSuccesses);
    return pass?0:1;
} }
