#import "EHRItchOwnership.h"
#import <Security/SecProtocolOptions.h>
#include <cstring>

namespace {
// Public Innersloth listing https://innersloth.itch.io/among-us embeds id257677.
// Contract: https://itch.io/docs/api/serverside#profileowned
constexpr uint64_t gameID=257677;
constexpr NSUInteger keyLimit=8192,bodyLimit=65536,pageSize=10,pageLimit=4,totalLimit=bodyLimit*pageLimit;
constexpr NSTimeInterval overallTimeout=30;
void wipe(NSMutableData *data){volatile uint8_t *p=(volatile uint8_t *)data.mutableBytes;for(NSUInteger i=0;i<data.length;++i)p[i]=0;[data setLength:0];}
bool validKey(NSData *key){if(!key||key.length==0||key.length>keyLimit)return false;const auto *bytes=(const uint8_t *)key.bytes;if(!bytes)return false;for(NSUInteger i=0;i<key.length;++i)if(bytes[i]<33||bytes[i]>126)return false;return true;}
bool integer(id value,uint64_t *result){if(![value isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()||CFNumberIsFloatType((__bridge CFNumberRef)value))return false;const int64_t n=[value longLongValue];if(n<0)return false;*result=(uint64_t)n;return true;}
bool jsonDepth(NSData *data){const auto *p=(const uint8_t *)data.bytes;NSUInteger depth=0;bool quoted=false,escaped=false;for(NSUInteger i=0;i<data.length;++i){const auto c=p[i];if(quoted){if(escaped)escaped=false;else if(c=='\\')escaped=true;else if(c=='"')quoted=false;}else if(c=='"')quoted=true;else if(c=='{'||c=='['){if(++depth>32)return false;}else if(c=='}'||c==']'){if(!depth)return false;--depth;}}return !quoted&&!depth;}
NSURL *pageURL(NSUInteger page){return [NSURL URLWithString:[NSString stringWithFormat:@"https://api.itch.io/profile/owned-keys?game_ids=%llu&per_page=%lu&page=%lu",(unsigned long long)gameID,(unsigned long)pageSize,(unsigned long)page]];}
EHRItchOwnershipStatus httpFailure(NSInteger status){if(status==401)return EHRItchOwnershipInvalidCredential;if(status==403)return EHRItchOwnershipInsufficientScope;if(status==429||status>=500)return EHRItchOwnershipServiceUnavailable;return EHRItchOwnershipServerRejected;}
enum class PageResult {Verified,Empty,More,Malformed,Rejected};
// Numeric-only stages describe validation boundaries, never response values.
enum Stage:int32_t {
    NotStarted=0,BadCredential=1,RequestPrepared=2,ResponseReceived=3,
    HeaderNotHTTP=4,HeaderURLMismatch=5,HTTPRejected=6,HeaderMIMERejected=7,
    HeaderLengthExceeded=8,BodyReceived=9,BodyLimitExceeded=10,
    DeadlineExceeded=11,NetworkError=12,RedirectRejected=13,Cancelled=14,
    BodyEmpty=20,BodyBoundaryInvalid=21,JSONDecodeFailed=22,RootNotObject=23,
    ErrorEnvelope=24,PageTypeInvalid=25,PageValueMismatch=26,
    PerPageTypeInvalid=27,PerPageValueMismatch=28,OwnedKeysTypeInvalid=29,
    OwnedKeysTooMany=30,RecordNotObject=31,RecordIDInvalid=32,
    RecordGameIDInvalid=33,RecordGameMismatch=34,DuplicateID=35,
    NestedGameInvalid=36,RevokedFlagInvalid=37,RevokedAtInvalid=38,
    Verified=40,Empty=41,More=42,PageLimitExceeded=43
};
int kind(id value){
    if(!value)return 0;if(value==NSNull.null)return 1;
    if([value isKindOfClass:NSDictionary.class])return 2;
    if([value isKindOfClass:NSArray.class])return 3;
    if([value isKindOfClass:NSNumber.class]){if(CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID())return 6;return CFNumberIsFloatType((__bridge CFNumberRef)value)?5:4;}
    return [value isKindOfClass:NSString.class]?7:8;
}
NSNumber *boundedPageValue(id value){if(kind(value)!=4)return @0;NSNumber *number=value;if([number compare:@1000]==NSOrderedDescending)return @1000;if([number compare:@(-1000)]==NSOrderedAscending)return @(-1000);return @([number longLongValue]);}
void resetDiagnostics(NSMutableDictionary *diagnostics,NSUInteger page,NSUInteger total){
    [diagnostics setDictionary:@{@"schemaVersion":@1,@"parserStage":@(RequestPrepared),@"requestedPage":@(MIN(page,pageLimit+1)),
        @"responseBytes":@0,@"totalBytes":@(MIN(total,totalLimit)),@"httpTyped":@0,@"urlMatched":@0,@"mimeJSON":@0,@"lengthOK":@0,
        @"rootKind":@0,@"ownedKeysKind":@0,@"ownedKeysCount":@0,@"pageKind":@0,@"returnedPage":@0,@"perPageKind":@0,@"returnedPerPage":@0}];
}
PageResult parsePage(NSData *data,NSUInteger page,NSMutableSet<NSNumber *> *seen,NSMutableDictionary *diagnostics){
    auto failure=[&](Stage stage,PageResult result=PageResult::Malformed){diagnostics[@"parserStage"]=@(stage);return result;};
    diagnostics[@"responseBytes"]=@(MIN(data.length,bodyLimit));
    if(!data.length)return failure(BodyEmpty);
    if(data.length>bodyLimit||!jsonDepth(data))return failure(BodyBoundaryInvalid);
    NSError *error=nil;id object=[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:&error];
    if(error||!object)return failure(JSONDecodeFailed);
    diagnostics[@"rootKind"]=@(kind(object));
    if(![object isKindOfClass:NSDictionary.class])return failure(RootNotObject);
    NSDictionary *json=object;id rowsValue=json[@"owned_keys"],pageValue=json[@"page"],sizeValue=json[@"per_page"];
    diagnostics[@"ownedKeysKind"]=@(kind(rowsValue));diagnostics[@"pageKind"]=@(kind(pageValue));diagnostics[@"perPageKind"]=@(kind(sizeValue));
    diagnostics[@"returnedPage"]=boundedPageValue(pageValue);diagnostics[@"returnedPerPage"]=boundedPageValue(sizeValue);
    if([rowsValue isKindOfClass:NSArray.class]||[rowsValue isKindOfClass:NSDictionary.class])diagnostics[@"ownedKeysCount"]=@(MIN((NSUInteger)[rowsValue count],(NSUInteger)1000));
    if(json[@"errors"]||json[@"error"])return failure(ErrorEnvelope,PageResult::Rejected);
    uint64_t returnedPage=0,returnedSize=0;
    if(!integer(pageValue,&returnedPage))return failure(PageTypeInvalid);
    if(returnedPage!=page)return failure(PageValueMismatch);
    if(!integer(sizeValue,&returnedSize))return failure(PerPageTypeInvalid);
    if(returnedSize!=pageSize)return failure(PerPageValueMismatch);
    // The live API has returned an empty object for an empty owned-key page.
    // This compatibility case is negative only, after all envelope/pagination
    // checks. A nonempty object can never establish an entitlement.
    if([rowsValue isKindOfClass:NSDictionary.class]&&[(NSDictionary *)rowsValue count]==0)return failure(Empty,PageResult::Empty);
    if(![rowsValue isKindOfClass:NSArray.class])return failure(OwnedKeysTypeInvalid);
    NSArray *rows=rowsValue;if(rows.count>pageSize)return failure(OwnedKeysTooMany);
    NSMutableSet<NSNumber *> *newIDs=[NSMutableSet new];bool verified=false;
    for(id row in rows){
        if(![row isKindOfClass:NSDictionary.class])return failure(RecordNotObject);
        NSDictionary *entry=row;uint64_t idValue=0,game=0;
        if(!integer(entry[@"id"],&idValue)||!idValue)return failure(RecordIDInvalid);
        if(!integer(entry[@"game_id"],&game))return failure(RecordGameIDInvalid);
        if(game!=gameID)return failure(RecordGameMismatch);
        NSNumber *identity=@(idValue);if([seen containsObject:identity]||[newIDs containsObject:identity])return failure(DuplicateID);[newIDs addObject:identity];
        if(entry[@"game"]){if(![entry[@"game"] isKindOfClass:NSDictionary.class]||!integer(entry[@"game"][@"id"],&game)||game!=gameID)return failure(NestedGameInvalid);}
        bool revoked=false;
        if(entry[@"revoked"]){if(![entry[@"revoked"] isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)entry[@"revoked"])!=CFBooleanGetTypeID())return failure(RevokedFlagInvalid);revoked=[entry[@"revoked"] boolValue];}
        if(entry[@"revoked_at"]&&entry[@"revoked_at"]!=NSNull.null){if(![entry[@"revoked_at"] isKindOfClass:NSString.class]||![entry[@"revoked_at"] length])return failure(RevokedAtInvalid);revoked=true;}
        if(!revoked)verified=true;
    }
    [seen unionSet:newIDs];return verified?failure(Verified,PageResult::Verified):rows.count?failure(More,PageResult::More):failure(Empty,PageResult::Empty);
}
}

@interface EHRItchOwnershipCheck()<NSURLSessionDataDelegate>
@property(nonatomic,strong) NSLock *lock;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *diagnostics;
@property(nonatomic,strong) NSMutableData *key;
@property(nonatomic,strong) NSMutableData *body;
@property(nonatomic,strong) NSMutableSet<NSNumber *> *seen;
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) NSURLSessionDataTask *task;
@property(nonatomic,strong) NSURL *requestURL;
@property(nonatomic,copy) EHRItchOwnershipCompletion completion;
@property(nonatomic) BOOL finished;
@property(nonatomic) NSUInteger page,totalBytes;
@property(nonatomic) int32_t httpStatus;
@property(nonatomic) NSTimeInterval deadline;
- (instancetype)initWithKey:(NSData *)key completion:(EHRItchOwnershipCompletion)completion;
- (void)start;
- (void)finish:(EHRItchOwnershipStatus)status;
@end
@implementation EHRItchOwnershipCheck
- (instancetype)initWithKey:(NSData *)key completion:(EHRItchOwnershipCompletion)completion {if((self=[super init])){self.lock=[NSLock new];self.diagnostics=[NSMutableDictionary new];resetDiagnostics(self.diagnostics,0,0);self.diagnostics[@"parserStage"]=@(NotStarted);self.key=key.length<=keyLimit?[key mutableCopy]:nil;self.completion=[completion copy];self.seen=[NSMutableSet new];self.page=1;self.deadline=NSProcessInfo.processInfo.systemUptime+overallTimeout;}return self;}
- (void)start {
    [self.lock lock];if(self.finished){[self.lock unlock];return;}
    if(!validKey(self.key)){self.diagnostics[@"parserStage"]=@(BadCredential);[self.lock unlock];[self finish:EHRItchOwnershipBadCredentialFormat];return;}
    if(NSProcessInfo.processInfo.systemUptime>=self.deadline){self.diagnostics[@"parserStage"]=@(DeadlineExceeded);[self.lock unlock];[self finish:EHRItchOwnershipNetworkUnavailable];return;}
    NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;configuration.URLCache=nil;configuration.URLCredentialStorage=nil;configuration.HTTPCookieStorage=nil;configuration.HTTPShouldSetCookies=NO;configuration.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;configuration.timeoutIntervalForRequest=10;configuration.timeoutIntervalForResource=20;configuration.TLSMinimumSupportedProtocolVersion=tls_protocol_version_TLSv12;
    NSOperationQueue *queue=[NSOperationQueue new];queue.maxConcurrentOperationCount=1;
    self.session=[NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:queue];
    [self.lock unlock];[self nextPage];
}
- (void)nextPage {
    [self.lock lock];if(self.finished){[self.lock unlock];return;}
    if(self.page>pageLimit){self.diagnostics[@"parserStage"]=@(PageLimitExceeded);[self.lock unlock];[self finish:EHRItchOwnershipLimitExceeded];return;}
    if(NSProcessInfo.processInfo.systemUptime>=self.deadline){self.diagnostics[@"parserStage"]=@(DeadlineExceeded);[self.lock unlock];[self finish:EHRItchOwnershipNetworkUnavailable];return;}
    resetDiagnostics(self.diagnostics,self.page,self.totalBytes);self.body=[NSMutableData new];self.httpStatus=0;self.requestURL=pageURL(self.page);
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:self.requestURL];request.HTTPMethod=@"GET";request.cachePolicy=NSURLRequestReloadIgnoringLocalCacheData;request.timeoutInterval=10;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    NSString *secret=[[NSString alloc] initWithData:self.key encoding:NSASCIIStringEncoding];[request setValue:[@"Bearer " stringByAppendingString:secret] forHTTPHeaderField:@"Authorization"];
    self.task=[self.session dataTaskWithRequest:request];[self.task resume];[self.lock unlock];
}
- (void)finish:(EHRItchOwnershipStatus)status {
    [self.lock lock];if(self.finished){[self.lock unlock];return;}self.finished=YES;if(status==EHRItchOwnershipCancelled)self.diagnostics[@"parserStage"]=@(Cancelled);if(status==EHRItchOwnershipNetworkUnavailable&&NSProcessInfo.processInfo.systemUptime>=self.deadline)self.diagnostics[@"parserStage"]=@(DeadlineExceeded);
    EHRItchOwnershipCompletion completion=self.completion;self.completion=nil;const int32_t http=self.httpStatus;NSURLSession *session=self.session;self.session=nil;self.task=nil;self.requestURL=nil;
    wipe(self.key);self.key=nil;wipe(self.body);self.body=nil;[self.seen removeAllObjects];[self.lock unlock];[session invalidateAndCancel];
    // Always asynchronous, so the caller can retain the returned cancellation
    // handle before even an invalid-input completion is delivered.
    dispatch_async(dispatch_get_main_queue(),^{@try{try{if(completion)completion(status,http);}catch(...){}}@catch(__unused NSException *exception){}});
}
- (void)cancel {[self finish:EHRItchOwnershipCancelled];}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void(^)(NSURLSessionResponseDisposition))handler {
    (void)session;(void)task;[self.lock lock];if(self.finished){[self.lock unlock];handler(NSURLSessionResponseCancel);return;}
    BOOL typed=[response isKindOfClass:NSHTTPURLResponse.class];NSInteger status=typed?[(NSHTTPURLResponse *)response statusCode]:0;self.httpStatus=status>=0&&status<=999?(int32_t)status:0;
    BOOL url=[response.URL.absoluteString isEqualToString:self.requestURL.absoluteString];BOOL json=[response.MIMEType.lowercaseString isEqualToString:@"application/json"];BOOL limit=response.expectedContentLength<0||(uint64_t)response.expectedContentLength<=bodyLimit;
    self.diagnostics[@"httpTyped"]=@(typed);self.diagnostics[@"urlMatched"]=@(url);self.diagnostics[@"mimeJSON"]=@(json);self.diagnostics[@"lengthOK"]=@(limit);
    self.diagnostics[@"parserStage"]=@(ResponseReceived);
    if(!typed)self.diagnostics[@"parserStage"]=@(HeaderNotHTTP);else if(!url)self.diagnostics[@"parserStage"]=@(HeaderURLMismatch);
    else if(status!=200)self.diagnostics[@"parserStage"]=@(HTTPRejected);else if(!limit)self.diagnostics[@"parserStage"]=@(HeaderLengthExceeded);else if(!json)self.diagnostics[@"parserStage"]=@(HeaderMIMERejected);
    [self.lock unlock];
    if(!typed||!url){handler(NSURLSessionResponseCancel);[self finish:EHRItchOwnershipMalformedResponse];return;}
    if(status!=200){handler(NSURLSessionResponseCancel);[self finish:httpFailure(status)];return;}
    if(!limit||!json){handler(NSURLSessionResponseCancel);[self finish:limit?EHRItchOwnershipMalformedResponse:EHRItchOwnershipLimitExceeded];return;}
    handler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void(^)(NSURLRequest *))handler {(void)session;(void)task;(void)request;[self.lock lock];if(!self.finished){NSInteger status=response.statusCode;self.httpStatus=status>=0&&status<=999?(int32_t)status:0;self.diagnostics[@"parserStage"]=@(RedirectRejected);}[self.lock unlock];handler(nil);[self finish:EHRItchOwnershipRedirectRejected];}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    (void)session;(void)task;[self.lock lock];BOOL timedOut=!self.finished&&NSProcessInfo.processInfo.systemUptime>=self.deadline;BOOL tooLarge=!self.finished&&(data.length>bodyLimit-self.body.length||data.length>totalLimit-self.totalBytes);if(!self.finished&&!tooLarge&&!timedOut){[self.body appendData:data];self.totalBytes+=data.length;self.diagnostics[@"responseBytes"]=@(self.body.length);self.diagnostics[@"totalBytes"]=@(self.totalBytes);self.diagnostics[@"parserStage"]=@(BodyReceived);}
    if(timedOut)self.diagnostics[@"parserStage"]=@(DeadlineExceeded);else if(tooLarge)self.diagnostics[@"parserStage"]=@(BodyLimitExceeded);[self.lock unlock];if(timedOut)[self finish:EHRItchOwnershipNetworkUnavailable];else if(tooLarge)[self finish:EHRItchOwnershipLimitExceeded];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)session;(void)task;[self.lock lock];if(self.finished){[self.lock unlock];return;}if(error||NSProcessInfo.processInfo.systemUptime>=self.deadline){self.diagnostics[@"parserStage"]=@(NSProcessInfo.processInfo.systemUptime>=self.deadline?DeadlineExceeded:NetworkError);[self.lock unlock];[self finish:EHRItchOwnershipNetworkUnavailable];return;}
    PageResult page=parsePage(self.body,self.page,self.seen,self.diagnostics);wipe(self.body);self.body=nil;++self.page;[self.lock unlock];
    switch(page){case PageResult::Verified:[self finish:EHRItchOwnershipVerified];break;case PageResult::Empty:[self finish:EHRItchOwnershipNoEntitlement];break;case PageResult::Malformed:[self finish:EHRItchOwnershipMalformedResponse];break;case PageResult::Rejected:[self finish:EHRItchOwnershipServerRejected];break;case PageResult::More:[self nextPage];break;}
}
- (void)dealloc {wipe(_key);wipe(_body);}
@end
EHRItchOwnershipCheck *EHRItchOwnershipBegin(NSData *key,EHRItchOwnershipCompletion completion){
    EHRItchOwnershipCheck *check=[[EHRItchOwnershipCheck alloc] initWithKey:key completion:completion];
    dispatch_async(dispatch_get_main_queue(),^{[check start];});
    __weak EHRItchOwnershipCheck *weak=check;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(overallTimeout*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weak finish:EHRItchOwnershipNetworkUnavailable];});return check;
}

NSDictionary<NSString *,NSNumber *> *EHRItchOwnershipCopyDiagnostics(EHRItchOwnershipCheck *check){
    if(!check)return @{};[check.lock lock];NSDictionary *snapshot=[check.diagnostics copy];[check.lock unlock];return snapshot?:@{};
}
