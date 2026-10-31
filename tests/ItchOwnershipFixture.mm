// Exact ownership helper with an owned NSURLProtocol transport. Every URL is
// intercepted in-process. No credential, account, device, DNS or game is used.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../native/EHRItchOwnership.h"
#import "../native/EHRItchOwnership.mm"

namespace {
NSUInteger checks=0,requests=0,completionCalls=0;NSMutableArray<NSString *> *failures;
NSArray<NSDictionary *> *script;NSMutableArray<NSURLRequest *> *observed;
NSDictionary<NSString *,NSNumber *> *lastDiagnostics;
bool completionMain=true,configurationSafe=true;EHRItchOwnershipStatus result=EHRItchOwnershipCancelled;int32_t resultHTTP=0;
void Check(bool okay,NSString *name){++checks;if(!okay)[failures addObject:name];}
NSData *Bytes(NSString *text){return [text dataUsingEncoding:NSUTF8StringEncoding];}
NSDictionary *Row(id game,NSNumber *identity){return @{@"id":identity,@"game_id":game};}
NSData *Page(NSArray *rows,NSUInteger page=1){return [NSJSONSerialization dataWithJSONObject:@{@"page":@(page),@"per_page":@10,@"owned_keys":rows} options:0 error:nil];}
NSDictionary *Reply(NSData *body,NSInteger status=200,NSString *mime=@"application/json"){return @{@"body":body?:NSData.data,@"status":@(status),@"mime":mime};}
void DrainUntil(bool(^predicate)(void)){NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];while(!predicate()&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];Check(predicate(),@"owned_async_completion_reached");}
}

@interface EHROwnedOwnershipProtocol:NSURLProtocol
@end
@implementation EHROwnedOwnershipProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {(void)request;return YES;}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {return request;}
- (void)startLoading {
    @synchronized(EHROwnedOwnershipProtocol.class){
        ++requests;[observed addObject:self.request];
        if(requests>script.count){[self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]];return;}
        NSDictionary *step=script[requests-1];
        if([step[@"hang"] boolValue])return;
        if([step[@"network"] boolValue]){[self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];return;}
        NSData *body=step[@"body"];NSMutableDictionary *headers=[@{@"Content-Type":step[@"mime"]?:@"application/json"} mutableCopy];
        if(step[@"length"])headers[@"Content-Length"]=[step[@"length"] stringValue];
        NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:[step[@"status"] integerValue] HTTPVersion:@"HTTP/1.1" headerFields:headers];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        NSUInteger chunk=step[@"chunk"]?[step[@"chunk"] unsignedIntegerValue]:MAX((NSUInteger)1,body.length);
        for(NSUInteger offset=0;offset<body.length;offset+=chunk)[self.client URLProtocol:self didLoadData:[body subdataWithRange:NSMakeRange(offset,MIN(chunk,body.length-offset))]];
        [self.client URLProtocolDidFinishLoading:self];
    }
}
- (void)stopLoading {}
@end

@interface NSURLSession(EHROwnedOwnershipFixture)
+ (NSURLSession *)ownedSessionWithConfiguration:(NSURLSessionConfiguration *)config delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue;
@end
@implementation NSURLSession(EHROwnedOwnershipFixture)
+ (NSURLSession *)ownedSessionWithConfiguration:(NSURLSessionConfiguration *)config delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue {
    configurationSafe=configurationSafe&&!config.URLCache&&!config.URLCredentialStorage&&!config.HTTPCookieStorage&&!config.HTTPShouldSetCookies&&config.requestCachePolicy==NSURLRequestReloadIgnoringLocalCacheData&&config.timeoutIntervalForResource<=20&&config.timeoutIntervalForRequest<=10&&queue.maxConcurrentOperationCount==1;
    config.protocolClasses=@[EHROwnedOwnershipProtocol.class];
    return [self ownedSessionWithConfiguration:config delegate:delegate delegateQueue:queue];
}
@end

namespace {
void Reset(NSArray<NSDictionary *> *steps){script=steps;requests=completionCalls=0;observed=[NSMutableArray new];result=EHRItchOwnershipCancelled;resultHTTP=0;completionMain=true;configurationSafe=true;}
EHRItchOwnershipCheck *Begin(NSData *key){return EHRItchOwnershipBegin(key,^(EHRItchOwnershipStatus status,int32_t http){++completionCalls;completionMain=completionMain&&NSThread.isMainThread;result=status;resultHTTP=http;});}
void Expect(NSArray<NSDictionary *> *steps,EHRItchOwnershipStatus expected,NSUInteger requestCount,int32_t http=200){
    Reset(steps);NSMutableData *key=[Bytes(@"OWNED-FAKE-KEY-NOT-A-CREDENTIAL") mutableCopy];EHRItchOwnershipCheck *check=Begin(key);wipe(key);
    DrainUntil(^bool{return completionCalls>0;});Check(result==expected,@"exact_numeric_decision");Check(resultHTTP==http,@"exact_bounded_http_status");Check(requests==requestCount,@"bounded_request_count");Check(completionCalls==1&&completionMain,@"once_on_main");Check(configurationSafe,@"ephemeral_cookie_cache_credential_storage_disabled");
    for(NSUInteger i=0;i<observed.count;++i){NSURLRequest *request=observed[i];Check([request.URL.absoluteString isEqualToString:pageURL(i+1).absoluteString],@"fixed_host_path_filter_page_and_size");Check([request.HTTPMethod isEqualToString:@"GET"]&&!request.HTTPBody,@"read_only_get");Check([[request valueForHTTPHeaderField:@"Authorization"] isEqualToString:@"Bearer OWNED-FAKE-KEY-NOT-A-CREDENTIAL"],@"borrowed_key_copied_synchronously");}
    NSDictionary<NSString *,NSNumber *> *diagnostics=EHRItchOwnershipCopyDiagnostics(check);lastDiagnostics=diagnostics;
    Check(diagnostics.count==16,@"structural_diagnostics_fixed_field_count");
    for(NSString *name in diagnostics){id value=diagnostics[name];Check([value isKindOfClass:NSNumber.class],@"structural_diagnostics_numbers_only");Check([value longLongValue]>=-1000&&[value longLongValue]<=(int64_t)totalLimit,@"structural_diagnostics_bounded_numbers");}
    Check([diagnostics[@"responseBytes"] unsignedIntegerValue]<=bodyLimit&&[diagnostics[@"totalBytes"] unsignedIntegerValue]<=totalLimit&&[diagnostics[@"requestedPage"] unsignedIntegerValue]<=pageLimit+1,@"response_size_and_requested_page_diagnostics_bounded");
    Check([diagnostics[@"returnedPage"] longLongValue]>=-1000&&[diagnostics[@"returnedPage"] longLongValue]<=1000&&[diagnostics[@"returnedPerPage"] longLongValue]>=-1000&&[diagnostics[@"returnedPerPage"] longLongValue]<=1000,@"returned_pagination_values_clamped");
    Check(![[diagnostics description] containsString:@"OWNED-FAKE"]&&![[diagnostics description] containsString:@"game_id"]&&![[diagnostics description] containsString:@"https://"],@"structural_diagnostics_do_not_include_response_content_or_credentials");
    [check cancel];DrainUntil(^bool{return completionCalls==1;});Check(completionCalls==1,@"cancel_after_completion_idempotent");
}
}

int main(){@autoreleasepool{
    failures=[NSMutableArray new];method_exchangeImplementations(class_getClassMethod(NSURLSession.class,@selector(sessionWithConfiguration:delegate:delegateQueue:)),class_getClassMethod(NSURLSession.class,@selector(ownedSessionWithConfiguration:delegate:delegateQueue:)));
    Expect(@[Reply(Page(@[Row(@257677,@1)]))],EHRItchOwnershipVerified,1);
    Expect(@[Reply(Page(@[Row(@257677,@1),Row(@257677,@2)]))],EHRItchOwnershipVerified,1);
    Expect(@[Reply(Page(@[]))],EHRItchOwnershipNoEntitlement,1);
    // A nonempty short page is never exhaustion. Revoked keys require another
    // page; a later valid claim can still establish entitlement.
    NSDictionary *revoked=@{@"id":@1,@"game_id":@257677,@"revoked":@YES};
    Expect(@[Reply(Page(@[revoked])),Reply(Page(@[Row(@257677,@2)],2))],EHRItchOwnershipVerified,2);
    Expect(@[Reply(Page(@[revoked])),Reply(Page(@[],2))],EHRItchOwnershipNoEntitlement,2);
    NSMutableArray *many=[NSMutableArray new];for(NSUInteger i=1;i<=pageLimit;++i)[many addObject:Reply(Page(@[@{@"id":@(i),@"game_id":@257677,@"revoked":@YES}],i))];
    Expect(many,EHRItchOwnershipLimitExceeded,pageLimit);
    for(id game in @[@"257677",@YES,@257677.5,@(-1),@257678,NSNull.null])Expect(@[Reply(Page(@[Row(game,@1)]))],EHRItchOwnershipMalformedResponse,1);
    for(id identity in @[@"1",@YES,@0,@(-1),@1.25,NSNull.null])Expect(@[Reply(Page(@[Row(@257677,identity)]))],EHRItchOwnershipMalformedResponse,1);
    for(NSData *body in @[Bytes(@"{broken"),Bytes(@"[]"),Bytes(@"{}"),Bytes(@"{\"page\":true,\"per_page\":10,\"owned_keys\":[]}"),Bytes(@"{\"page\":1,\"per_page\":10,\"owned_keys\":[{}]}"),Page(@[Row(@257677,@1),Row(@257677,@1)]),Page(@[Row(@257677,@1)],2)])Expect(@[Reply(body)],EHRItchOwnershipMalformedResponse,1);
    Expect(@[Reply(Page(@[revoked])),Reply(Page(@[revoked],2))],EHRItchOwnershipMalformedResponse,2);
    Expect(@[Reply(Bytes(@"{\"errors\":[\"fixture error\"]}"))],EHRItchOwnershipServerRejected,1);
    Expect(@[Reply(Page(@[]),200,@"text/html")],EHRItchOwnershipMalformedResponse,1);
    for(NSNumber *http in @[@401,@403,@404,@429,@500,@503])Expect(@[Reply(NSData.data,http.integerValue)],http.integerValue==401?EHRItchOwnershipInvalidCredential:http.integerValue==403?EHRItchOwnershipInsufficientScope:http.integerValue==404?EHRItchOwnershipServerRejected:EHRItchOwnershipServiceUnavailable,1,http.intValue);
    Expect(@[@{@"network":@YES}],EHRItchOwnershipNetworkUnavailable,1,0);
    // Exact structural failures diagnose HTTP-200 shape differences without
    // changing which responses establish ownership or exposing response text.
    Expect(@[Reply(Bytes(@"{\"owned_keys\":[]}"))],EHRItchOwnershipMalformedResponse,1);
    Check([lastDiagnostics[@"parserStage"] intValue]==PageTypeInvalid&&[lastDiagnostics[@"rootKind"] intValue]==2&&[lastDiagnostics[@"ownedKeysKind"] intValue]==3&&[lastDiagnostics[@"ownedKeysCount"] intValue]==0&&[lastDiagnostics[@"pageKind"] intValue]==0&&[lastDiagnostics[@"perPageKind"] intValue]==0,@"missing_pagination_and_empty_array_distinguished");
    Check([lastDiagnostics[@"httpTyped"] boolValue]&&[lastDiagnostics[@"urlMatched"] boolValue]&&[lastDiagnostics[@"mimeJSON"] boolValue]&&[lastDiagnostics[@"lengthOK"] boolValue]&&[lastDiagnostics[@"responseBytes"] intValue]==17&&[lastDiagnostics[@"requestedPage"] intValue]==1,@"successful_header_checks_and_original_page_survive_body_wipe");
    Expect(@[Reply(Bytes(@"{\"page\":1,\"per_page\":10,\"owned_keys\":{}}"))],EHRItchOwnershipNoEntitlement,1);Check([lastDiagnostics[@"parserStage"] intValue]==Empty&&[lastDiagnostics[@"ownedKeysKind"] intValue]==2&&[lastDiagnostics[@"ownedKeysCount"] intValue]==0,@"observed_empty_object_owned_keys_is_negative_only");
    // Empty-object compatibility applies only to a fully valid empty page.
    // Record-shaped objects and keyed maps must never become positive proof.
    for(id rejected in @[@{@"id":@1,@"game_id":@257677},@{@"0":Row(@257677,@1)},@{@"claim":Row(@257677,@1)},@{@"id":@1},@{@"game_id":@257677},@{@"nested":@{}},NSNull.null,@YES,@NO,@0,@1,@"",@"[]",@"{}"]){
        NSData *body=[NSJSONSerialization dataWithJSONObject:@{@"page":@1,@"per_page":@10,@"owned_keys":rejected} options:0 error:nil];
        Expect(@[Reply(body)],EHRItchOwnershipMalformedResponse,1);Check([lastDiagnostics[@"parserStage"] intValue]==OwnedKeysTypeInvalid,@"nonempty_objects_and_scalars_cannot_verify_or_end_pagination");
    }
    for(NSData *body in @[Bytes(@"{\"page\":1,\"per_page\":10}"),Bytes(@"{\"owned_keys\":{}}"),Bytes(@"{\"page\":1,\"owned_keys\":{}}"),Bytes(@"{\"page\":2,\"per_page\":10,\"owned_keys\":{}}"),Bytes(@"{\"page\":\"1\",\"per_page\":10,\"owned_keys\":{}}"),Bytes(@"{\"page\":true,\"per_page\":10,\"owned_keys\":{}}"),Bytes(@"{\"page\":1.0,\"per_page\":10,\"owned_keys\":{}}"),Bytes(@"{\"page\":1,\"per_page\":11,\"owned_keys\":{}}"),Bytes(@"{\"page\":1,\"per_page\":\"10\",\"owned_keys\":{}}"),Bytes(@"{\"page\":1,\"per_page\":true,\"owned_keys\":{}}")]){
        Expect(@[Reply(body)],EHRItchOwnershipMalformedResponse,1);Check([lastDiagnostics[@"parserStage"] intValue]!=Empty,@"empty_object_does_not_relax_missing_or_wrong_pagination");
    }
    for(NSString *envelope in @[@"errors",@"error"]){
        NSData *body=[NSJSONSerialization dataWithJSONObject:@{@"page":@1,@"per_page":@10,@"owned_keys":@{},envelope:@[]} options:0 error:nil];
        Expect(@[Reply(body)],EHRItchOwnershipServerRejected,1);Check([lastDiagnostics[@"parserStage"] intValue]==ErrorEnvelope,@"error_envelope_precedes_empty_object_compatibility");
    }
    Expect(@[Reply(Page(@[revoked])),Reply(Bytes(@"{\"page\":2,\"per_page\":10,\"owned_keys\":{}}"))],EHRItchOwnershipNoEntitlement,2);Check([lastDiagnostics[@"parserStage"] intValue]==Empty&&[lastDiagnostics[@"requestedPage"] intValue]==2&&[lastDiagnostics[@"ownedKeysKind"] intValue]==2,@"later_empty_object_terminates_revoked_key_pagination_negatively");
    Expect(@[Reply(Page(@[revoked])),Reply(Bytes(@"{\"page\":1,\"per_page\":10,\"owned_keys\":{}}"))],EHRItchOwnershipMalformedResponse,2);Check([lastDiagnostics[@"parserStage"] intValue]==PageValueMismatch,@"later_empty_object_requires_exact_requested_page");
    Expect(@[Reply(Page(@[Row(@257677,@1)]))],EHRItchOwnershipVerified,1);Check([lastDiagnostics[@"parserStage"] intValue]==Verified&&[lastDiagnostics[@"ownedKeysKind"] intValue]==3,@"positive_proof_still_requires_strict_matching_array_record");
    Expect(@[Reply(Bytes(@"{\"page\":1,\"owned_keys\":[]}"))],EHRItchOwnershipMalformedResponse,1);Check([lastDiagnostics[@"parserStage"] intValue]==PerPageTypeInvalid&&[lastDiagnostics[@"returnedPage"] intValue]==1&&[lastDiagnostics[@"perPageKind"] intValue]==0,@"missing_per_page_distinguished");
    Expect(@[Reply(Bytes(@"{\"page\":true,\"per_page\":10,\"owned_keys\":[]}"))],EHRItchOwnershipMalformedResponse,1);Check([lastDiagnostics[@"parserStage"] intValue]==PageTypeInvalid&&[lastDiagnostics[@"pageKind"] intValue]==6&&[lastDiagnostics[@"returnedPage"] intValue]==0,@"boolean_pagination_is_not_reported_as_integer");
    Expect(@[Reply(Bytes(@"{\"page\":50000,\"per_page\":10,\"owned_keys\":[]}"))],EHRItchOwnershipMalformedResponse,1);Check([lastDiagnostics[@"parserStage"] intValue]==PageValueMismatch&&[lastDiagnostics[@"returnedPage"] intValue]==1000,@"oversized_pagination_values_clamped_and_rejected");
    Expect(@[Reply(Bytes(@"{\"page\":-2,\"per_page\":10,\"owned_keys\":[]}"))],EHRItchOwnershipMalformedResponse,1);Check([lastDiagnostics[@"parserStage"] intValue]==PageTypeInvalid&&[lastDiagnostics[@"pageKind"] intValue]==4&&[lastDiagnostics[@"returnedPage"] intValue]==-2,@"negative_integer_pagination_distinguished");
    Expect(@[Reply(Bytes(@"{\"page\":1,\"per_page\":11,\"owned_keys\":[]}"))],EHRItchOwnershipMalformedResponse,1);Check([lastDiagnostics[@"parserStage"] intValue]==PerPageValueMismatch&&[lastDiagnostics[@"returnedPerPage"] intValue]==11,@"per_page_value_mismatch_distinguished");
    Expect(@[Reply(Bytes(@"{\"x\":undefined}"))],EHRItchOwnershipMalformedResponse,1);Check([lastDiagnostics[@"parserStage"] intValue]==JSONDecodeFailed&&[lastDiagnostics[@"rootKind"] intValue]==0,@"json_decode_failure_has_no_root_value");
    Expect(@[Reply(Bytes(@"null"))],EHRItchOwnershipMalformedResponse,1);Check([lastDiagnostics[@"parserStage"] intValue]==RootNotObject&&[lastDiagnostics[@"rootKind"] intValue]==1,@"literal_null_distinguished_from_decode_failure");
    Expect(@[Reply(Page(@[]),200,@"text/html")],EHRItchOwnershipMalformedResponse,1);Check([lastDiagnostics[@"parserStage"] intValue]==HeaderMIMERejected&&[lastDiagnostics[@"mimeJSON"] intValue]==0&&[lastDiagnostics[@"rootKind"] intValue]==0,@"header_mime_failure_distinguished_before_parsing");
    Expect(@[Reply(Page(@[revoked])),Reply(Bytes(@"{\"owned_keys\":[]}"))],EHRItchOwnershipMalformedResponse,2);Check([lastDiagnostics[@"requestedPage"] intValue]==2&&[lastDiagnostics[@"pageKind"] intValue]==0&&[lastDiagnostics[@"returnedPage"] intValue]==0&&[lastDiagnostics[@"ownedKeysCount"] intValue]==0,@"next_page_resets_prior_header_and_pagination_structure");
    Check([boundedPageValue(@(UINT64_MAX)) intValue]==1000,@"large_unsigned_page_diagnostic_does_not_wrap_negative");
    NSMutableData *large=[NSMutableData dataWithLength:bodyLimit+1];Expect(@[Reply(large)],EHRItchOwnershipLimitExceeded,1);
    Expect(@[@{@"body":NSData.data,@"status":@200,@"mime":@"application/json",@"length":@(bodyLimit+1)}],EHRItchOwnershipLimitExceeded,1);
    NSMutableString *deep=[NSMutableString new];for(int i=0;i<40;++i)[deep appendString:@"["];for(int i=0;i<40;++i)[deep appendString:@"]"];Expect(@[Reply(Bytes(deep))],EHRItchOwnershipMalformedResponse,1);
    for(NSData *bad in @[NSData.data,Bytes(@"contains space"),Bytes(@"line\nbreak"),[NSData dataWithBytes:"\0" length:1],[NSMutableData dataWithLength:keyLimit+1]]){
        Reset(@[]);EHRItchOwnershipCheck *check=Begin(bad);Check(completionCalls==0,@"invalid_input_still_completes_asynchronously");DrainUntil(^bool{return completionCalls>0;});Check(result==EHRItchOwnershipBadCredentialFormat&&requests==0&&completionCalls==1&&completionMain,@"invalid_key_never_reaches_transport");[check cancel];
    }
    Reset(@[]);EHRItchOwnershipCheck *cancelled=Begin(Bytes(@"OWNED-FAKE-CANCEL"));[cancelled cancel];[cancelled cancel];DrainUntil(^bool{return completionCalls>0;});Check(result==EHRItchOwnershipCancelled&&requests==0&&completionCalls==1&&completionMain,@"cancel_before_start_never_transmits_once_on_main");
    Reset(@[]);EHRItchOwnershipCheck *redirect=[[EHRItchOwnershipCheck alloc] initWithKey:Bytes(@"OWNED-FAKE-REDIRECT") completion:^(EHRItchOwnershipStatus status,int32_t http){(void)http;++completionCalls;result=status;}];
    __block NSURLRequest *redirected=[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.invalid/"]];
    [redirect URLSession:(NSURLSession *)[NSObject new] task:(NSURLSessionTask *)[NSObject new] willPerformHTTPRedirection:[[NSHTTPURLResponse alloc] initWithURL:redirected.URL statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{}] newRequest:redirected completionHandler:^(NSURLRequest *request){redirected=request;}];DrainUntil(^bool{return completionCalls>0;});Check(!redirected&&result==EHRItchOwnershipRedirectRejected&&requests==0,@"all_redirects_rejected_without_followup");
    Reset(@[]);EHRItchOwnershipCheck *expired=[[EHRItchOwnershipCheck alloc] initWithKey:Bytes(@"OWNED-FAKE-DEADLINE") completion:^(EHRItchOwnershipStatus status,int32_t http){(void)http;++completionCalls;result=status;completionMain=NSThread.isMainThread;}];expired.deadline=0;expired.body=[Page(@[Row(@257677,@1)]) mutableCopy];NSMutableData *expiredKey=expired.key,*expiredBody=expired.body;
    [expired URLSession:(NSURLSession *)[NSObject new] task:(NSURLSessionTask *)[NSObject new] didCompleteWithError:nil];DrainUntil(^bool{return completionCalls>0;});Check(result==EHRItchOwnershipNetworkUnavailable&&completionCalls==1&&completionMain&&expiredKey.length==0&&expiredBody.length==0,@"expired_delegate_cannot_verify_before_delayed_main_watchdog");
    Reset(@[@{@"hang":@YES}]);EHRItchOwnershipCheck *inflight=Begin(Bytes(@"OWNED-FAKE-INFLIGHT"));DrainUntil(^bool{return requests>0;});NSMutableData *inflightKey=inflight.key;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[inflight cancel];[inflight cancel];});DrainUntil(^bool{return completionCalls>0;});Check(result==EHRItchOwnershipCancelled&&completionCalls==1&&completionMain&&inflightKey.length==0,@"worker_cancel_inflight_wipes_key_and_delivers_once_on_main");
    Reset(@[]);EHRItchOwnershipCheck *bytesBound=[[EHRItchOwnershipCheck alloc] initWithKey:Bytes(@"OWNED-FAKE-BYTES") completion:^(EHRItchOwnershipStatus status,int32_t http){(void)http;++completionCalls;result=status;}];bytesBound.body=[NSMutableData data];bytesBound.totalBytes=totalLimit;
    [bytesBound URLSession:(NSURLSession *)[NSObject new] dataTask:(NSURLSessionDataTask *)[NSObject new] didReceiveData:Bytes(@"x")];DrainUntil(^bool{return completionCalls>0;});Check(result==EHRItchOwnershipLimitExceeded&&completionCalls==1&&bytesBound.body==nil,@"total_response_bound_applies_before_append_or_parse");
    NSDictionary *proof=@{@"schema":@"ehr.itch-ownership-owned-proof.v1",@"success":@(failures.count==0),@"checks":@(checks),@"failures":failures,@"actualHelperCompiled":@YES,@"transportInterceptedInProcess":@YES,@"networkRequests":@0,@"keychainOperations":@0,@"gameCalls":@0,@"accountActions":@0,@"actualCredentialsRead":@0};
    NSData *output=[NSJSONSerialization dataWithJSONObject:proof options:NSJSONWritingSortedKeys error:nil];puts([[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding].UTF8String);return failures.count?1:0;
}}
