#include <math.h>
#import "overspeed-frame.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
static void GVMExcludeLayerFromInput(CALayer *layer) {
    SEL selector=NSSelectorFromString(@"setAllowsHitTesting:");
    if ([layer respondsToSelector:selector]) ((void (*)(id,SEL,BOOL))objc_msgSend)(layer,selector,NO);
}
@implementation GVMOverspeedFrame {
    CALayer *_rim;
    CGSize _renderedSize;
    BOOL _requested;
    NSUInteger _level;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor; self.opaque=NO; self.userInteractionEnabled=NO;
        self.isAccessibilityElement=NO; self.accessibilityElementsHidden=YES; self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        GVMExcludeLayerFromInput(self.layer);
        _rim=[CALayer layer]; GVMExcludeLayerFromInput(_rim);
        [self.layer addSublayer:_rim]; self.hidden=YES;
    }
    return self;
}
// Warning artwork must never participate in touch or CarPlay focus routing.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return NO; }
- (BOOL)canBecomeFocused { return NO; }
- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES]; _rim.frame=self.bounds; [CATransaction commit];
    CGSize size=self.bounds.size;
    if (CGSizeEqualToSize(size,_renderedSize) && _rim.contents) return;
    if (size.width<=0 || size.height<=0) return;
    _renderedSize=size;
    CGFloat depth=MIN(18,MIN(size.width,size.height)*0.06);
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *render) {
        CGRect bounds=(CGRect){CGPointZero,size};
        UIBezierPath *inside=[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:12];
        [inside addClip];
        CGContextSetShadowWithColor(render.CGContext,CGSizeZero,depth,
            [UIColor colorWithRed:1 green:0.08 blue:0.08 alpha:0.8].CGColor);
        // Cast the shadow inward from an outside ring; its fill stays outside the clip.
        UIBezierPath *outside=[UIBezierPath bezierPathWithRect:CGRectInset(bounds,-depth*3,-depth*3)];
        [outside appendPath:inside]; outside.usesEvenOddFillRule=YES;
        [[UIColor colorWithRed:1 green:0.08 blue:0.08 alpha:1] setFill]; [outside fill];
    }];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _rim.contents=(__bridge id)image.CGImage; _rim.contentsScale=image.scale;
    [CATransaction commit];
}
- (void)setWholeScreen:(BOOL)wholeScreen {
    if (_wholeScreen==wholeScreen) return;
    _wholeScreen=wholeScreen;
    [_rim removeAnimationForKey:@"pulse"];
    [self setWarningActive:_requested];
}
- (void)setWarningLevel:(NSUInteger)level {
    level=MIN(level,3);
    if (_level!=level) { _level=level; [_rim removeAnimationForKey:@"pulse"]; }
    [self setWarningActive:level!=0];
}
- (void)setWarningActive:(BOOL)active {
    _requested=active;
    self.hidden=!active || !self.layer.superlayer;
    if (self.hidden) { [_rim removeAnimationForKey:@"pulse"]; return; }
    if (![_rim animationForKey:@"pulse"]) {
        CABasicAnimation *pulse=[CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.fromValue=self.wholeScreen ? @0.05 : @0.12;
        pulse.toValue=self.wholeScreen ? @0.5 : @1.0;
        pulse.duration=0.5/(_level==3 ? 2.0 : _level==2 ? 1.25 : 0.75);
        pulse.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        pulse.autoreverses=YES; pulse.repeatCount=HUGE_VALF;
        [_rim addAnimation:pulse forKey:@"pulse"];
    }
}
- (void)didMoveToWindow { [super didMoveToWindow]; [self setWarningActive:_requested]; }
@end
