#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include "EHRTouchUI.h"
#include "EHRKeyboardViewport.hpp"
#include <cmath>
#include <cstring>

static UIColor *Color(EHRTouchColor c) {
  return [UIColor colorWithRed:c.r green:c.g blue:c.b alpha:c.a];
}
static EHRTouchColor Tinted(EHRTouchColor c, EHRTouchColor tint) {
  c.r *= tint.r;
  c.g *= tint.g;
  c.b *= tint.b;
  return c; // Tint alpha is applied once to the containing view.
}
static BOOL Finite(float x) { return std::isfinite(x); }
static BOOL ValidRect(EHRTouchRect r) {
  return Finite(r.x) && Finite(r.y) && Finite(r.width) && Finite(r.height) && r.width >= 0 &&
         r.height >= 0 && fabs(r.x) < 1000000 && fabs(r.y) < 1000000 && r.width < 1000000 &&
         r.height < 1000000;
}
static BOOL ValidColor(EHRTouchColor c) {
  return Finite(c.r) && Finite(c.g) && Finite(c.b) && Finite(c.a) && c.r >= 0 && c.r <= 1 &&
         c.g >= 0 && c.g <= 1 && c.b >= 0 && c.b <= 1 && c.a >= 0 && c.a <= 1;
}
static BOOL ValidState(EHRTouchState s) {
  return ValidColor(s.text) && ValidColor(s.fill) && ValidColor(s.edge) && Finite(s.radius) &&
         s.radius >= 0 && s.radius <= 100000;
}
static BOOL ValidStyle(EHRTouchStyle s) {
  return ValidState(s.normal) && ValidState(s.hover) && ValidState(s.active) &&
         ValidColor(s.tint) && Finite(s.font_size) && s.font_size >= 0 && s.font_size <= 100000 &&
         s.font_style >= 0 && s.font_style <= 3 && s.alignment >= 0 && s.alignment <= 8 &&
         (s.rich_text == 0 || s.rich_text == 1) && (s.word_wrap == 0 || s.word_wrap == 1);
}

@interface EHRTouchPassthrough : UIView
@end
@implementation EHRTouchPassthrough
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
  UIView *v = [super hitTest:p withEvent:e];
  return v == self ? nil : v;
}
@end

@interface EHRTouchButton : UIButton
@property(nonatomic) EHRTouchStyle appearance;
@property(nonatomic) CGFloat unit;
@property(nonatomic) BOOL presentationHovered;
- (void)hover:(UIHoverGestureRecognizer *)gesture;
@end
@implementation EHRTouchButton
- (void)refresh {
  EHRTouchState s = self.highlighted           ? self.appearance.active
                    : self.presentationHovered ? self.appearance.hover
                                               : self.appearance.normal;
  self.backgroundColor = Color(Tinted(s.fill, self.appearance.tint));
  self.layer.borderColor = Color(Tinted(s.edge, self.appearance.tint)).CGColor;
  self.layer.borderWidth = 1;
  self.layer.cornerRadius = s.radius / self.unit;
}
- (void)hover:(UIHoverGestureRecognizer *)gesture {
  self.presentationHovered = gesture.state == UIGestureRecognizerStateBegan ||
                             gesture.state == UIGestureRecognizerStateChanged;
  [self refresh];
}
- (void)setHighlighted:(BOOL)value {
  [super setHighlighted:value];
  [self refresh];
}
@end

@interface EHRTouchWidget : NSObject
@property(nonatomic, strong) UIView *view;
@property(nonatomic, copy) NSString *label;
@property(nonatomic) uint32_t kind;
@property(nonatomic) uint64_t seen;
@property(nonatomic) BOOL pressed, changed;
@property(nonatomic) float changedValue;
@end
@implementation EHRTouchWidget
@end

@interface EHRTouchScroll : UIScrollView <UIScrollViewDelegate>
@property(nonatomic, strong) UIView *track, *thumb;
@property(nonatomic) CGFloat trackWidth, thumbWidth;
@end
@implementation EHRTouchScroll
- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat h = self.bounds.size.height, c = self.contentSize.height;
  self.track.hidden = c <= h || self.trackWidth <= 0;
  self.track.frame = CGRectMake(self.contentOffset.x + self.bounds.size.width - self.trackWidth,
                                self.contentOffset.y, self.trackWidth, h);
  CGFloat th = MAX(16, h * h / MAX(h, c));
  CGFloat y = (h - th) * self.contentOffset.y / MAX(1, c - h);
  self.thumb.frame =
      CGRectMake(1, MAX(0, MIN(h - th, y)), MAX(1, MIN(self.trackWidth, self.thumbWidth) - 2), th);
  [self bringSubviewToFront:self.track];
}
@end

@interface EHRTouchController : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, strong) EHRTouchPassthrough *root;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, EHRTouchWidget *> *widgets;
@property(nonatomic, strong) EHRTouchScroll *scroll;
@property(nonatomic, strong) UIView *fixtureHost;
@property(nonatomic) BOOL drawing;
@property(nonatomic) BOOL buttonConsumed;
@property(nonatomic) uint64_t epoch;
@property(nonatomic) float px, py, width, height;
@property(nonatomic) CFTimeInterval lastFrame;
@property(nonatomic) EHRTouchRect window;
@property(nonatomic) float titleHeight;
@property(nonatomic) CGPoint dragOrigin;
@property(nonatomic) BOOL moved;
@property(nonatomic) float dragX, dragY;
- (void)press:(UIButton *)sender;
- (void)slide:(UISlider *)sender;
- (void)pan:(UIPanGestureRecognizer *)gesture;
@end
static EHRTouchController *Controller;
static EHRTouchController *Get(void) {
  if (!Controller) {
    Controller = [EHRTouchController new];
    Controller.widgets = [NSMutableDictionary new];
  }
  return Controller;
}
static EHRTouchWidget *FindView(UIView *v) {
  for (EHRTouchWidget *w in Get().widgets.allValues)
    if (w.view == v)
      return w;
  return nil;
}
@implementation EHRTouchController
- (void)press:(UIButton *)sender {
  EHRTouchWidget *w = FindView(sender);
  if (w && w.seen == self.epoch && !self.root.hidden)
    w.pressed = YES;
}
- (void)slide:(UISlider *)sender {
  EHRTouchWidget *w = FindView(sender);
  if (w && w.seen == self.epoch && !self.root.hidden) {
    w.changed = YES;
    w.changedValue = sender.value;
  }
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
  CGPoint p = [g locationInView:self.root];
  return p.x >= self.window.x / self.px && p.x <= (self.window.x + self.window.width) / self.px &&
         p.y >= self.window.y / self.py && p.y <= (self.window.y + self.titleHeight) / self.py;
}
- (void)pan:(UIPanGestureRecognizer *)g {
  if (g.state == UIGestureRecognizerStateBegan)
    self.dragOrigin = CGPointMake(self.window.x, self.window.y);
  CGPoint t = [g translationInView:self.root];
  if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged ||
      g.state == UIGestureRecognizerStateEnded) {
    self.dragX = MAX(0, MIN(self.width - self.window.width, self.dragOrigin.x + t.x * self.px));
    self.dragY = MAX(0, MIN(self.height - self.window.height, self.dragOrigin.y + t.y * self.py));
    self.moved = YES;
  }
}
@end

static UIFont *Font(EHRTouchStyle s, CGFloat unit) {
  UIFont *font =
      [UIFont systemFontOfSize:MAX(6, s.font_size / unit)
                        weight:(s.font_style == 1 || s.font_style == 3) ? UIFontWeightBold
                                                                        : UIFontWeightRegular];
  if (s.font_style == 2 || s.font_style == 3) {
    UIFontDescriptor *d =
        [font.fontDescriptor fontDescriptorWithSymbolicTraits:font.fontDescriptor.symbolicTraits |
                                                              UIFontDescriptorTraitItalic];
    if (d)
      font = [UIFont fontWithDescriptor:d size:font.pointSize];
  }
  return font;
}
// Deliberately small Unity label markup parser. Unknown tags remain literal;
// there is no HTML/WebView/resource loading surface.
static NSAttributedString *Text(NSString *text, EHRTouchStyle style, CGFloat unit,
                                EHRTouchColor color) {
  NSMutableAttributedString *out = [NSMutableAttributedString new];
  NSMutableArray<NSDictionary *> *stack = [NSMutableArray arrayWithObject:@{
    NSFontAttributeName : Font(style, unit),
    NSForegroundColorAttributeName : Color(color)
  }];
  NSUInteger pos = 0;
  while (pos < text.length) {
    NSRange start = style.rich_text ? [text rangeOfString:@"<"
                                                  options:0
                                                    range:NSMakeRange(pos, text.length - pos)]
                                    : NSMakeRange(NSNotFound, 0);
    if (start.location == NSNotFound) {
      [out appendAttributedString:[[NSAttributedString alloc]
                                      initWithString:[text substringFromIndex:pos]
                                          attributes:stack.lastObject]];
      break;
    }
    if (start.location > pos)
      [out appendAttributedString:[[NSAttributedString alloc]
                                      initWithString:[text substringWithRange:NSMakeRange(
                                                                                  pos,
                                                                                  start.location -
                                                                                      pos)]
                                          attributes:stack.lastObject]];
    NSRange end = [text rangeOfString:@">"
                              options:0
                                range:NSMakeRange(start.location, text.length - start.location)];
    if (end.location == NSNotFound) {
      [out appendAttributedString:[[NSAttributedString alloc]
                                      initWithString:[text substringFromIndex:start.location]
                                          attributes:stack.lastObject]];
      break;
    }
    NSString *tag = [text
        substringWithRange:NSMakeRange(start.location + 1, end.location - start.location - 1)];
    BOOL accepted = NO;
    if (([tag isEqual:@"/b"] || [tag isEqual:@"/i"] || [tag isEqual:@"/size"] ||
         [tag isEqual:@"/color"]) &&
        stack.count > 1) {
      [stack removeLastObject];
      accepted = YES;
    } else if (stack.count < 16) {
      NSMutableDictionary *a = [stack.lastObject mutableCopy];
      UIFont *f = a[NSFontAttributeName];
      if ([tag isEqual:@"b"] || [tag isEqual:@"i"]) {
        UIFontDescriptorSymbolicTraits trait =
            [tag isEqual:@"b"] ? UIFontDescriptorTraitBold : UIFontDescriptorTraitItalic;
        UIFontDescriptor *d = [f.fontDescriptor
            fontDescriptorWithSymbolicTraits:f.fontDescriptor.symbolicTraits | trait];
        if (d)
          a[NSFontAttributeName] = [UIFont fontWithDescriptor:d size:f.pointSize];
        accepted = YES;
      } else if ([tag hasPrefix:@"size="]) {
        NSScanner *scan = [NSScanner scannerWithString:[tag substringFromIndex:5]];
        double size = 0;
        if ([scan scanDouble:&size] && scan.isAtEnd && size > 0 && size < 10000) {
          a[NSFontAttributeName] = [UIFont fontWithDescriptor:f.fontDescriptor
                                                         size:MAX(6, size / unit)];
          accepted = YES;
        }
      } else if ([tag hasPrefix:@"color=#"] && (tag.length == 13 || tag.length == 15)) {
        NSString *hex = [tag substringFromIndex:7];
        NSScanner *scan = [NSScanner scannerWithString:hex];
        unsigned long long rgba = 0;
        if ([scan scanHexLongLong:&rgba] && scan.isAtEnd) {
          if (hex.length == 6)
            rgba = (rgba << 8) | 255;
          a[NSForegroundColorAttributeName] = [UIColor colorWithRed:((rgba >> 24) & 255) / 255.0
                                                              green:((rgba >> 16) & 255) / 255.0
                                                               blue:((rgba >> 8) & 255) / 255.0
                                                              alpha:(rgba & 255) / 255.0];
          accepted = YES;
        }
      }
      if (accepted)
        [stack addObject:a];
    }
    if (!accepted)
      [out appendAttributedString:[[NSAttributedString alloc]
                                      initWithString:[text
                                                         substringWithRange:NSMakeRange(
                                                                                start.location,
                                                                                end.location -
                                                                                    start.location +
                                                                                    1)]
                                          attributes:stack.lastObject]];
    pos = end.location + 1;
  }
  return out;
}
static UIView *Host(void) {
  if (Get().fixtureHost)
    return Get().fixtureHost;
  for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
    if (![s isKindOfClass:UIWindowScene.class] ||
        s.activationState != UISceneActivationStateForegroundActive)
      continue;
    for (UIWindow *w in ((UIWindowScene *)s).windows)
      if (w.isKeyWindow && w.rootViewController)
        return w.rootViewController.view;
  }
  return nil;
}
static int32_t Main(void) { return NSThread.isMainThread ? 1 : 0; }
static int32_t Hide(void) {
  if (!Main())
    return 2;
  EHRTouchController *c = Get();
  c.root.hidden = YES;
  c.drawing = NO;
  c.scroll = nil;
  c.moved = NO;
  for (EHRTouchWidget *w in c.widgets.allValues) {
    w.pressed = NO;
    w.changed = NO;
  }
  return 0;
}
static int32_t Begin(float width, float height, EHRTouchFrame *frame) {
  if (frame)
    memset(frame, 0, sizeof(*frame));
  if (!Main())
    return 2;
  if (!frame || !Finite(width) || !Finite(height) || width <= 0 || height <= 0 || width > 100000 ||
      height > 100000)
    return 4;
  EHRTouchController *c = Get();
  if (c.drawing)
    return 4;
  UIView *host = Host();
  if (!host || host.bounds.size.width <= 0 || host.bounds.size.height <= 0) {
    Hide();
    return 3;
  }
  frame->version = 1;
  frame->size = sizeof(*frame);
  c.width = width;
  c.height = height;
  c.px = width / host.bounds.size.width;
  c.py = height / host.bounds.size.height;
  frame->pixels_per_point_x = c.px;
  frame->pixels_per_point_y = c.py;
  frame->width = width;
  frame->height = height;
  UIEdgeInsets safe = host.safeAreaInsets;
  // The public guide already tracks the keyboard in this scene/view. Reading
  // its current frame also handles a keyboard visible before Begin first runs.
  // Leave followsUndockedKeyboard and all host constraints unchanged. Only a
  // full-safe-width bottom obstruction becomes the existing bottom inset.
  if (host.window) {
    UIKeyboardLayoutGuide *guide = host.keyboardLayoutGuide;
    UIView *owner = guide.owningView;
    if (owner) {
      CGRect keyboard = owner == host ? guide.layoutFrame
                                     : [host convertRect:guide.layoutFrame fromView:owner];
      CGRect bounds = host.bounds;
      safe.bottom = ehr::keyboard::bottomInset(
          {bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height},
          {keyboard.origin.x, keyboard.origin.y, keyboard.size.width, keyboard.size.height},
          safe.left, safe.right, safe.bottom);
    }
  }
  frame->safe_left = safe.left * c.px;
  frame->safe_top = safe.top * c.py;
  frame->safe_right = safe.right * c.px;
  frame->safe_bottom = safe.bottom * c.py;
  CFTimeInterval now = CACurrentMediaTime();
  if (!c.fixtureHost && now - c.lastFrame < 1.0 / 20.0)
    return 0;
  c.lastFrame = now;
  if (!c.root || c.root.superview != host) {
    [c.root removeFromSuperview];
    c.root = [[EHRTouchPassthrough alloc] initWithFrame:host.bounds];
    c.root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    c.root.accessibilityIdentifier = @"EHR.TouchControls";
    [host addSubview:c.root];
    [c.widgets removeAllObjects];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:c
                                                                          action:@selector(pan:)];
    pan.delegate = c;
    pan.cancelsTouchesInView = YES;
    [c.root addGestureRecognizer:pan];
  }
  c.root.hidden = NO;
  [host bringSubviewToFront:c.root];
  c.epoch++;
  c.drawing = YES;
  c.buttonConsumed = NO;
  c.scroll = nil;
  c.titleHeight = 0;
  frame->should_draw = 1;
  return 0;
}
static CGRect ViewRect(EHRTouchRect r) {
  EHRTouchController *c = Get();
  return CGRectMake(r.x / c.px, r.y / c.py, r.width / c.px, r.height / c.py);
}
static int32_t End(int32_t commit) {
  if (!Main())
    return 2;
  EHRTouchController *c = Get();
  if (!c.drawing)
    return 4;
  c.drawing = NO;
  if (!commit || c.scroll) {
    Hide();
    return commit ? 4 : 0;
  }
  for (NSNumber *k in c.widgets.allKeys) {
    EHRTouchWidget *w = c.widgets[k];
    if (w.seen != c.epoch) {
      [w.view removeFromSuperview];
      [c.widgets removeObjectForKey:k];
    }
  }
  return 0;
}
static int32_t Item(const EHRTouchItem *item, const uint8_t *utf8, size_t length, float *value,
                    int32_t *pressed) {
  if (value)
    *value = 0;
  if (pressed)
    *pressed = 0;
  if (!Main())
    return 2;
  EHRTouchController *c = Get();
  if (!c.drawing || !item || !value || !pressed || !item->key || !ValidRect(item->rect) ||
      !ValidStyle(item->style) || length > 8192 || (!utf8 && length) || item->kind < 1 ||
      item->kind > 4)
    return 4;
  NSString *label = [[NSString alloc] initWithBytes:utf8
                                             length:length
                                           encoding:NSUTF8StringEncoding];
  if (!label)
    return 4;
  NSNumber *key = @(item->key);
  EHRTouchWidget *w = c.widgets[key];
  if (w && w.seen == c.epoch)
    return 4;
  if (w && (w.kind != item->kind || ![w.label isEqual:label])) {
    [w.view removeFromSuperview];
    [c.widgets removeObjectForKey:key];
    w = nil;
  }
  if (!w) {
    if (c.widgets.count >= 512)
      return 5;
    w = [EHRTouchWidget new];
    w.kind = item->kind;
    w.label = label;
    if (item->kind == EHR_TOUCH_BUTTON) {
      EHRTouchButton *b = [EHRTouchButton buttonWithType:UIButtonTypeCustom];
      [b addTarget:c action:@selector(press:) forControlEvents:UIControlEventTouchUpInside];
      [b addGestureRecognizer:[[UIHoverGestureRecognizer alloc] initWithTarget:b
                                                                        action:@selector(hover:)]];
      w.view = b;
    } else if (item->kind == EHR_TOUCH_LABEL)
      w.view = [UILabel new];
    else if (item->kind == EHR_TOUCH_SLIDER) {
      UISlider *s = [UISlider new];
      [s addTarget:c action:@selector(slide:) forControlEvents:UIControlEventValueChanged];
      w.view = s;
    } else
      w.view = [UIView new];
    c.widgets[key] = w;
  }
  *value = item->value;
  *pressed = w.pressed && !c.buttonConsumed ? 1 : 0;
  if (*pressed)
    c.buttonConsumed = YES;
  w.pressed = NO;
  w.seen = c.epoch;
  UIView *v = w.view;
  v.frame = ViewRect(item->rect);
  v.alpha = item->style.tint.a;
  v.accessibilityIdentifier =
      [NSString stringWithFormat:@"EHR.%llu", (unsigned long long)item->key];
  UIView *parent = c.scroll ?: c.root;
  [parent addSubview:v];
  EHRTouchState s = item->style.normal;
  if (item->kind == EHR_TOUCH_BUTTON) {
    EHRTouchButton *b = (EHRTouchButton *)v;
    b.appearance = item->style;
    b.unit = c.py;
    b.titleLabel.numberOfLines = item->style.word_wrap ? 0 : 1;
    b.titleLabel.textAlignment = (item->style.alignment % 3 == 0)   ? NSTextAlignmentLeft
                                 : (item->style.alignment % 3 == 1) ? NSTextAlignmentCenter
                                                                    : NSTextAlignmentRight;
    [b setAttributedTitle:Text(label, item->style, c.py, Tinted(s.text, item->style.tint))
                 forState:UIControlStateNormal];
    [b setAttributedTitle:Text(label, item->style, c.py,
                               Tinted(item->style.active.text, item->style.tint))
                 forState:UIControlStateHighlighted];
    [b refresh];
  } else if (item->kind == EHR_TOUCH_LABEL) {
    UILabel *l = (UILabel *)v;
    l.attributedText = Text(label, item->style, c.py, Tinted(s.text, item->style.tint));
    l.numberOfLines = item->style.word_wrap ? 0 : 1;
    l.textAlignment = (item->style.alignment % 3 == 0)   ? NSTextAlignmentLeft
                      : (item->style.alignment % 3 == 1) ? NSTextAlignmentCenter
                                                         : NSTextAlignmentRight;
  } else if (item->kind == EHR_TOUCH_SLIDER) {
    if (!Finite(item->minimum) || !Finite(item->maximum) || !Finite(item->value) ||
        item->minimum >= item->maximum)
      return 4;
    UISlider *slider = (UISlider *)v;
    slider.minimumValue = item->minimum;
    slider.maximumValue = item->maximum;
    if (w.changed) {
      *value = MAX(item->minimum, MIN(item->maximum, w.changedValue));
      w.changed = NO;
    }
    slider.value = *value;
    slider.accessibilityLabel = @"Zoom";
  } else {
    v.backgroundColor = Color(Tinted(s.fill, item->style.tint));
    v.layer.cornerRadius = s.radius / c.py;
    v.layer.borderColor = Color(Tinted(s.edge, item->style.tint)).CGColor;
    v.layer.borderWidth = 1;
  }
  return 0;
}
static int32_t BeginScroll(uint64_t key, const EHRTouchRect *outer, const EHRTouchRect *inner,
                           float x, float y, float indicator, float thumb, float *outX,
                           float *outY) {
  if (outX)
    *outX = 0;
  if (outY)
    *outY = 0;
  if (!Main())
    return 2;
  EHRTouchController *c = Get();
  if (!c.drawing || c.scroll || !key || !outer || !inner || !outX || !outY || !ValidRect(*outer) ||
      !ValidRect(*inner) || !Finite(x) || !Finite(y) || !Finite(indicator) || indicator < 0 ||
      !Finite(thumb) || thumb < 0)
    return 4;
  EHRTouchWidget *w = c.widgets[@(key)];
  if (w && w.kind != 5)
    return 4;
  if (!w) {
    if (c.widgets.count >= 512)
      return 5;
    w = [EHRTouchWidget new];
    w.kind = 5;
    w.label = @"scroll";
    EHRTouchScroll *s = [EHRTouchScroll new];
    s.showsHorizontalScrollIndicator = NO;
    s.showsVerticalScrollIndicator = NO;
    s.alwaysBounceVertical = NO;
    s.track = [UIView new];
    s.track.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.4];
    s.track.userInteractionEnabled = NO;
    s.thumb = [UIView new];
    s.thumb.backgroundColor = [UIColor colorWithWhite:0.7 alpha:0.7];
    s.thumb.layer.cornerRadius = 3;
    [s.track addSubview:s.thumb];
    [s addSubview:s.track];
    w.view = s;
    c.widgets[@(key)] = w;
  }
  if (w.seen == c.epoch)
    return 4;
  BOOL fresh = w.seen == 0;
  w.seen = c.epoch;
  EHRTouchScroll *s = (EHRTouchScroll *)w.view;
  s.frame = ViewRect(*outer);
  s.contentSize = CGSizeMake(inner->width / c.px, MAX(inner->height, outer->height) / c.py);
  s.trackWidth = indicator / c.px;
  s.thumbWidth = thumb / c.px;
  [c.root addSubview:s];
  if (fresh)
    s.contentOffset = CGPointMake(0, MAX(0, y / c.py));
  *outX = 0;
  *outY = s.contentOffset.y * c.py;
  c.scroll = s;
  return 0;
}
static int32_t EndScroll(void) {
  if (!Main())
    return 2;
  EHRTouchController *c = Get();
  if (!c.drawing || !c.scroll)
    return 4;
  [c.scroll setNeedsLayout];
  c.scroll = nil;
  return 0;
}
static int32_t Move(EHRTouchRect *r, float title) {
  if (!Main())
    return 2;
  EHRTouchController *c = Get();
  if (!c.drawing || !r || !ValidRect(*r) || !Finite(title) || title < 0)
    return 4;
  if (c.moved) {
    r->x = c.dragX;
    r->y = c.dragY;
    c.moved = NO;
  }
  c.window = *r;
  c.titleHeight = title;
  return 0;
}
static const EHRTouchUIV1 Table = {1,    sizeof(EHRTouchUIV1), Main,      Begin, End,
                                   Item, BeginScroll,          EndScroll, Move,  Hide};
extern "C" const EHRTouchUIV1 *EHRTouchUIGetV1(void) { return &Table; }

extern "C" int32_t EHRTouchUISelfTest(int32_t *p, size_t count) {
  if (p && count)
    memset(p, 0, MIN(count, 12ul) * sizeof(*p));
  if (!p || count < 12 || !Main())
    return 4;
  EHRTouchController *saved = Controller;
  Controller = [EHRTouchController new];
  Controller.widgets = [NSMutableDictionary new];
  Controller.fixtureHost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 300)];
  int32_t status = 0;
  EHRTouchFrame f = {};
  EHRTouchItem i = {};
  float value = 0;
  int32_t pressed = 0;
  i.key = 7;
  i.kind = EHR_TOUCH_BUTTON;
  i.rect = {10, 10, 100, 50};
  i.style.normal.text = {1, 1, 1, 1};
  i.style.normal.fill = {0, 0, 1, 1};
  i.style.normal.edge = {1, 1, 1, 1};
  i.style.hover = i.style.normal;
  i.style.active = i.style.normal;
  i.style.tint = {1, 1, 1, 1};
  i.style.font_size = 20;
  i.style.alignment = 4;
  i.style.rich_text = 1;
  status = Begin(800, 600, &f);
  p[2] = status == 0 && f.should_draw && f.pixels_per_point_x == 2;
  p[3] = Item(&i, (const uint8_t *)"<b>Test</b>", 11, &value, &pressed) == 0 && pressed == 0;
  End(1);
  EHRTouchButton *b = (EHRTouchButton *)Get().widgets[@7].view;
  [b sendActionsForControlEvents:UIControlEventTouchUpInside];
  Begin(800, 600, &f);
  p[4] = Item(&i, (const uint8_t *)"<b>Test</b>", 11, &value, &pressed) == 0 && pressed == 1;
  p[5] = Item(&i, (const uint8_t *)"<b>Test</b>", 11, &value, &pressed) == 4;
  End(1);
  Begin(800, 600, &f);
  Item(&i, (const uint8_t *)"<b>Test</b>", 11, &value, &pressed);
  p[6] = pressed == 0;
  End(1);
  [b sendActionsForControlEvents:UIControlEventTouchUpInside];
  Begin(800, 600, &f);
  End(1);
  Begin(800, 600, &f);
  Item(&i, (const uint8_t *)"<b>Test</b>", 11, &value, &pressed);
  p[7] = pressed == 0;
  End(1);
  EHRTouchButton *current = (EHRTouchButton *)Get().widgets[@7].view;
  [current sendActionsForControlEvents:UIControlEventTouchUpInside];
  Begin(800, 600, &f);
  Item(&i, (const uint8_t *)"Different action", 16, &value, &pressed);
  p[7] = p[7] && pressed == 0;
  End(1);
  p[8] = [[b attributedTitleForState:UIControlStateNormal].string isEqual:@"Test"];
  Begin(800, 600, &f);
  i.kind = EHR_TOUCH_SLIDER;
  i.key = 8;
  i.minimum = 3;
  i.maximum = 18;
  i.value = 4;
  Item(&i, (const uint8_t *)"", 0, &value, &pressed);
  End(1);
  UISlider *s = (UISlider *)Get().widgets[@8].view;
  s.value = 7;
  [s sendActionsForControlEvents:UIControlEventValueChanged];
  Begin(800, 600, &f);
  Item(&i, (const uint8_t *)"", 0, &value, &pressed);
  p[9] = value == 7;
  End(1);
  Hide();
  p[10] = Get().root.hidden;
  [s sendActionsForControlEvents:UIControlEventValueChanged];
  Begin(800, 600, &f);
  Item(&i, (const uint8_t *)"", 0, &value, &pressed);
  p[10] = p[10] && value == i.value;
  End(1);
  Begin(800, 600, &f);
  EHRTouchRect outer = {10, 20, 200, 100}, inner = {0, 0, 180, 1000};
  float scrollX = 0, scrollY = 0;
  p[10] = p[10] && BeginScroll(44, &outer, &inner, 0, 42, 8, 6, &scrollX, &scrollY) == 0 &&
          scrollY == 42;
  EndScroll();
  End(1);
  Begin(800, 600, &f);
  const uint8_t invalid[] = {0xff};
  p[11] = Item(&i, invalid, sizeof(invalid), &value, &pressed) == 4;
  i.rect.width = NAN;
  p[11] = p[11] && Item(&i, (const uint8_t *)"", 0, &value, &pressed) == 4;
  End(0);
  p[0] = 1;
  for (size_t n = 2; n < 12; n++)
    if (!p[n])
      p[0] = 0;
  p[1] = status;
  [Controller.root removeFromSuperview];
  Controller = saved;
  return p[0] ? 0 : 7;
}
