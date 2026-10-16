#import "halo-dock.h"
#import "halo-style.h"

const CGFloat GVMHaloSignDockBleed=0.12;

@implementation GVMHaloSignDock
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    self.backgroundColor=UIColor.clearColor; self.opaque=NO; self.userInteractionEnabled=NO;
    return self;
}
- (void)setSigns:(NSArray<NSDictionary *> *)signs {
    if ((_signs==signs) || [_signs isEqual:signs]) return;
    _signs=[signs copy]; [self setNeedsDisplay];
}
- (void)setDiameter:(CGFloat)diameter {
    if (_diameter==diameter) return;
    _diameter=diameter; [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGFloat d=self.diameter, bleed=d*GVMHaloSignDockBleed;
    if (d<=0) return;
    for (NSUInteger i=0;i<self.signs.count;i++) {
        NSDictionary *sign=self.signs[i];
        GVMHaloDrawSign([sign[@"type"] unsignedIntegerValue],sign[@"value"],CGPointMake(bleed+d/2+i*(d+6),bleed+d/2),d);
    }
}
@end
