#import "EHROwnershipCover.h"
#import "EHRItchAuthProvider.h"
#import "EHRItchOwnership.h"

@interface EHROwnershipCover ()
@property(nonatomic,strong) UIImageView *brand;
@property(nonatomic,strong) UILabel *heading;
@property(nonatomic,strong) UILabel *message;
@property(nonatomic,strong) UILabel *footnote;
@property(nonatomic,strong) UIButton *signIn;
@property(nonatomic,strong) UIButton *account;
@property(nonatomic,strong) UIButton *store;
@end

@implementation EHROwnershipCover
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    self.backgroundColor=[UIColor colorWithRed:0.025 green:0.045 blue:0.10 alpha:1];
    self.accessibilityViewIsModal=YES;
    self.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    self.brand=[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"EHRBrandIcon"]];
    self.brand.contentMode=UIViewContentModeScaleAspectFit;self.brand.isAccessibilityElement=NO;
    self.heading=[UILabel new];self.heading.text=@"Among Us ownership required";
    self.heading.textColor=UIColor.whiteColor;self.heading.font=[UIFont boldSystemFontOfSize:26];
    self.message=[UILabel new];self.message.textColor=[UIColor colorWithWhite:0.82 alpha:1];self.message.font=[UIFont systemFontOfSize:16];
    self.footnote=[UILabel new];self.footnote.textColor=[UIColor colorWithWhite:0.66 alpha:1];self.footnote.font=[UIFont systemFontOfSize:13];
    self.footnote.text=@"Use the itch.io account that owns or has claimed Among Us. A purchase on another store does not establish ownership in your itch.io library.";
    for(UILabel *label in @[self.heading,self.message,self.footnote]){label.numberOfLines=0;label.textAlignment=NSTextAlignmentCenter;}
    self.signIn=[self button:@"Sign in with itch.io" action:@selector(openSignIn)];
    self.account=[self button:@"Account and saved login" action:@selector(openAccount)];
    self.store=[self button:@"Among Us on itch.io" action:@selector(openStore)];
    self.signIn.backgroundColor=[UIColor colorWithRed:0.18 green:0.84 blue:0.96 alpha:1];self.signIn.tintColor=[UIColor colorWithWhite:0.04 alpha:1];self.signIn.layer.cornerRadius=12;
    for(UIView *view in @[self.brand,self.heading,self.message,self.signIn,self.account,self.store,self.footnote])[self addSubview:view];
    [self refreshOwnership];return self;
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];button.tintColor=UIColor.cyanColor;
    [button setTitle:title forState:UIControlStateNormal];button.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return button;
}
- (void)openSignIn {EHRItchAuthProviderPresent();}
- (void)openAccount {EHRItchAuthProviderPresentAccount();}
- (void)openStore {[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://innersloth.itch.io/among-us"] options:@{} completionHandler:nil];}
- (void)refreshOwnership {
    self.hidden=!EHRItchAuthProviderSelected()||EHRItchAuthProviderOwnershipVerified();
    if(self.hidden)return;
    NSDictionary *status=EHRItchAuthProviderCopyStatus();
    const BOOL pending=[status[@"ownershipPending"] boolValue];
    self.signIn.enabled=!pending;
    self.heading.text=pending?@"Checking your itch.io library":@"Among Us ownership required";
    if(pending)self.message.text=@"Verifying that this itch.io account owns Among Us. This does not purchase or download the game.";
    else if([status[@"clearedForRestart"] boolValue])self.message.text=@"Saved login removed. Close and reopen EHR Among Us to enter another key.";
    else if(![status[@"ownershipChecks"] unsignedLongLongValue])self.message.text=@"Sign in with your itch.io API key to verify ownership before using EHR Among Us.";
    else switch([status[@"ownershipStatus"] intValue]){
        case EHRItchOwnershipNoEntitlement:self.message.text=@"Among Us was not found in this account’s claimed library. Check the account, claim an existing bundle or gift purchase, or obtain the game on itch.io, then retry.";break;
        case EHRItchOwnershipInvalidCredential:case EHRItchOwnershipBadCredentialFormat:self.message.text=@"The itch.io key could not be accepted. Enter a valid key for the account that owns Among Us.";break;
        case EHRItchOwnershipInsufficientScope:self.message.text=@"This credential cannot read owned games. Authorize library access or use a personal key from your itch.io account.";break;
        case EHRItchOwnershipCancelled:self.message.text=@"Ownership verification was cancelled. Sign in to continue.";break;
        default:self.message.text=@"Ownership could not be verified. Check your connection and retry. This does not mean your purchase is missing.";break;
    }
    if([status[@"clearedForRestart"] boolValue])self.signIn.enabled=NO;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width=MAX(0,MIN(480,self.bounds.size.width-48));CGFloat x=(self.bounds.size.width-width)/2;
    CGFloat y=self.safeAreaInsets.top+24;
    self.brand.frame=CGRectMake((self.bounds.size.width-80)/2,y,80,80);y+=100;
    for(UILabel *label in @[self.heading,self.message]){
        CGFloat height=[label sizeThatFits:CGSizeMake(width,CGFLOAT_MAX)].height;
        label.frame=CGRectMake(x,y,width,height);y+=height+18;
    }
    for(UIButton *button in @[self.signIn,self.account,self.store]){button.frame=CGRectMake(x,y,width,52);y+=64;}
    CGFloat height=[self.footnote sizeThatFits:CGSizeMake(width,CGFLOAT_MAX)].height;
    self.footnote.frame=CGRectMake(x,y,width,height);y+=height+24+self.safeAreaInsets.bottom;
    self.contentSize=CGSizeMake(self.bounds.size.width,MAX(self.bounds.size.height,y));
}
@end
