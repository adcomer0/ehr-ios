#import <UIKit/UIKit.h>
#import "EHRLiveBridge.h"
#import "EHRNativeHooks.h"

@interface EHRPassThroughView : UIView
@end
@implementation EHRPassThroughView
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *hit = [super hitTest:p withEvent:e]; return hit == self ? nil : hit;
}
@end
@interface EHRPassThroughWindow : UIWindow
@end
@implementation EHRPassThroughWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *hit = [super hitTest:p withEvent:e];
    return hit == self || hit == self.rootViewController.view ? nil : hit;
}
@end

@interface EHRNativePanel : NSObject
@property(nonatomic, strong) EHRPassThroughWindow *window;
@property(nonatomic, strong) UIViewController *controller;
@property(nonatomic, strong) UILabel *label, *minimumLabel, *maximumLabel;
@property(nonatomic, strong) UIButton *button, *playerButton;
@property(nonatomic, strong) UIScrollView *panel;
@property(nonatomic, strong) UIStackView *stack;
@property(nonatomic, strong) UISwitch *enabled;
@property(nonatomic, strong) UIStepper *minimum, *maximum;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) int selectedPlayerId;
@end
@implementation EHRNativePanel
- (void)toggle { self.panel.hidden = !self.panel.hidden; }
- (UILabel *)text:(NSString *)text {
    UILabel *label = [UILabel new]; label.text = text; label.textColor = UIColor.whiteColor;
    label.numberOfLines = 0; label.font = [UIFont systemFontOfSize:13]; return label;
}
- (UIView *)row:(UIView *)left control:(UIView *)right {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[left, right]];
    row.axis = UILayoutConstraintAxisHorizontal; row.alignment = UIStackViewAlignmentCenter; row.spacing = 12;
    [right setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal]; return row;
}
- (void)applySettings {
    if (self.enabled.on && self.selectedPlayerId < 0) self.enabled.on = NO;
    int accepted = EHRLiveBridgeConfigureBait(self.enabled.on ? 1 : 0, self.selectedPlayerId,
                                            (int)self.minimum.value, (int)self.maximum.value);
    if (!accepted) self.enabled.on = NO;
    self.minimumLabel.text = [NSString stringWithFormat:@"Minimum delay: %.0f s", self.minimum.value];
    self.maximumLabel.text = [NSString stringWithFormat:@"Maximum delay: %.0f s", self.maximum.value];
    [self refresh];
}
- (void)choosePlayer {
    NSDictionary *snapshot = EHRLiveBridgeSampleNow();
    NSArray *players = [snapshot[@"players"] isKindOfClass:NSArray.class] ? snapshot[@"players"] : @[];
    UIAlertController *choice = [UIAlertController alertControllerWithTitle:@"Choose the Bait player"
        message:@"Manual assignment for this preview. The rule runs only while you host an active game."
        preferredStyle:UIAlertControllerStyleAlert];
    for (id value in players) {
        if (![value isKindOfClass:NSDictionary.class] || ![value[@"playerId"] isKindOfClass:NSNumber.class]) continue;
        int playerId = [value[@"playerId"] intValue]; if (playerId < 0 || playerId > 253) continue;
        NSString *name = [value[@"name"] isKindOfClass:NSString.class] ? value[@"name"] : @"Player";
        NSString *title = [NSString stringWithFormat:@"%@ · ID %d", name, playerId];
        [choice addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            self.selectedPlayerId = playerId; [self applySettings];
        }]];
    }
    [choice addAction:[UIAlertAction actionWithTitle:@"Clear assignment" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        self.enabled.on = NO; self.selectedPlayerId = -1; [self applySettings];
    }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.controller presentViewController:choice animated:YES completion:nil];
}
- (void)install {
    self.selectedPlayerId = -1; UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate; break;
        }
    }
    self.window = scene ? [[EHRPassThroughWindow alloc] initWithWindowScene:scene] :
                         [[EHRPassThroughWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.controller = [UIViewController new];
    EHRPassThroughView *root = [[EHRPassThroughView alloc] initWithFrame:self.window.bounds];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    root.backgroundColor = UIColor.clearColor; self.controller.view = root;
    self.window.rootViewController = self.controller; self.window.windowLevel = UIWindowLevelAlert + 10;
    self.window.backgroundColor = UIColor.clearColor;
    self.button = [UIButton buttonWithType:UIButtonTypeSystem];
    self.button.backgroundColor = [UIColor colorWithRed:0.03 green:0.25 blue:0.28 alpha:0.95]; self.button.layer.cornerRadius = 10;
    [self.button setTitle:@"EHR · MODDED" forState:UIControlStateNormal];
    [self.button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; self.button.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.button.accessibilityLabel = @"EHR mod settings";
    [self.button addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside]; [root addSubview:self.button];
    self.panel = [UIScrollView new]; self.panel.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.96];
    self.panel.layer.cornerRadius = 12; self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithRed:0.2 green:0.9 blue:0.8 alpha:0.8].CGColor; [root addSubview:self.panel];
    self.stack = [UIStackView new]; self.stack.axis = UILayoutConstraintAxisVertical; self.stack.spacing = 12;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO; [self.panel addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.stack.topAnchor constraintEqualToAnchor:self.panel.contentLayoutGuide.topAnchor constant:14],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.panel.contentLayoutGuide.bottomAnchor constant:-14],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.panel.contentLayoutGuide.leadingAnchor constant:14],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.panel.contentLayoutGuide.trailingAnchor constant:-14],
        [self.stack.widthAnchor constraintEqualToAnchor:self.panel.frameLayoutGuide.widthAnchor constant:-28]
    ]];
    [self.stack addArrangedSubview:[self text:@"BAIT · NATIVE PREVIEW\nManual assignment. Full EHR roles are not available."]];
    self.playerButton = [UIButton buttonWithType:UIButtonTypeSystem]; self.playerButton.titleLabel.numberOfLines = 2;
    self.playerButton.accessibilityLabel = @"Choose Bait player"; [self.playerButton setTitleColor:UIColor.cyanColor forState:UIControlStateNormal];
    [self.playerButton addTarget:self action:@selector(choosePlayer) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:self.playerButton]; self.enabled = [UISwitch new];
    [self.enabled addTarget:self action:@selector(applySettings) forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:[self row:[self text:@"Enable Bait auto-report"] control:self.enabled]];
    self.minimum = [UIStepper new]; self.maximum = [UIStepper new];
    self.minimumLabel = [self text:@"Minimum delay: 0 s"]; self.maximumLabel = [self text:@"Maximum delay: 0 s"];
    for (UIStepper *stepper in @[self.minimum, self.maximum]) {
        stepper.minimumValue = 0; stepper.maximumValue = 90; stepper.stepValue = 1;
        [stepper addTarget:self action:@selector(applySettings) forControlEvents:UIControlEventValueChanged];
    }
    self.minimum.accessibilityLabel = @"Bait minimum delay seconds"; self.maximum.accessibilityLabel = @"Bait maximum delay seconds";
    [self.stack addArrangedSubview:[self row:self.minimumLabel control:self.minimum]];
    [self.stack addArrangedSubview:[self row:self.maximumLabel control:self.maximum]];
    [self.stack addArrangedSubview:[self text:@"A zero delay or reversed range uses 150 ms. Meetings, host loss, a new round, or settings changes cancel pending reports."]];
    self.label = [self text:@""]; self.label.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    [self.stack addArrangedSubview:self.label]; self.window.hidden = NO;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes]; [self refresh];
}
- (void)refresh {
    CGFloat inset = MAX(self.window.safeAreaInsets.left + 8, 12), top = MAX(self.window.safeAreaInsets.top + 8, 12);
    self.button.frame = CGRectMake(inset, top, 136, 34);
    self.panel.frame = CGRectMake(inset, top + 42, MIN(390, self.window.bounds.size.width - inset - 12),
                                  MAX(100, self.window.bounds.size.height - top - 54 - self.window.safeAreaInsets.bottom));
    NSDictionary *snapshot = EHRLiveBridgeCopySnapshot(), *bait = EHRLiveBridgeCopyBaitStatus(), *hooks = EHRNativeHooksCopyStatus();
    NSDictionary *client = [snapshot[@"client"] isKindOfClass:NSDictionary.class] ? snapshot[@"client"] : @{};
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *selected = self.selectedPlayerId < 0 ? @"Choose a Bait player" : [NSString stringWithFormat:@"Bait: player ID %d", self.selectedPlayerId];
    NSArray *players = [snapshot[@"players"] isKindOfClass:NSArray.class] ? snapshot[@"players"] : @[];
    for (id player in players) {
        if ([player isKindOfClass:NSDictionary.class] && [player[@"playerId"] isKindOfClass:NSNumber.class] &&
            [player[@"playerId"] intValue] == self.selectedPlayerId && [player[@"name"] isKindOfClass:NSString.class]) {
            selected = [NSString stringWithFormat:@"Bait: %@ · ID %d", player[@"name"], self.selectedPlayerId]; break;
        }
    }
    [self.playerButton setTitle:selected forState:UIControlStateNormal]; self.enabled.enabled = self.selectedPlayerId >= 0;
    NSDictionary *last = [bait[@"lastEvent"] isKindOfClass:NSDictionary.class] ? bait[@"lastEvent"] : @{};
    NSString *host = [client[@"amHost"] isKindOfClass:NSNumber.class] ? ([client[@"amHost"] boolValue] ? @"yes" : @"no") : @"waiting";
    self.label.text = [NSString stringWithFormat:@"Version %@ (%@) · game %@\nRuntime: %@ · host: %@\nKill callbacks: %@\nConfirmed callback observed: %@\nPending reports: %@ · completed calls: %@\n%@\n%@",
        info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?", info[@"EHRReferenceGameVersion"] ?: @"?",
        snapshot[@"status"] ?: @"waiting", host, hooks[@"murderCallbacks"] ?: @0,
        [bait[@"callbackObserved"] boolValue] ? @"yes" : @"waiting", bait[@"pendingReports"] ?: @0, bait[@"reportCallsCompleted"] ?: @0,
        last[@"outcome"] ?: @"No kill callback observed", last[@"reason"] ?: @""];
    NSMutableDictionary *evidence = [snapshot mutableCopy]; evidence[@"nativeHooks"] = hooks; evidence[@"bait"] = bait;
    NSData *data = [NSJSONSerialization dataWithJSONObject:evidence options:NSJSONWritingPrettyPrinted error:nil];
    if (data) {
        NSURL *cache = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
        [data writeToURL:[cache URLByAppendingPathComponent:@"EHRLiveBridge.json"] atomically:YES];
    }
}
@end
__attribute__((constructor)) static void EHRNativeOverlayLoad(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        EHRLiveBridgeStart(); static EHRNativePanel *panel; panel = [EHRNativePanel new]; [panel install];
    });
}
