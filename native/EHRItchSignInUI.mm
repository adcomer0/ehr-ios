#import "EHRItchSignInUI.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#include <mutex>
#include <cstring>

#ifndef EHR_ITCH_UI_POLICY_FIXTURE
#define EHR_ITCH_UI_POLICY_FIXTURE 0
#endif
#if !EHR_ITCH_UI_POLICY_FIXTURE
#import <UIKit/UIKit.h>
#import <AuthenticationServices/AuthenticationServices.h>
#import <QuartzCore/QuartzCore.h>
#endif

namespace {
constexpr NSUInteger kKeyLimit=8192,kResponseLimit=65536;
constexpr uint64_t kCounterLimit=1000000;
struct Facts {uint64_t presented=0,submitted=0,cancelled=0,oauthStarted=0,oauthFailed=0,saved=0,saveFailed=0,forgotten=0,rejected=0;int32_t local=0,eos=0,ownership=EHRItchOwnershipCancelled,ownershipHTTP=0;bool ownershipPending=false,ownershipVerified=false,visible=false,busy=false,oauthConfigured=false,completed=false,resultKnown=false,awaitingNewProfile=false,newProfileConfirmed=false;};
std::mutex factsMutex;Facts facts;
static void Increment(uint64_t &counter){if(counter<kCounterLimit)++counter;}
static bool ValidKey(NSData *data){if(!data||data.length==0||data.length>kKeyLimit)return false;const uint8_t *p=(const uint8_t *)data.bytes;for(NSUInteger i=0;i<data.length;++i)if(p[i]<=0x20||p[i]>0x7e)return false;return true;}
static bool FullResultAllowed(int32_t local,int32_t eos,bool completed,bool confirmedNewProfile,bool ownershipVerified){return ownershipVerified&&local==0&&completed&&(eos==0||(eos==3&&confirmedNewProfile));}
static EHRItchOwnershipStatus BoundedOwnershipStatus(EHRItchOwnershipStatus status){return status>=EHRItchOwnershipVerified&&status<=EHRItchOwnershipServerRejected?status:EHRItchOwnershipMalformedResponse;}
static int32_t BoundedHTTPStatus(int32_t status){return status>=0&&status<=999?status:0;}
static NSURL *OwnershipLibraryURL(void){return [NSURL URLWithString:@"https://itch.io/my-purchases"];}
static NSString *OwnershipMessage(EHRItchOwnershipStatus status,bool pending){
    if(pending)return @"Checking that your itch.io account owns Among Us…";
    switch(status){
        case EHRItchOwnershipVerified:return @"Among Us ownership confirmed. Waiting for the game to confirm sign-in…";
        case EHRItchOwnershipNoEntitlement:return @"This itch.io account has no claimed copy of Among Us. Open your itch.io library, claim the game if it came in a bundle, then try again.";
        case EHRItchOwnershipInvalidCredential:return @"itch.io didn’t accept this key. Check your key or sign in through the browser again.";
        case EHRItchOwnershipInsufficientScope:return @"This key can’t check your game library. Use a key with profile:owned permission, or sign in through the browser again.";
        case EHRItchOwnershipNetworkUnavailable:return @"We couldn’t reach itch.io to check ownership. Check your connection and try again.";
        case EHRItchOwnershipServiceUnavailable:return @"itch.io is temporarily unavailable. Please try the ownership check again later.";
        case EHRItchOwnershipCancelled:return @"Ownership check cancelled. You can try signing in again.";
        case EHRItchOwnershipBadCredentialFormat:return @"Enter a key of at most 8192 ASCII bytes, without spaces or line breaks.";
        case EHRItchOwnershipMalformedResponse:case EHRItchOwnershipLimitExceeded:case EHRItchOwnershipRedirectRejected:case EHRItchOwnershipServerRejected:
            return @"itch.io ownership could not be confirmed. Please try again later.";
    }
    return @"itch.io ownership could not be confirmed. Please try again later.";
}
static void Wipe(NSMutableData *data){if(!data)return;volatile uint8_t *p=(volatile uint8_t *)data.mutableBytes;for(NSUInteger i=0;i<data.length;++i)p[i]=0;[data setLength:0];}
static NSString *Service(void){NSString *bundle=NSBundle.mainBundle.bundleIdentifier;if(!bundle.length)return nil;return [bundle stringByAppendingString:@".ehr.itch-signin"];}
static NSMutableDictionary *KeyQuery(NSString *service){if(!service.length)return nil;return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:service,(__bridge id)kSecAttrAccount:@"player-key",(__bridge id)kSecAttrSynchronizable:@NO} mutableCopy];}
static NSDictionary *KeyAttributes(NSData *data){if(!ValidKey(data))return nil;return @{(__bridge id)kSecValueData:data,(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,(__bridge id)kSecAttrSynchronizable:@NO};}
static OSStatus StoreKey(NSData *data){NSMutableDictionary *query=KeyQuery(Service());NSDictionary *attrs=KeyAttributes(data);if(!query||!attrs)return errSecParam;OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)query,(__bridge CFDictionaryRef)attrs);if(status==errSecItemNotFound){[query addEntriesFromDictionary:attrs];status=SecItemAdd((__bridge CFDictionaryRef)query,nullptr);}return status;}
static OSStatus ForgetKey(void){NSDictionary *query=KeyQuery(Service());return query?SecItemDelete((__bridge CFDictionaryRef)query):errSecParam;}
static NSString *Base64URL(NSData *data){NSString *s=[data base64EncodedStringWithOptions:0];s=[s stringByReplacingOccurrencesOfString:@"+" withString:@"-"];s=[s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];return [s stringByReplacingOccurrencesOfString:@"=" withString:@""];}
static NSString *RandomValue(void){uint8_t bytes[32];if(SecRandomCopyBytes(kSecRandomDefault,sizeof(bytes),bytes)!=errSecSuccess)return nil;NSMutableData *data=[NSMutableData dataWithBytes:bytes length:sizeof(bytes)];std::memset(bytes,0,sizeof(bytes));NSString *s=Base64URL(data);Wipe(data);return s;}
static NSString *Challenge(NSString *verifier){NSData *data=[verifier dataUsingEncoding:NSASCIIStringEncoding];if(data.length<43||data.length>128)return nil;uint8_t hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,hash);return Base64URL([NSData dataWithBytes:hash length:sizeof(hash)]);}
static NSDictionary *OAuthConfig(NSDictionary *info){
    NSString *client=info[@"EHRItchOAuthClientID"],*redirect=info[@"EHRItchOAuthRedirectURI"];
    if(![client isKindOfClass:NSString.class]||!client.length||client.length>256||![redirect isKindOfClass:NSString.class]||redirect.length>1024)return nil;
    NSCharacterSet *clientChars=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"];
    if([client rangeOfCharacterFromSet:clientChars.invertedSet].location!=NSNotFound)return nil;
    NSURLComponents *parts=[NSURLComponents componentsWithString:redirect];NSString *scheme=parts.scheme.lowercaseString;
    if(!parts.URL||!scheme.length||!parts.host.length||!parts.path.length||parts.user||parts.password||parts.port||parts.query||parts.fragment||[scheme isEqualToString:@"http"]||[scheme isEqualToString:@"https"]||[scheme isEqualToString:@"file"]||[scheme isEqualToString:@"data"]||[scheme isEqualToString:@"javascript"])return nil;
    BOOL registered=NO;id types=info[@"CFBundleURLTypes"];if(![types isKindOfClass:NSArray.class])return nil;
    for(id type in types){if(![type isKindOfClass:NSDictionary.class])continue;id schemes=type[@"CFBundleURLSchemes"];if(![schemes isKindOfClass:NSArray.class])continue;for(id value in schemes)if([value isKindOfClass:NSString.class]&&[value caseInsensitiveCompare:scheme]==NSOrderedSame)registered=YES;}
    if(!registered)return nil;return @{@"client":client,@"redirect":redirect,@"scheme":scheme};
}
static NSURL *AuthorizationURL(NSDictionary *config,NSString *state,NSString *challenge){if(!config||!state.length||!challenge.length)return nil;NSURLComponents *u=[NSURLComponents componentsWithString:@"https://itch.io/user/oauth"];u.queryItems=@[[NSURLQueryItem queryItemWithName:@"client_id" value:config[@"client"]],[NSURLQueryItem queryItemWithName:@"scope" value:@"profile:me profile:owned"],[NSURLQueryItem queryItemWithName:@"redirect_uri" value:config[@"redirect"]],[NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],[NSURLQueryItem queryItemWithName:@"state" value:state],[NSURLQueryItem queryItemWithName:@"code_challenge" value:challenge],[NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"]];return u.URL;}
static void Deliver(EHRItchSignInSubmit submit,NSData *key){if(!submit)return;try{@try{submit(key);}@catch(NSException *error){(void)error;}}catch(...){}}
static BOOL SameState(NSString *left,NSString *right){NSData *a=[left dataUsingEncoding:NSUTF8StringEncoding],*b=[right dataUsingEncoding:NSUTF8StringEncoding];if(!a.length||a.length!=b.length)return NO;const uint8_t *x=(const uint8_t *)a.bytes,*y=(const uint8_t *)b.bytes;volatile uint8_t difference=0;for(NSUInteger i=0;i<a.length;++i)difference|=x[i]^y[i];return difference==0;}
static NSString *CallbackCode(NSURL *url,NSDictionary *config,NSString *state){
    if(!url||!config)return nil;NSURLComponents *got=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO],*wanted=[NSURLComponents componentsWithString:config[@"redirect"]];
    if(!got.scheme.length||!got.host.length||got.user||got.password||got.port||got.fragment||[got.scheme caseInsensitiveCompare:wanted.scheme]!=NSOrderedSame||[got.host caseInsensitiveCompare:wanted.host]!=NSOrderedSame||![got.percentEncodedPath isEqualToString:wanted.percentEncodedPath])return nil;
    NSMutableDictionary *items=[NSMutableDictionary new];for(NSURLQueryItem *item in got.queryItems){if(![@[@"code",@"state"] containsObject:item.name]||items[item.name]||!item.value)return nil;items[item.name]=item.value;}
    NSString *code=items[@"code"];if(items.count!=2||!SameState(items[@"state"],state)||![code isKindOfClass:NSString.class]||code.length==0||code.length>4096)return nil;return code;
}
static NSString *FormValue(NSString *value){NSData *data=[value dataUsingEncoding:NSUTF8StringEncoding];NSMutableString *out=[NSMutableString new];const uint8_t *bytes=(const uint8_t *)data.bytes;for(NSUInteger i=0;i<data.length;++i){uint8_t c=bytes[i];if((c>='A'&&c<='Z')||(c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='-'||c=='_'||c=='.'||c=='~')[out appendFormat:@"%c",c];else [out appendFormat:@"%%%02X",c];}return out;}
static NSMutableData *TokenBody(NSDictionary *config,NSString *code,NSString *verifier){if(!config||!code||!verifier)return nil;NSString *text=[NSString stringWithFormat:@"grant_type=authorization_code&code=%@&code_verifier=%@&redirect_uri=%@&client_id=%@",FormValue(code),FormValue(verifier),FormValue(config[@"redirect"]),FormValue(config[@"client"])];return [[text dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];}
static BOOL ResponseAllowed(NSURLResponse *response){if(![response isKindOfClass:NSHTTPURLResponse.class])return NO;NSHTTPURLResponse *http=(NSHTTPURLResponse *)response;return http.statusCode==200&&[http.MIMEType.lowercaseString isEqualToString:@"application/json"]&&(http.expectedContentLength<0||(uint64_t)http.expectedContentLength<=kResponseLimit);}
static NSMutableData *ParseToken(NSData *body){if(!body.length||body.length>kResponseLimit)return nil;@autoreleasepool{id json=[NSJSONSerialization JSONObjectWithData:body options:0 error:nil];if(![json isKindOfClass:NSDictionary.class])return nil;id token=json[@"access_token"],type=json[@"token_type"];if(![token isKindOfClass:NSString.class]||![type isKindOfClass:NSString.class]||[type caseInsensitiveCompare:@"bearer"]!=NSOrderedSame)return nil;NSMutableData *bytes=[[token dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];if(!ValidKey(bytes)){Wipe(bytes);return nil;}return bytes;}}
}

NSMutableData *EHRItchSignInCopySavedKey(void){NSMutableDictionary *query=KeyQuery(Service());if(!query)return nil;query[(__bridge id)kSecReturnData]=@YES;query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;CFTypeRef result=nullptr;OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&result);NSMutableData *copy=nil;if(status==errSecSuccess&&result&&CFGetTypeID(result)==CFDataGetTypeID()&&CFDataGetLength((CFDataRef)result)>0&&CFDataGetLength((CFDataRef)result)<=(CFIndex)kKeyLimit)copy=[(__bridge NSData *)result mutableCopy];if(result)CFRelease(result);if(!ValidKey(copy)){Wipe(copy);return nil;}return copy;}
NSDictionary *EHRItchSignInCopyStatus(void){Facts copy;{std::lock_guard<std::mutex> lock(factsMutex);copy=facts;}return @{@"schemaVersion":@1,@"presented":@(copy.presented),@"submissions":@(copy.submitted),@"cancelled":@(copy.cancelled),@"oauthStarted":@(copy.oauthStarted),@"oauthFailures":@(copy.oauthFailed),@"saved":@(copy.saved),@"saveFailures":@(copy.saveFailed),@"forgotten":@(copy.forgotten),@"rejected":@(copy.rejected),@"visible":@(copy.visible),@"busy":@(copy.busy),@"oauthConfigured":@(copy.oauthConfigured),@"localStatus":@(copy.local),@"eosResult":@(copy.eos),@"fullGameCompleted":@(copy.completed),@"resultKnown":@(copy.resultKnown),@"awaitingNewProfileConfirmation":@(copy.awaitingNewProfile),@"newProfileConfirmed":@(copy.newProfileConfirmed),@"ownershipStatus":@(copy.ownership),@"ownershipHTTPStatus":@(copy.ownershipHTTP),@"ownershipPending":@(copy.ownershipPending),@"ownershipVerified":@(copy.ownershipVerified)};}

#if !EHR_ITCH_UI_POLICY_FIXTURE
static UIColor *Ink(void){return [UIColor colorWithRed:0.035 green:0.047 blue:0.086 alpha:1];}
static UIColor *Accent(void){return [UIColor colorWithRed:0.35 green:0.87 blue:0.94 alpha:1];}
static UIColor *Muted(void){return [UIColor colorWithRed:0.62 green:0.69 blue:0.78 alpha:1];}
static UILabel *Text(NSString *text,CGFloat size,UIFontWeight weight){UILabel *label=[UILabel new];label.text=text;label.textColor=UIColor.whiteColor;label.font=[[UIFontMetrics defaultMetrics] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];label.numberOfLines=0;label.adjustsFontForContentSizeCategory=YES;return label;}
@interface EHRAuthBackground:UIView
@end
@implementation EHRAuthBackground
- (instancetype)initWithFrame:(CGRect)frame {if((self=[super initWithFrame:frame]))self.contentMode=UIViewContentModeRedraw;return self;}
- (void)drawRect:(CGRect)rect {
    CGContextRef context=UIGraphicsGetCurrentContext();if(!context)return;
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();CGFloat colors[]={0.055,0.09,0.15,1,0.018,0.027,0.055,1};CGFloat stops[]={0,1};CGGradientRef gradient=CGGradientCreateWithColorComponents(space,colors,stops,2);
    CGContextDrawLinearGradient(context,gradient,CGPointZero,CGPointMake(rect.size.width,rect.size.height),0);CGGradientRelease(gradient);CGColorSpaceRelease(space);
    for(NSUInteger i=0;i<34;++i){CGFloat x=fmod(i*139.0+29,MAX(1,rect.size.width)),y=fmod(i*97.0+31,MAX(1,rect.size.height));CGFloat radius=i%5==0?1.4:0.7;[[UIColor colorWithWhite:1 alpha:i%3==0?0.23:0.10] setFill];CGContextFillEllipseInRect(context,CGRectMake(x,y,radius*2,radius*2));}
}
@end
static void StyleNavigation(UINavigationController *navigation){navigation.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];[appearance configureWithTransparentBackground];appearance.titleTextAttributes=@{NSForegroundColorAttributeName:UIColor.whiteColor};navigation.navigationBar.standardAppearance=appearance;navigation.navigationBar.scrollEdgeAppearance=appearance;navigation.navigationBar.tintColor=Accent();}
static UIButton *StyledButton(NSString *title,id target,SEL action,BOOL primary){UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *configuration=primary?[UIButtonConfiguration filledButtonConfiguration]:[UIButtonConfiguration plainButtonConfiguration];configuration.title=title;configuration.baseForegroundColor=primary?Ink():Accent();configuration.baseBackgroundColor=primary?Accent():UIColor.clearColor;configuration.cornerStyle=UIButtonConfigurationCornerStyleLarge;configuration.contentInsets=NSDirectionalEdgeInsetsMake(14,18,14,18);button.configuration=configuration;[button setTitle:title forState:UIControlStateNormal];button.accessibilityLabel=title;button.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];[button.heightAnchor constraintGreaterThanOrEqualToConstant:52].active=YES;[button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];return button;}
static UIImageView *BrandMark(void){UIImage *image=[UIImage imageNamed:@"EHRBrandIcon"];if(!image)image=[UIImage systemImageNamed:@"sparkles.rectangle.stack.fill"];UIImageView *mark=[[UIImageView alloc] initWithImage:image];mark.contentMode=UIViewContentModeScaleAspectFit;mark.tintColor=Accent();mark.layer.cornerRadius=22;mark.clipsToBounds=YES;mark.isAccessibilityElement=NO;return mark;}
@interface EHRItchTokenExchange:NSObject<NSURLSessionDataDelegate>
@property(nonatomic,strong) NSLock *lock;
@property(nonatomic,strong) NSMutableData *received;
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) NSURLSessionDataTask *task;
@property(nonatomic,copy) void(^completion)(NSMutableData *,int32_t);
@property(nonatomic) BOOL finished;
- (void)start:(NSMutableURLRequest *)request completion:(void(^)(NSMutableData *,int32_t))completion;
- (void)finish:(NSMutableData *)key status:(int32_t)status;
- (void)cancel;
@end
@implementation EHRItchTokenExchange
- (void)start:(NSMutableURLRequest *)request completion:(void(^)(NSMutableData *,int32_t))completion {
    self.lock=[NSLock new];self.received=[NSMutableData new];self.completion=completion;
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.URLCache=nil;config.URLCredentialStorage=nil;config.HTTPCookieStorage=nil;config.HTTPShouldSetCookies=NO;config.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;config.timeoutIntervalForRequest=20;config.timeoutIntervalForResource=30;
    NSOperationQueue *queue=[NSOperationQueue new];queue.maxConcurrentOperationCount=1;
    self.session=[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:queue];self.task=[self.session dataTaskWithRequest:request];[self.task resume];
}
- (void)finish:(NSMutableData *)key status:(int32_t)status {
    [self.lock lock];if(self.finished){[self.lock unlock];Wipe(key);return;}self.finished=YES;
    void(^completion)(NSMutableData *,int32_t)=self.completion;self.completion=nil;NSURLSession *session=self.session;self.session=nil;self.task=nil;Wipe(self.received);self.received=nil;[self.lock unlock];[session invalidateAndCancel];
    void(^deliver)(void)=^{@try{try{if(completion)completion(key,status);}catch(...){}}@catch(NSException *error){(void)error;}@finally{Wipe(key);}};if(NSThread.isMainThread)deliver();else dispatch_async(dispatch_get_main_queue(),deliver);
}
- (void)cancel {[self finish:nil status:11];}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void(^)(NSURLSessionResponseDisposition))completionHandler {(void)session;(void)task;if(!ResponseAllowed(response)){completionHandler(NSURLSessionResponseCancel);[self finish:nil status:12];return;}completionHandler(NSURLSessionResponseAllow);}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void(^)(NSURLRequest *))completionHandler {(void)session;(void)task;(void)response;(void)request;completionHandler(nil);[self finish:nil status:13];}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {(void)session;(void)task;[self.lock lock];BOOL overflow=!self.finished&&(data.length>kResponseLimit-self.received.length);if(!self.finished&&!overflow)[self.received appendData:data];[self.lock unlock];if(overflow)[self finish:nil status:14];}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {(void)session;(void)task;[self.lock lock];BOOL done=self.finished;NSMutableData *body=done?nil:[self.received mutableCopy];[self.lock unlock];if(done)return;NSMutableData *key=error?nil:ParseToken(body);Wipe(body);[self finish:key status:key?0:15];}
@end

@interface EHRItchSignInController:UIViewController<ASWebAuthenticationPresentationContextProviding,UIAdaptivePresentationControllerDelegate,UITextFieldDelegate>
@property(nonatomic,copy) EHRItchSignInSubmit submit;
@property(nonatomic,strong) UITextField *field;
@property(nonatomic,strong) UISwitch *remember;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UILabel *detailsLabel;
@property(nonatomic,strong) UIButton *visibilityButton;
@property(nonatomic,strong) UIStackView *contentStack;
@property(nonatomic,strong) UIStackView *heroStack;
@property(nonatomic,strong) NSLayoutConstraint *heroWidth;
@property(nonatomic,strong) NSLayoutConstraint *maximumWidth;
@property(nonatomic,strong) UIButton *manualButton;
@property(nonatomic,strong) UIButton *browserButton;
@property(nonatomic,strong) UIButton *savedButton;
@property(nonatomic,strong) UIButton *createProfileButton;
@property(nonatomic,strong) UIButton *libraryButton;
@property(nonatomic,strong) UIScrollView *formScroll;
@property(nonatomic,copy) int32_t (^confirmNewProfileAction)(void);
@property(nonatomic,strong) NSMutableData *pendingKey;
@property(nonatomic,strong) NSDictionary *config;
@property(nonatomic,strong) ASWebAuthenticationSession *webSession;
@property(nonatomic,strong) EHRItchTokenExchange *exchange;
@property(nonatomic,copy) NSString *state;
@property(nonatomic,copy) NSString *verifier;
@property(nonatomic) uint64_t generation;
@property(nonatomic) BOOL pending,accepted,completed,rememberAttempt,closed,cancelDelivered,awaitingNewProfile,newProfileConfirmed,ownershipPending,ownershipVerified;
- (void)offerNewProfile:(int32_t (^)(void))confirm;
- (void)receiveLocal:(int32_t)local eos:(int32_t)eos completed:(bool)completed;
- (void)receiveOwnership:(EHRItchOwnershipStatus)status http:(int32_t)http pending:(bool)pending;
- (void)cancelFlow;
@end
static EHRItchSignInController *currentController;
@implementation EHRItchSignInController
- (UIButton *)button:(NSString *)title action:(SEL)action {return StyledButton(title,self,action,NO);}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"";self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;self.view=[[EHRAuthBackground alloc] initWithFrame:self.view.bounds];self.config=OAuthConfig(NSBundle.mainBundle.infoDictionary);self.generation=1;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(cancelFlow)];
    UIScrollView *scroll=[UIScrollView new];self.formScroll=scroll;scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;scroll.alwaysBounceVertical=YES;[self.view addSubview:scroll];
    UIView *container=[UIView new];container.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:container];
    UIStackView *outer=[UIStackView new];self.contentStack=outer;outer.axis=UILayoutConstraintAxisVertical;outer.spacing=28;outer.translatesAutoresizingMaskIntoConstraints=NO;[container addSubview:outer];UIStackView *hero=[UIStackView new];self.heroStack=hero;hero.axis=UILayoutConstraintAxisVertical;hero.spacing=14;[outer addArrangedSubview:hero];UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=18;[outer addArrangedSubview:stack];self.heroWidth=[hero.widthAnchor constraintEqualToAnchor:outer.widthAnchor multiplier:0.31];
    UIImageView *mark=BrandMark();UIView *markRow=[UIView new];[markRow addSubview:mark];mark.translatesAutoresizingMaskIntoConstraints=NO;[NSLayoutConstraint activateConstraints:@[[mark.widthAnchor constraintEqualToConstant:84],[mark.heightAnchor constraintEqualToConstant:84],[mark.centerXAnchor constraintEqualToAnchor:markRow.centerXAnchor],[mark.topAnchor constraintEqualToAnchor:markRow.topAnchor],[mark.bottomAnchor constraintEqualToAnchor:markRow.bottomAnchor]]];[hero addArrangedSubview:markRow];
    UILabel *brand=Text(@"EHR Among Us",34,UIFontWeightBold);brand.textAlignment=NSTextAlignmentCenter;brand.accessibilityTraits=UIAccessibilityTraitHeader;[hero addArrangedSubview:brand];[hero setCustomSpacing:8 afterView:brand];
    UILabel *intro=Text(@"Your crew. Your rules.",16,UIFontWeightRegular);intro.textColor=Muted();intro.textAlignment=NSTextAlignmentCenter;[hero addArrangedSubview:intro];
    UILabel *heading=Text(@"Sign in with itch.io",22,UIFontWeightSemibold);heading.accessibilityTraits=UIAccessibilityTraitHeader;[stack addArrangedSubview:heading];[stack setCustomSpacing:8 afterView:heading];
    UILabel *notice=Text(@"Use an itch.io account that owns Among Us. Enter your API key to check ownership and connect your game account.",15,UIFontWeightRegular);notice.textColor=Muted();[stack addArrangedSubview:notice];
    self.field=[UITextField new];self.field.placeholder=@"itch.io API key";self.field.delegate=self;self.field.secureTextEntry=YES;self.field.textContentType=@"";self.field.passwordRules=nil;self.field.keyboardType=UIKeyboardTypeASCIICapable;self.field.returnKeyType=UIReturnKeyGo;self.field.autocorrectionType=UITextAutocorrectionTypeNo;self.field.spellCheckingType=UITextSpellCheckingTypeNo;self.field.autocapitalizationType=UITextAutocapitalizationTypeNone;self.field.smartDashesType=UITextSmartDashesTypeNo;self.field.smartQuotesType=UITextSmartQuotesTypeNo;self.field.textColor=UIColor.whiteColor;self.field.tintColor=Accent();self.field.font=[UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightRegular];self.field.backgroundColor=[UIColor colorWithWhite:1 alpha:0.045];self.field.layer.cornerRadius=14;self.field.layer.borderWidth=1;self.field.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.16].CGColor;[self.field.heightAnchor constraintGreaterThanOrEqualToConstant:58].active=YES;self.field.accessibilityLabel=@"itch.io API key";UIView *inset=[[UIView alloc] initWithFrame:CGRectMake(0,0,16,1)];self.field.leftView=inset;self.field.leftViewMode=UITextFieldViewModeAlways;
    self.visibilityButton=[UIButton buttonWithType:UIButtonTypeSystem];self.visibilityButton.frame=CGRectMake(0,0,52,52);[self.visibilityButton setImage:[UIImage systemImageNamed:@"eye"] forState:UIControlStateNormal];self.visibilityButton.tintColor=Muted();self.visibilityButton.accessibilityLabel=@"Show key";[self.visibilityButton addTarget:self action:@selector(toggleKeyVisibility) forControlEvents:UIControlEventTouchUpInside];self.field.rightView=self.visibilityButton;self.field.rightViewMode=UITextFieldViewModeAlways;[stack addArrangedSubview:self.field];
    self.remember=[UISwitch new];self.remember.on=YES;self.remember.hidden=YES;
    self.manualButton=StyledButton(@"Sign in",self,@selector(submitManual),YES);[stack addArrangedSubview:self.manualButton];
    UILabel *storage=Text(@"Saved securely on this device after sign-in. Manage your saved login in Account.",13,UIFontWeightRegular);storage.textColor=Muted();storage.textAlignment=NSTextAlignmentCenter;[stack addArrangedSubview:storage];
    self.browserButton=[self button:@"Other option: sign in through browser" action:@selector(startBrowser)];self.browserButton.enabled=self.config!=nil;self.browserButton.hidden=self.config==nil;[stack addArrangedSubview:self.browserButton];
    self.statusLabel=Text(@"",15,UIFontWeightRegular);self.statusLabel.textColor=Muted();self.statusLabel.accessibilityTraits=UIAccessibilityTraitUpdatesFrequently;[stack addArrangedSubview:self.statusLabel];
    self.libraryButton=[self button:@"Open itch.io library" action:@selector(openOwnershipLibrary)];self.libraryButton.hidden=YES;[stack addArrangedSubview:self.libraryButton];
    self.createProfileButton=StyledButton(@"Create game account",self,@selector(confirmNewProfile),YES);self.createProfileButton.hidden=YES;self.createProfileButton.enabled=NO;[stack addArrangedSubview:self.createProfileButton];
    self.detailsLabel=Text(@"",12,UIFontWeightRegular);self.detailsLabel.textColor=Muted();self.detailsLabel.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];self.detailsLabel.hidden=YES;[stack addArrangedSubview:self.detailsLabel];
    UILabel *privacy=Text(@"Your key is private. Never share it in chat or screenshots. This does not link or merge Apple accounts.",12,UIFontWeightRegular);privacy.textColor=Muted();[stack addArrangedSubview:privacy];
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],[container.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],[container.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],[container.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],[container.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],[container.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],[outer.topAnchor constraintEqualToAnchor:container.topAnchor constant:20],[outer.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-28],[outer.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],[outer.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:28],[outer.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-28]]];self.maximumWidth=[outer.widthAnchor constraintEqualToConstant:MAX(1,MIN(440,self.view.bounds.size.width-56))];self.maximumWidth.active=YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(hideKey) name:UIApplicationWillResignActiveNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(revealInput) name:UIKeyboardDidChangeFrameNotification object:nil];
    std::lock_guard<std::mutex> lock(factsMutex);facts.oauthConfigured=self.config!=nil;
}
- (void)viewWillLayoutSubviews {[super viewWillLayoutSubviews];BOOL wide=self.view.bounds.size.width>self.view.bounds.size.height;self.heroWidth.active=NO;self.contentStack.axis=wide?UILayoutConstraintAxisHorizontal:UILayoutConstraintAxisVertical;self.contentStack.alignment=wide?UIStackViewAlignmentTop:UIStackViewAlignmentFill;self.maximumWidth.constant=MAX(1,MIN(wide?880:440,self.view.bounds.size.width-self.view.safeAreaInsets.left-self.view.safeAreaInsets.right-56));self.heroWidth.active=wide;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {return UIInterfaceOrientationMaskAllButUpsideDown;}
- (void)hideKey {self.field.secureTextEntry=YES;self.visibilityButton.accessibilityLabel=@"Show key";[self.visibilityButton setImage:[UIImage systemImageNamed:@"eye"] forState:UIControlStateNormal];}
- (void)toggleKeyVisibility {self.field.secureTextEntry=!self.field.secureTextEntry;self.visibilityButton.accessibilityLabel=self.field.secureTextEntry?@"Show key":@"Hide key";[self.visibilityButton setImage:[UIImage systemImageNamed:self.field.secureTextEntry?@"eye":@"eye.slash"] forState:UIControlStateNormal];}
- (void)revealInput {if(!self.field.isFirstResponder)return;[self.view layoutIfNeeded];CGRect field=[self.field convertRect:self.field.bounds toView:self.formScroll],button=[self.manualButton convertRect:self.manualButton.bounds toView:self.formScroll];[self.formScroll scrollRectToVisible:CGRectInset(CGRectUnion(field,button),0,-12) animated:YES];}
- (void)textFieldDidBeginEditing:(UITextField *)textField {(void)textField;[self revealInput];}
- (BOOL)textFieldShouldReturn:(UITextField *)textField {(void)textField;if(self.manualButton.enabled)[self submitManual];return YES;}
- (void)showError:(int32_t)local eos:(int32_t)eos {
    self.statusLabel.text=eos==3?@"A separate game account could not be created. Your existing progress has not been moved.":@"We couldn’t finish signing you in. Check your key, then try again.";
    self.statusLabel.textColor=[UIColor colorWithRed:1 green:0.48 blue:0.50 alpha:1];self.detailsLabel.text=[NSString stringWithFormat:@"Details · Status %d · EOS %d",local,eos];self.detailsLabel.hidden=NO;
}
- (void)openOwnershipLibrary {if(self.closed||self.pending||self.libraryButton.hidden)return;[UIApplication.sharedApplication openURL:OwnershipLibraryURL() options:@{} completionHandler:nil];}
- (void)setBusyUI:(BOOL)busy {BOOL canSubmit=!busy&&!self.completed&&self.submit!=nil;self.manualButton.enabled=canSubmit;self.savedButton.enabled=canSubmit;self.browserButton.enabled=canSubmit&&self.config!=nil;self.field.enabled=canSubmit;self.remember.enabled=canSubmit;self.visibilityButton.enabled=canSubmit;self.createProfileButton.enabled=self.pending&&self.awaitingNewProfile&&!self.newProfileConfirmed&&!self.closed;self.modalInPresentation=busy;self.navigationController.modalInPresentation=busy;{std::lock_guard<std::mutex> lock(factsMutex);facts.busy=busy;}}
- (void)cancelFlow {
    if(self.closed)return;self.closed=YES;if(!self.accepted)++self.generation;[self.webSession cancel];self.webSession=nil;[self.exchange cancel];self.exchange=nil;self.verifier=nil;self.state=nil;self.field.text=@"";[self hideKey];self.ownershipPending=NO;
    if(!self.accepted&&!self.completed){self.ownershipVerified=NO;[self clearNewProfilePhase];Wipe(self.pendingKey);self.pendingKey=nil;self.pending=NO;if(!self.cancelDelivered){self.cancelDelivered=YES;EHRItchSignInSubmit submit=self.submit;self.submit=nil;{std::lock_guard<std::mutex> lock(factsMutex);Increment(facts.cancelled);}Deliver(submit,nil);}}
    {std::lock_guard<std::mutex> lock(factsMutex);facts.visible=false;facts.busy=self.pending;facts.ownershipPending=false;facts.ownershipVerified=self.ownershipVerified;}
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];if(!self.pending&&currentController==self)currentController=nil;
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {(void)presentationController;[self cancelFlow];}
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)replacement {if(range.location>textField.text.length||range.length>textField.text.length-range.location||replacement.length>kKeyLimit)return NO;NSString *proposed=[textField.text stringByReplacingCharactersInRange:range withString:replacement];if(proposed.length>kKeyLimit)return NO;return proposed.length==0||ValidKey([proposed dataUsingEncoding:NSUTF8StringEncoding]);}
- (void)submitManual {if(self.field.text.length>kKeyLimit){self.field.text=@"";self.statusLabel.text=@"The key is too long.";return;}NSMutableData *key=[[self.field.text?:@"" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];[self handoff:key];Wipe(key);}
- (void)useSaved {NSMutableData *key=EHRItchSignInCopySavedKey();if(!key){self.statusLabel.text=@"No remembered key is available.";return;}[self handoff:key];Wipe(key);}
- (void)forgetSaved {if(self.pending)return;OSStatus status=ForgetKey();self.statusLabel.text=(status==errSecSuccess||status==errSecItemNotFound)?@"Remembered key removed.":@"The remembered key could not be removed.";std::lock_guard<std::mutex> lock(factsMutex);if(status==errSecSuccess||status==errSecItemNotFound)Increment(facts.forgotten);else Increment(facts.saveFailed);}
- (void)handoff:(NSMutableData *)key {
    if(self.pending||self.completed||self.closed)return;if(!ValidKey(key)){self.field.text=@"";self.statusLabel.text=@"Enter a key of at most 8192 ASCII bytes, without spaces or line breaks.";std::lock_guard<std::mutex> lock(factsMutex);Increment(facts.rejected);return;}
    [self clearNewProfilePhase];[self hideKey];self.ownershipVerified=NO;self.ownershipPending=YES;self.libraryButton.hidden=YES;self.detailsLabel.hidden=YES;self.statusLabel.textColor=Muted();self.pending=YES;self.rememberAttempt=self.remember.on;self.pendingKey=self.rememberAttempt?[key mutableCopy]:nil;self.field.text=@"";[self.field resignFirstResponder];[self setBusyUI:YES];self.statusLabel.text=OwnershipMessage(EHRItchOwnershipCancelled,true);
    {std::lock_guard<std::mutex> lock(factsMutex);Increment(facts.submitted);facts.completed=false;facts.resultKnown=false;facts.ownership=EHRItchOwnershipCancelled;facts.ownershipHTTP=0;facts.ownershipPending=true;facts.ownershipVerified=false;}
    uint64_t generation=++self.generation;__weak EHRItchSignInController *weak=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_SEC),dispatch_get_main_queue(),^{[weak expireGeneration:generation];});
    NSMutableData *payload=[key mutableCopy];BOOL threw=NO;try{@try{if(self.submit)self.submit(payload);else threw=YES;}@catch(NSException *error){(void)error;threw=YES;}}catch(...){threw=YES;}Wipe(payload);if(threw){[self receiveLocal:16 eos:0 completed:false];}
}
- (void)expireGeneration:(uint64_t)generation {if(!self.pending||self.generation!=generation)return;Wipe(self.pendingKey);self.pendingKey=nil;[self clearNewProfilePhase];if(self.accepted){self.pending=NO;[self setBusyUI:NO];self.statusLabel.text=@"Game sign-in completion was not confirmed. Any account prompts remain controlled by the game.";if(self.closed&&currentController==self)currentController=nil;}else [self cancelFlow];}
- (void)clearNewProfilePhase {
    self.confirmNewProfileAction=nil;self.awaitingNewProfile=NO;self.newProfileConfirmed=NO;self.createProfileButton.hidden=YES;self.createProfileButton.enabled=NO;
    std::lock_guard<std::mutex> lock(factsMutex);facts.awaitingNewProfile=false;facts.newProfileConfirmed=false;
}
- (void)showGameContinuation {
    self.accepted=YES;self.submit=nil;
    self.statusLabel.text=self.newProfileConfirmed?@"New game profile creation started; finish any account prompts in the game.":@"Credentials accepted; finish any account prompts in the game.";
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Continue to game" style:UIBarButtonItemStyleDone target:self action:@selector(cancelFlow)];self.navigationController.modalInPresentation=NO;
}
- (void)offerNewProfile:(int32_t (^)(void))confirm {
    if(!self.pending||!self.ownershipVerified||self.ownershipPending||self.accepted||self.completed||self.closed||self.awaitingNewProfile||self.newProfileConfirmed||!confirm)return;
    self.confirmNewProfileAction=[confirm copy];self.awaitingNewProfile=YES;self.detailsLabel.hidden=YES;self.statusLabel.textColor=UIColor.whiteColor;self.createProfileButton.hidden=NO;
    self.statusLabel.text=@"You’re nearly there. Create a separate game account for this itch.io identity. This does not link or merge accounts, or bring over existing progress.";
    {std::lock_guard<std::mutex> lock(factsMutex);facts.local=0;facts.eos=3;facts.resultKnown=true;facts.awaitingNewProfile=true;facts.newProfileConfirmed=false;}
    [self setBusyUI:YES];[self.view layoutIfNeeded];[self.formScroll scrollRectToVisible:[self.createProfileButton convertRect:self.createProfileButton.bounds toView:self.formScroll] animated:YES];
}
- (void)confirmNewProfile {
    if(!self.pending||!self.ownershipVerified||self.ownershipPending||!self.awaitingNewProfile||self.newProfileConfirmed||self.accepted||self.completed||self.closed||!self.confirmNewProfileAction)return;
    int32_t (^confirm)(void)=self.confirmNewProfileAction;self.confirmNewProfileAction=nil;self.awaitingNewProfile=NO;self.newProfileConfirmed=YES;self.createProfileButton.hidden=YES;self.createProfileButton.enabled=NO;
    self.statusLabel.text=@"Starting a new game profile…";
    {std::lock_guard<std::mutex> lock(factsMutex);facts.local=0;facts.eos=0;facts.resultKnown=false;facts.awaitingNewProfile=false;facts.newProfileConfirmed=true;}
    int32_t status=16;try{@try{status=confirm();}@catch(NSException *error){(void)error;}}catch(...){}
    if(self.closed||!self.pending)return;
    if(status){[self receiveLocal:status eos:3 completed:false];return;}
    if(!self.completed)[self showGameContinuation];
}
- (void)receiveLocal:(int32_t)local eos:(int32_t)eos completed:(bool)completed {
    if(!self.pending||(!local&&(!self.ownershipVerified||self.ownershipPending)))return;BOOL acceptedResult=eos==0||(eos==3&&self.newProfileConfirmed);BOOL full=FullResultAllowed(local,eos,completed,self.newProfileConfirmed,self.ownershipVerified);
    {std::lock_guard<std::mutex> lock(factsMutex);facts.local=local;facts.eos=eos;facts.completed=full;facts.resultKnown=true;}
    if(!local&&eos==3&&!completed&&self.awaitingNewProfile)return;
    if(!local&&acceptedResult&&!full){[self showGameContinuation];return;}
    self.pending=NO;self.completed=full;self.ownershipPending=NO;if(!full)self.ownershipVerified=NO;
    {std::lock_guard<std::mutex> lock(factsMutex);facts.ownershipPending=false;facts.ownershipVerified=self.ownershipVerified;}
    if(full){
        self.accepted=YES;self.submit=nil;self.confirmNewProfileAction=nil;self.awaitingNewProfile=NO;self.createProfileButton.hidden=YES;self.createProfileButton.enabled=NO;
        self.statusLabel.text=@"Signed in.";self.statusLabel.textColor=Accent();self.detailsLabel.hidden=YES;
        if(self.rememberAttempt&&self.pendingKey){OSStatus status=StoreKey(self.pendingKey);std::lock_guard<std::mutex> lock(factsMutex);if(status==errSecSuccess)Increment(facts.saved);else{Increment(facts.saveFailed);self.statusLabel.text=@"Signed in. The key could not be remembered on this device.";}}
        self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(cancelFlow)];
    } else {[self clearNewProfilePhase];[self showError:local eos:eos];}
    Wipe(self.pendingKey);self.pendingKey=nil;[self setBusyUI:NO];if(self.closed&&currentController==self)currentController=nil;
}
- (void)receiveOwnership:(EHRItchOwnershipStatus)status http:(int32_t)http pending:(bool)pending {
    if(!self.pending||self.closed||self.accepted||self.completed)return;
    status=BoundedOwnershipStatus(status);http=BoundedHTTPStatus(http);
    self.ownershipPending=pending;self.ownershipVerified=!pending&&status==EHRItchOwnershipVerified;
    {std::lock_guard<std::mutex> lock(factsMutex);facts.ownership=status;facts.ownershipHTTP=http;facts.ownershipPending=pending;facts.ownershipVerified=self.ownershipVerified;}
    self.statusLabel.text=OwnershipMessage(status,pending);self.detailsLabel.hidden=YES;self.libraryButton.hidden=pending||status!=EHRItchOwnershipNoEntitlement;
    if(pending||self.ownershipVerified){self.statusLabel.textColor=Muted();[self setBusyUI:YES];return;}
    ++self.generation;self.pending=NO;[self clearNewProfilePhase];Wipe(self.pendingKey);self.pendingKey=nil;
    self.statusLabel.textColor=[UIColor colorWithRed:1 green:0.48 blue:0.50 alpha:1];self.detailsLabel.text=[NSString stringWithFormat:@"Details · Ownership %d · HTTP %d",(int32_t)status,http];self.detailsLabel.hidden=NO;
    {std::lock_guard<std::mutex> lock(factsMutex);facts.completed=false;facts.resultKnown=false;}
    [self setBusyUI:NO];
}
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {(void)session;return self.view.window;}
- (void)startBrowser {
    if(!self.config||self.pending||self.closed)return;self.verifier=RandomValue();self.state=RandomValue();NSString *challenge=Challenge(self.verifier);NSURL *url=AuthorizationURL(self.config,self.state,challenge);
    if(!url){self.verifier=nil;self.state=nil;self.statusLabel.text=@"Browser sign-in is unavailable.";return;}[self setBusyUI:YES];uint64_t generation=++self.generation;__weak EHRItchSignInController *weak=self;
    self.webSession=[[ASWebAuthenticationSession alloc] initWithURL:url callbackURLScheme:self.config[@"scheme"] completionHandler:^(NSURL *callback,NSError *error){dispatch_async(dispatch_get_main_queue(),^{EHRItchSignInController *strong=weak;if(!strong||strong.closed||strong.generation!=generation)return;strong.webSession=nil;if(error&&error.code==ASWebAuthenticationSessionErrorCodeCanceledLogin){[strong cancelFlow];return;}NSString *code=error?nil:CallbackCode(callback,strong.config,strong.state);strong.state=nil;if(!code){strong.verifier=nil;[strong browserFailure:17];return;}NSMutableData *body=TokenBody(strong.config,code,strong.verifier);strong.verifier=nil;NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.itch.io/oauth/token"]];request.HTTPMethod=@"POST";[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];request.HTTPBody=[body copy];Wipe(body);strong.exchange=[EHRItchTokenExchange new];[strong.exchange start:request completion:^(NSMutableData *key,int32_t status){EHRItchSignInController *owner=weak;if(!owner||owner.closed||owner.generation!=generation)return;owner.exchange=nil;[owner setBusyUI:NO];if(status||!key){[owner browserFailure:status?status:18];return;}[owner handoff:key];}];});}];
    self.webSession.presentationContextProvider=self;self.webSession.prefersEphemeralWebBrowserSession=YES;
    {std::lock_guard<std::mutex> lock(factsMutex);Increment(facts.oauthStarted);}
    if(![self.webSession start]){self.webSession=nil;self.verifier=nil;self.state=nil;[self browserFailure:19];}
}
- (void)browserFailure:(int32_t)status {[self setBusyUI:NO];[self showError:status eos:-1];std::lock_guard<std::mutex> lock(factsMutex);Increment(facts.oauthFailed);facts.local=status;}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];Wipe(_pendingKey);}
@end
// Retire the form before deleting storage, including an already dismissed form
// still waiting for the original game's final callback. Never deliver another
// submit/cancel callback here: the provider's clearSession owns that operation.
static void RetireSignInForRemoval(void){
    EHRItchSignInController *controller=currentController;if(!controller)return;
    ++controller.generation;controller.closed=YES;controller.pending=NO;controller.ownershipPending=NO;controller.ownershipVerified=NO;controller.accepted=NO;controller.completed=NO;controller.cancelDelivered=YES;controller.submit=nil;
    [controller clearNewProfilePhase];controller.field.text=@"";[controller hideKey];Wipe(controller.pendingKey);controller.pendingKey=nil;
    [controller.webSession cancel];controller.webSession=nil;[controller.exchange cancel];controller.exchange=nil;controller.verifier=nil;controller.state=nil;currentController=nil;
    std::lock_guard<std::mutex> lock(factsMutex);facts.visible=false;facts.busy=false;facts.completed=false;facts.ownershipPending=false;facts.ownershipVerified=false;
}
@interface EHRItchAccountController:UIViewController
@property(nonatomic) BOOL fullGameCompleted,removing,removed;
@property(nonatomic) uint64_t actionGeneration;
@property(nonatomic,copy) int32_t (^clearSession)(void);
@property(nonatomic,copy) void (^signIn)(void);
@property(nonatomic,strong) UIButton *signInButton;
@property(nonatomic,strong) UILabel *messageLabel;
@property(nonatomic,strong) UILabel *detailsLabel;
@property(nonatomic,strong) UIButton *removeButton;
- (void)removeConfirmed;
@end
@implementation EHRItchAccountController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Account";self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;self.view=[[EHRAuthBackground alloc] initWithFrame:self.view.bounds];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=24;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    UIImageView *mark=BrandMark();mark.translatesAutoresizingMaskIntoConstraints=NO;UIView *markRow=[UIView new];[markRow addSubview:mark];[NSLayoutConstraint activateConstraints:@[[mark.widthAnchor constraintEqualToConstant:76],[mark.heightAnchor constraintEqualToConstant:76],[mark.centerXAnchor constraintEqualToAnchor:markRow.centerXAnchor],[mark.topAnchor constraintEqualToAnchor:markRow.topAnchor],[mark.bottomAnchor constraintEqualToAnchor:markRow.bottomAnchor]]];[stack addArrangedSubview:markRow];
    UILabel *title=Text(@"EHR Among Us",30,UIFontWeightBold);title.textAlignment=NSTextAlignmentCenter;[stack addArrangedSubview:title];
    UILabel *state=Text(self.fullGameCompleted?@"Signed in with itch.io":(self.signIn?@"Sign in to play":@"Sign-in settings"),20,UIFontWeightSemibold);state.textColor=self.fullGameCompleted?Accent():UIColor.whiteColor;state.textAlignment=NSTextAlignmentCenter;[stack addArrangedSubview:state];
    self.messageLabel=Text(@"Your saved login stays on this device. Removing it does not delete your game account, progress, or app data.",16,UIFontWeightRegular);self.messageLabel.textColor=Muted();if(!self.fullGameCompleted&&!self.signIn)self.messageLabel.text=@"Finish any account prompts in the game. If you removed your saved login, close and reopen EHR Among Us to sign in again.";[stack addArrangedSubview:self.messageLabel];
    if(!self.fullGameCompleted&&self.signIn){self.signInButton=StyledButton(@"Sign in",self,@selector(beginSignIn),YES);[stack addArrangedSubview:self.signInButton];}
    self.removeButton=StyledButton(@"Remove saved login",self,@selector(requestRemoval),NO);self.removeButton.tintColor=[UIColor colorWithRed:1 green:0.48 blue:0.50 alpha:1];UIButtonConfiguration *configuration=[self.removeButton.configuration copy];configuration.baseForegroundColor=self.removeButton.tintColor;configuration.baseBackgroundColor=[UIColor colorWithRed:0.30 green:0.10 blue:0.14 alpha:0.6];self.removeButton.configuration=configuration;[stack addArrangedSubview:self.removeButton];
    self.detailsLabel=Text(@"",12,UIFontWeightRegular);self.detailsLabel.hidden=YES;self.detailsLabel.textColor=Muted();[stack addArrangedSubview:self.detailsLabel];
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:24],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-28],[stack.centerXAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.centerXAnchor],[stack.widthAnchor constraintLessThanOrEqualToConstant:440],[stack.widthAnchor constraintLessThanOrEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-56]]];NSLayoutConstraint *width=[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-56];width.priority=UILayoutPriorityDefaultHigh;width.active=YES;
}
- (void)close {[self.navigationController dismissViewControllerAnimated:YES completion:nil];}
- (void)beginSignIn {if(self.removing||self.removed||self.fullGameCompleted||!self.signIn)return;void (^signIn)(void)=self.signIn;self.signIn=nil;self.signInButton.enabled=NO;const uint64_t generation=++self.actionGeneration;void (^deliver)(void)=^{if(self.removing||self.removed||self.actionGeneration!=generation)return;@try{try{signIn();}catch(...){}}@catch(__unused NSException *error){}};if(self.navigationController.presentingViewController)[self.navigationController dismissViewControllerAnimated:YES completion:deliver];else deliver();}
- (void)requestRemoval {
    if(self.removing||self.removed||self.presentedViewController)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Remove saved login?" message:@"You’ll need your itch.io key next time. Your game account and progress will not be deleted. Close and reopen EHR Among Us after removing it." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Keep login" style:UIAlertActionStyleCancel handler:nil]];
    __weak EHRItchAccountController *weak=self;[alert addAction:[UIAlertAction actionWithTitle:@"Remove login" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){[weak removeConfirmed];}]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)removeConfirmed {
    if(self.removing||self.removed)return;self.removing=YES;self.removeButton.enabled=NO;++self.actionGeneration;self.signIn=nil;self.signInButton.enabled=NO;
    RetireSignInForRemoval();const OSStatus deletion=ForgetKey();
    if(deletion!=errSecSuccess&&deletion!=errSecItemNotFound){self.messageLabel.text=@"Your saved login could not be removed. Try again after unlocking this device.";self.detailsLabel.text=[NSString stringWithFormat:@"Details · Keychain %d",(int)deletion];self.detailsLabel.hidden=NO;self.removing=NO;self.removeButton.enabled=YES;std::lock_guard<std::mutex> lock(factsMutex);Increment(facts.saveFailed);return;}
    self.removed=YES;int32_t status=16;int32_t (^clear)(void)=self.clearSession;self.clearSession=nil;try{@try{if(clear)status=clear();}@catch(__unused NSException *error){}}catch(...){}
    self.messageLabel.text=@"Saved login removed. Close and reopen EHR Among Us to sign in again. Your game account and progress have not been deleted.";[self.removeButton setTitle:@"Login removed" forState:UIControlStateNormal];UIButtonConfiguration *configuration=[self.removeButton.configuration copy];configuration.title=@"Login removed";self.removeButton.configuration=configuration;self.removeButton.accessibilityLabel=@"Login removed";
    self.detailsLabel.hidden=status==0;if(status)self.detailsLabel.text=[NSString stringWithFormat:@"Details · Status %d. Reopen the app to finish.",status];
    std::lock_guard<std::mutex> lock(factsMutex);Increment(facts.forgotten);
}
@end
void EHRItchSignInPresentAccount(UIViewController *presenter,bool fullGameCompleted,int32_t (^clearSession)(void),void (^signIn)(void)){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{EHRItchSignInPresentAccount(presenter,fullGameCompleted,clearSession,signIn);});return;}
    if(!presenter||!clearSession||presenter.presentedViewController)return;EHRItchAccountController *controller=[EHRItchAccountController new];controller.fullGameCompleted=fullGameCompleted;controller.clearSession=[clearSession copy];controller.signIn=[signIn copy];UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:controller];StyleNavigation(navigation);navigation.modalPresentationStyle=UIModalPresentationFormSheet;[presenter presentViewController:navigation animated:YES completion:nil];
}
void EHRItchSignInPresent(UIViewController *presenter,EHRItchSignInSubmit submit){if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{EHRItchSignInPresent(presenter,submit);});return;}if(!presenter||!submit||currentController||presenter.presentedViewController){Deliver(submit,nil);return;}EHRItchSignInController *controller=[EHRItchSignInController new];controller.submit=submit;currentController=controller;UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:controller];navigation.modalPresentationStyle=UIModalPresentationFullScreen;StyleNavigation(navigation);navigation.presentationController.delegate=controller;{std::lock_guard<std::mutex> lock(factsMutex);Increment(facts.presented);facts.visible=true;facts.completed=false;facts.local=0;facts.eos=0;facts.resultKnown=false;facts.awaitingNewProfile=false;facts.newProfileConfirmed=false;facts.ownership=EHRItchOwnershipCancelled;facts.ownershipHTTP=0;facts.ownershipPending=false;facts.ownershipVerified=false;}[presenter presentViewController:navigation animated:YES completion:nil];}
void EHRItchSignInUpdateOwnership(EHRItchOwnershipStatus status,int32_t httpStatus,bool pending){void(^update)(void)=^{[currentController receiveOwnership:status http:httpStatus pending:pending];};if(NSThread.isMainThread)update();else dispatch_async(dispatch_get_main_queue(),update);}
void EHRItchSignInOfferNewProfile(int32_t (^confirm)(void)){void(^offer)(void)=^{[currentController offerNewProfile:confirm];};if(NSThread.isMainThread)offer();else dispatch_async(dispatch_get_main_queue(),offer);}
void EHRItchSignInUpdateResult(int32_t localStatus,int32_t eosResult,bool fullGameCompleted){void(^update)(void)=^{[currentController receiveLocal:localStatus eos:eosResult completed:fullGameCompleted];};if(NSThread.isMainThread)update();else dispatch_async(dispatch_get_main_queue(),update);}
#endif
