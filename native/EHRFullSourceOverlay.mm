#import <UIKit/UIKit.h>
#import "EHRFullSourceRuntime.h"
#import "EHRExportSharing.h"

@interface EHRFullStatusWindow:UIWindow
@end
@implementation EHRFullStatusWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event];
    return hit==self||hit==self.rootViewController.view?nil:hit;
}
@end
@interface EHRFullStatusPanel:NSObject
@property(nonatomic,strong) EHRFullStatusWindow *window;
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) UIScrollView *statusScroll;
@property(nonatomic,strong) UIButton *exportsButton;
@end
@implementation EHRFullStatusPanel
- (void)toggle {self.panel.hidden=!self.panel.hidden;[self refresh];}
- (void)shareExports {
    if(self.window.rootViewController.presentedViewController)return;
    [self.window.rootViewController presentViewController:EHRExportSharingController() animated:YES completion:nil];
}
- (void)install {
    UIWindowScene *scene=nil;
    for(UIScene *candidate in UIApplication.sharedApplication.connectedScenes)
        if([candidate isKindOfClass:UIWindowScene.class]&&candidate.activationState==UISceneActivationStateForegroundActive){scene=(UIWindowScene *)candidate;break;}
    if(!scene)return;
    self.window=[[EHRFullStatusWindow alloc] initWithWindowScene:scene];self.window.backgroundColor=UIColor.clearColor;
    self.window.windowLevel=UIWindowLevelNormal+2;self.window.rootViewController=[UIViewController new];
    self.window.rootViewController.view.backgroundColor=UIColor.clearColor;
    self.button=[UIButton buttonWithType:UIButtonTypeSystem];self.button.backgroundColor=[UIColor colorWithWhite:0.06 alpha:0.9];
    self.button.tintColor=UIColor.cyanColor;self.button.layer.cornerRadius=9;self.button.accessibilityLabel=@"EHR startup status";
    [self.button addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.window.rootViewController.view addSubview:self.button];
    self.panel=[UIView new];self.panel.backgroundColor=[UIColor colorWithWhite:0.06 alpha:0.96];self.panel.layer.cornerRadius=12;self.panel.hidden=YES;
    [self.window.rootViewController.view addSubview:self.panel];
    self.label=[UILabel new];self.label.numberOfLines=0;self.label.textColor=UIColor.whiteColor;self.label.font=[UIFont systemFontOfSize:14];
    self.statusScroll=[UIScrollView new];[self.panel addSubview:self.statusScroll];[self.statusScroll addSubview:self.label];
    self.exportsButton=[UIButton buttonWithType:UIButtonTypeSystem];self.exportsButton.tintColor=UIColor.cyanColor;
    [self.exportsButton setTitle:@"Share exports" forState:UIControlStateNormal];self.exportsButton.accessibilityLabel=@"Share EHR log and translation exports";
    [self.exportsButton addTarget:self action:@selector(shareExports) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.exportsButton];self.window.hidden=NO;[self refresh];
    [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}
- (void)refresh {
    UIEdgeInsets safe=self.window.safeAreaInsets;CGSize size=self.window.bounds.size;
    CGFloat width=MIN(360,size.width-safe.left-safe.right-24),right=size.width-safe.right-12;
    self.button.frame=CGRectMake(right-132,safe.top+10,132,44);
    self.panel.frame=CGRectMake(right-width,safe.top+62,width,MIN(360,size.height-safe.top-safe.bottom-74));
    self.statusScroll.frame=CGRectMake(14,12,MAX(0,self.panel.bounds.size.width-28),MAX(0,self.panel.bounds.size.height-80));
    self.exportsButton.frame=CGRectMake(14,self.panel.bounds.size.height-56,self.panel.bounds.size.width-28,44);
    NSDictionary *status=EHRFullSourceCopyRuntimeStatus(),*app=status[@"application"]?:@{},*info=NSBundle.mainBundle.infoDictionary;
    BOOL active=[app[@"state"] unsignedIntValue]==3,loaded=[app[@"optionsLoaded"] boolValue];
    NSString *title=active?(loaded?@"EHR running":@"EHR loading roles"):[status[@"attempted"] boolValue]?@"EHR status":@"EHR starting";
    [self.button setTitle:title forState:UIControlStateNormal];
    NSString *message=active?(loaded?@"EHR options are initialized. Open the game settings and EHR controls to playtest.":@"Waiting for the game's role and option initialization."):
        [NSString stringWithFormat:@"Startup: %@\nStatus: %@",status[@"stage"]?:@"waiting for game startup",status[@"status"]?:@1];
    self.label.text=[NSString stringWithFormat:@"EHR %@ · iPhone %@ (%@)\nGame %@\n\n%@\n\nUse a separate test account. Account linking, progress preservation and online play have not been verified.\n\nIndependent port; not endorsed by Innersloth.",
        info[@"EHRSourceVersion"]?:@"?",info[@"CFBundleShortVersionString"]?:@"?",info[@"CFBundleVersion"]?:@"?",info[@"EHRReferenceGameVersion"]?:@"?",message];
    CGSize textSize=[self.label sizeThatFits:CGSizeMake(self.statusScroll.bounds.size.width,CGFLOAT_MAX)];
    self.label.frame=CGRectMake(0,0,self.statusScroll.bounds.size.width,textSize.height);self.statusScroll.contentSize=self.label.bounds.size;
}
@end
__attribute__((constructor)) static void EHRFullStatusLoad(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        static EHRFullStatusPanel *panel;panel=[EHRFullStatusPanel new];[panel install];
    });
}
