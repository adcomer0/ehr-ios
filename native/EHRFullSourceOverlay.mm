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
@class EHRFullStatusPanel;
@interface EHRFullStatusController:UIViewController
@property(nonatomic,weak) EHRFullStatusPanel *statusPanel;
@end
@interface EHRFullStatusPanel:NSObject
@property(nonatomic,strong) EHRFullStatusWindow *window;
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) UIScrollView *statusScroll;
@property(nonatomic,strong) UIButton *exportsButton;
@property(nonatomic) CGPoint badgePosition;
@property(nonatomic) CGPoint dragOrigin;
- (void)layoutOverlay;
@end
@implementation EHRFullStatusController
- (void)viewDidLayoutSubviews {[super viewDidLayoutSubviews];[self.statusPanel layoutOverlay];}
- (void)viewSafeAreaInsetsDidChange {[super viewSafeAreaInsetsDidChange];[self.statusPanel layoutOverlay];}
@end
@implementation EHRFullStatusPanel
- (void)toggle {self.panel.hidden=!self.panel.hidden;[self refresh];}
- (void)dragBadge:(UIPanGestureRecognizer *)gesture {
    if(gesture.state==UIGestureRecognizerStateBegan){
        self.dragOrigin=self.button.frame.origin;
        self.panel.hidden=YES;
    }
    if(gesture.state!=UIGestureRecognizerStateBegan&&gesture.state!=UIGestureRecognizerStateChanged&&gesture.state!=UIGestureRecognizerStateEnded)return;
    UIView *root=self.window.rootViewController.view;
    CGRect safe=CGRectInset(UIEdgeInsetsInsetRect(root.bounds,root.safeAreaInsets),12,10);
    CGPoint translation=[gesture translationInView:root];
    CGFloat travelX=MAX(0,safe.size.width-self.button.bounds.size.width);
    CGFloat travelY=MAX(0,safe.size.height-self.button.bounds.size.height);
    self.badgePosition=CGPointMake(travelX>0?MAX(0,MIN(1,(self.dragOrigin.x+translation.x-CGRectGetMinX(safe))/travelX)):0.5,
                                  travelY>0?MAX(0,MIN(1,(self.dragOrigin.y+translation.y-CGRectGetMinY(safe))/travelY)):0);
    [self layoutOverlay];
}
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
    self.window.windowLevel=UIWindowLevelNormal+2;
    EHRFullStatusController *controller=[EHRFullStatusController new];controller.statusPanel=self;
    self.window.rootViewController=controller;
    self.window.rootViewController.view.backgroundColor=UIColor.clearColor;
    self.button=[UIButton buttonWithType:UIButtonTypeSystem];self.button.backgroundColor=[UIColor colorWithWhite:0.06 alpha:0.9];
    self.button.tintColor=UIColor.cyanColor;self.button.layer.cornerRadius=9;self.button.accessibilityLabel=@"EHR startup status";
    self.badgePosition=CGPointMake(0.5,0);
    [self.button setTitle:@"EHR" forState:UIControlStateNormal];
    self.button.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    self.button.accessibilityHint=@"Tap for status and exports. Drag to move.";
    UIPanGestureRecognizer *drag=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragBadge:)];
    drag.cancelsTouchesInView=YES;[self.button addGestureRecognizer:drag];
    [self.button addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.window.rootViewController.view addSubview:self.button];
    self.panel=[UIView new];self.panel.backgroundColor=[UIColor colorWithWhite:0.06 alpha:0.96];self.panel.layer.cornerRadius=12;self.panel.hidden=YES;
    [self.window.rootViewController.view addSubview:self.panel];
    self.label=[UILabel new];self.label.numberOfLines=0;self.label.textColor=UIColor.whiteColor;self.label.font=[UIFont systemFontOfSize:14];
    self.statusScroll=[UIScrollView new];[self.panel addSubview:self.statusScroll];[self.statusScroll addSubview:self.label];
    self.exportsButton=[UIButton buttonWithType:UIButtonTypeSystem];self.exportsButton.tintColor=UIColor.cyanColor;
    [self.exportsButton setTitle:@"Share exports" forState:UIControlStateNormal];self.exportsButton.accessibilityLabel=@"Share EHR log and translation exports";
    [self.exportsButton addTarget:self action:@selector(shareExports) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.exportsButton];self.window.hidden=NO;[self layoutOverlay];[self refresh];
    [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}
- (void)layoutOverlay {
    if(!self.button||!self.panel)return;
    UIView *root=self.window.rootViewController.view;
    CGRect safe=CGRectInset(UIEdgeInsetsInsetRect(root.bounds,root.safeAreaInsets),12,10);
    CGFloat width=MAX(0,MIN(64,safe.size.width)),height=MAX(0,MIN(44,safe.size.height));
    self.button.frame=CGRectMake(CGRectGetMinX(safe)+MAX(0,safe.size.width-width)*self.badgePosition.x,
                                CGRectGetMinY(safe)+MAX(0,safe.size.height-height)*self.badgePosition.y,width,height);
    CGFloat panelWidth=MAX(0,MIN(360,safe.size.width));
    CGFloat below=MAX(0,CGRectGetMaxY(safe)-CGRectGetMaxY(self.button.frame)-8);
    CGFloat above=MAX(0,CGRectGetMinY(self.button.frame)-CGRectGetMinY(safe)-8);
    BOOL placeBelow=below>=above;
    CGFloat panelHeight=MIN(360,placeBelow?below:above);
    CGFloat panelX=MAX(CGRectGetMinX(safe),MIN(CGRectGetMaxX(safe)-panelWidth,CGRectGetMidX(self.button.frame)-panelWidth/2));
    self.panel.frame=CGRectMake(panelX,placeBelow?CGRectGetMaxY(self.button.frame)+8:CGRectGetMinY(self.button.frame)-8-panelHeight,panelWidth,panelHeight);
    self.statusScroll.frame=CGRectMake(14,12,MAX(0,self.panel.bounds.size.width-28),MAX(0,self.panel.bounds.size.height-80));
    self.exportsButton.frame=CGRectMake(14,MAX(0,self.panel.bounds.size.height-56),MAX(0,self.panel.bounds.size.width-28),MIN(44,self.panel.bounds.size.height));
    CGSize textSize=[self.label sizeThatFits:CGSizeMake(self.statusScroll.bounds.size.width,CGFLOAT_MAX)];
    self.label.frame=CGRectMake(0,0,self.statusScroll.bounds.size.width,textSize.height);self.statusScroll.contentSize=self.label.bounds.size;
}
- (void)refresh {
    NSDictionary *status=EHRFullSourceCopyRuntimeStatus(),*app=status[@"application"]?:@{},*info=NSBundle.mainBundle.infoDictionary;
    BOOL active=[app[@"state"] unsignedIntValue]==3,loaded=[app[@"optionsLoaded"] boolValue];
    NSString *title=active?(loaded?@"EHR running":@"EHR loading roles"):[status[@"attempted"] boolValue]?@"EHR status":@"EHR starting";
    self.button.accessibilityValue=title;
    NSString *message=active?(loaded?@"EHR options are initialized. Open the game settings and EHR controls to playtest.":@"Waiting for the game's role and option initialization."):
        [NSString stringWithFormat:@"Startup: %@\nStatus: %@",status[@"stage"]?:@"waiting for game startup",status[@"status"]?:@1];
    self.label.text=[NSString stringWithFormat:@"EHR %@ · iPhone %@ (%@)\nGame %@\n\n%@\n%@\n\nUse a separate test account. Account linking, progress preservation and online play have not been verified.\n\nIndependent port; not endorsed by Innersloth.",
        info[@"EHRSourceVersion"]?:@"?",info[@"CFBundleShortVersionString"]?:@"?",info[@"CFBundleVersion"]?:@"?",info[@"EHRReferenceGameVersion"]?:@"?",title,message];
    CGSize textSize=[self.label sizeThatFits:CGSizeMake(self.statusScroll.bounds.size.width,CGFLOAT_MAX)];
    self.label.frame=CGRectMake(0,0,self.statusScroll.bounds.size.width,textSize.height);self.statusScroll.contentSize=self.label.bounds.size;
}
@end
__attribute__((constructor)) static void EHRFullStatusLoad(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        static EHRFullStatusPanel *panel;panel=[EHRFullStatusPanel new];[panel install];
    });
}
