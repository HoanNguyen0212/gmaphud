#import <rootless.h>
#import "carplay-style.h"
#import "speed-presentation.h"
#import "vietmap-alert-assets.h"
#import "placement-state.h"
#import <objc/runtime.h>

@interface GVMSpeedCard : UIView
@property(nonatomic, copy) NSNumber *speed, *limit;
@property(nonatomic, copy) NSArray<NSDictionary *> *alerts;
@property(nonatomic) BOOL night, compact;
@end

static UIColor *RGB(unsigned value, CGFloat alpha) {
    return [UIColor colorWithRed:((value >> 16) & 255)/255.0 green:((value >> 8) & 255)/255.0
        blue:(value & 255)/255.0 alpha:alpha];
}
static void Text(NSString *text, CGRect rect, CGFloat size, UIFontWeight weight, UIColor *color) {
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName:color, NSParagraphStyleAttributeName:paragraph}];
}
@implementation GVMSpeedCard
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    NSUInteger count=MIN(self.alerts.count,2);
    CGFloat canvasWidth = self.compact ? 84 : (count==2 ? 296 : count==1 ? 240 : 208);
    CGFloat canvasHeight = self.compact ? (count==2 ? 350 : count ? 260 : 160) : 106;
    CGContextScaleCTM(context, self.bounds.size.width/canvasWidth, self.bounds.size.height/canvasHeight);
    GVMWarning warning = GVMWarningFor(self.speed, self.limit);
    UIColor *accent = warning == GVMWarningOver ? RGB(0xff6868,1) :
        warning == GVMWarningNear ? RGB(0xffd15c,1) : UIColor.whiteColor;
    UIColor *muted = RGB(0xe0e3e8,1);
    CGRect body = self.compact ? CGRectMake(1,1,82,canvasHeight-2) : CGRectMake(1,25,canvasWidth-2,80);
    if (!self.compact) {
        CGFloat badgeX = (canvasWidth - 112) / 2;
        UIBezierPath *badge = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(badgeX,1,112,32) cornerRadius:12];
        [RGB(0x202631,0.94) setFill]; [badge fill];
        Text(@"VIETMAP LIVE",CGRectMake(badgeX+2,5,108,19),13,UIFontWeightBold,UIColor.whiteColor);
    }
    UIBezierPath *bubble = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:self.compact ? 41 : 24];
    [RGB(self.night ? 0x303642 : 0x59616f,0.60) setFill]; [bubble fill];
    [RGB(0x303947,0.8) setStroke]; bubble.lineWidth=1.5; [bubble stroke];
    if (count && !self.compact) {
        UIBezierPath *sourceRegion=[UIBezierPath bezierPathWithRoundedRect:
            CGRectMake(178,29,canvasWidth-183,72) cornerRadius:18];
        [RGB(0x162b35,0.22) setFill]; [sourceRegion fill];
    }
    CGRect signRect = self.compact ? CGRectMake(12,12,60,60) : CGRectMake(count ? 104 : 131,35,60,60);
    UIBezierPath *sign = [UIBezierPath bezierPathWithOvalInRect:signRect];
    sign.lineWidth=self.limit ? 6 : 2.5;
    if (self.limit) {
        [UIColor.whiteColor setFill]; [sign fill]; [RGB(0xff3b30,1) setStroke];
    } else {
        CGFloat dash[]={5,3}; [sign setLineDash:dash count:2 phase:0]; [muted setStroke];
    }
    [sign stroke];
    Text(self.limit ? self.limit.stringValue : @"–",
        CGRectMake(signRect.origin.x-3,signRect.origin.y+10,66,42),
        self.limit.doubleValue >= 100 ? 28 : 32,UIFontWeightBold,self.limit ? RGB(0x17191d,1) : muted);
    CGRect speedRect = self.compact ? CGRectMake(7,91,70,39) : CGRectMake(5,34,count ? 94 : 108,45);
    Text(self.speed ? self.speed.stringValue : @"--",speedRect,self.compact ? 31 : 37,
        UIFontWeightBold,self.speed ? accent : muted);
    Text(@"km/h",self.compact ? CGRectMake(14,130,56,19) : CGRectMake(count ? 17 : 31,78,64,20),
        14,UIFontWeightMedium,muted);
    if (count) {
        CGFloat y=self.compact ? 195 : 58;
        UIBezierPath *divider=[UIBezierPath bezierPath];
        [divider moveToPoint:self.compact ? CGPointMake(10,158) : CGPointMake(174,34)];
        [divider addLineToPoint:self.compact ? CGPointMake(74,158) : CGPointMake(174,96)];
        [RGB(0x303947,0.65) setStroke]; divider.lineWidth=1; [divider stroke];
        if (self.compact && count==2) {
            UIBezierPath *secondDivider=[UIBezierPath bezierPath];
            [secondDivider moveToPoint:CGPointMake(10,250)];
            [secondDivider addLineToPoint:CGPointMake(74,250)];
            [RGB(0x303947,0.65) setStroke]; secondDivider.lineWidth=1; [secondDivider stroke];
        }
        if (!self.compact && count==2) {
            UIBezierPath *secondDivider=[UIBezierPath bezierPath];
            [secondDivider moveToPoint:CGPointMake(235,34)];
            [secondDivider addLineToPoint:CGPointMake(235,96)];
            [RGB(0x303947,0.65) setStroke]; secondDivider.lineWidth=1; [secondDivider stroke];
        }
        static NSMutableDictionary<NSNumber *, UIImage *> *artworkCache;
        static dispatch_once_t artworkOnce;
        dispatch_once(&artworkOnce, ^{ artworkCache=[NSMutableDictionary dictionary]; });
        CGFloat alertDiameter=self.compact ? signRect.size.width+6 : 42;
        for (NSUInteger i=0;i<count;i++) {
            CGFloat x=self.compact ? 42 : 205+60*i;
            CGFloat alertY=y+(self.compact ? 90*i : 0);
            NSDictionary *alert=self.alerts[i];
            NSNumber *kind=alert[@"kind"];
            NSNumber *cacheKey=@(([alert[@"provider"] unsignedIntegerValue]<<8)|kind.unsignedIntegerValue);
            UIImage *artwork=artworkCache[cacheKey];
            if (!artwork && [alert[@"provider"] unsignedIntegerValue]==GVMVietMapProviderID) {
                NSString *name=GVMVietMapAssetName(kind.unsignedIntegerValue);
                if (name) {
                    NSString *path=[ROOT_PATH_NS(@"/usr/share/gmaphud/vietmap") stringByAppendingPathComponent:name];
                    artwork=[UIImage imageWithContentsOfFile:path];
                    if (artwork) artworkCache[cacheKey]=artwork;
                }
            }
            [artwork drawInRect:CGRectMake(x-alertDiameter/2,alertY-alertDiameter/2,alertDiameter,alertDiameter)];
            id meters=alert[@"distance"];
            NSString *distance=meters==NSNull.null ? @"" : ([meters integerValue]>=1000 ?
                [NSString stringWithFormat:@"%.1f km",[meters doubleValue]/1000] :
                [NSString stringWithFormat:@"%@ m",meters]);
            Text(distance,CGRectMake(x-29,alertY+alertDiameter/2+2,58,21),self.compact ? 16 : 13,UIFontWeightMedium,UIColor.whiteColor);
        }
    }
    CGContextRestoreGState(context);
}
@end

static const void *cardKey = &cardKey;
static GVMCardPlacement fullPlacement = GVMCardTopRight;
static BOOL dashboardLeft;

void GVMSetPlacementState(uint64_t state) {
    NSUInteger corner=0;
    BOOL left=NO;
    if (!GVMDecodePlacement(state,&corner,&left)) return;
    fullPlacement=(GVMCardPlacement)corner;
    dashboardLeft=left;
}

static BOOL ExternalMap(UIView *map) {
    return NSThread.isMainThread && [map isKindOfClass:NSClassFromString(@"AZCarPlayView")] &&
        map.window && map.window.screen != UIScreen.mainScreen;
}
void GVMStyleNativeSpeedView(UIView *view) {
    UIView *owner = view.superview;
    while (owner && ![owner isKindOfClass:NSClassFromString(@"AZCarPlayView")]) owner=owner.superview;
    if (ExternalMap(owner)) view.alpha=0; // Keep Google's model/layout boundary, replace only its artwork.
}
CGRect GVMLayoutSpeedCard(UIView *map) {
    if (!ExternalMap(map)) return CGRectZero;
    GVMSpeedCard *card = objc_getAssociatedObject(map,cardKey);
    CGRect screen=map.window.screen.bounds;
    UIEdgeInsets insets=map.safeAreaInsets;
    CGFloat margin=MIN(10,MAX(5,MIN(screen.size.width,screen.size.height)*0.03));
    // Google propagates horizontal control exclusions into map/window safe
    // areas. Anchor to the map bounds so disappearing alerts cannot shift it.
    CGFloat left=CGRectGetMinX(map.bounds)+margin;
    CGFloat right=CGRectGetMaxX(map.bounds)-margin;
    CGFloat top=CGRectGetMinY(map.bounds)+insets.top+margin;
    CGFloat bottom=CGRectGetMaxY(map.bounds)-insets.bottom-margin;
    GVMCardSize size=GVMCardSizeFor(MAX(0,right-left),MAX(0,bottom-top),
        screen.size.width,screen.size.height,card.alerts.count);
    BOOL compact=size.compact;
    GVMCardPlacement placement=compact ? (dashboardLeft ? GVMCardTopLeft : GVMCardTopRight) : fullPlacement;
    if (placement==GVMCardTopLeft || placement==GVMCardBottomLeft) left+=insets.left;
    if (placement==GVMCardBottomRight) right-=insets.right;
    if (placement==GVMCardBottomLeft || placement==GVMCardBottomRight)
        bottom-=MAX(0,25-insets.bottom); // Leave Google's map attribution clear.
    size=GVMCardSizeFor(MAX(0,right-left),MAX(0,bottom-top),
        screen.size.width,screen.size.height,card.alerts.count);
    GVMCardOrigin origin=GVMCardOriginFor(left,right,top,bottom,size,placement);
    CGRect frame=CGRectMake(origin.x,origin.y,size.width,size.height);
    if (card && card.compact!=compact) { card.compact=compact; [card setNeedsDisplay]; }
    if (card && !CGRectEqualToRect(card.frame,frame)) { card.frame=frame; [card setNeedsDisplay]; }
    return frame;
}
void GVMUpdateSpeedCard(UIView *map, NSNumber *speed, NSNumber *limit, NSArray<NSDictionary *> *alerts, BOOL night) {
    if (!ExternalMap(map)) return;
    GVMSpeedCard *card = objc_getAssociatedObject(map,cardKey);
    if (!card) {
        card = [[GVMSpeedCard alloc] initWithFrame:CGRectZero];
        card.backgroundColor=UIColor.clearColor; card.opaque=NO; card.userInteractionEnabled=NO;
        card.isAccessibilityElement=YES;
        card.layer.shadowColor=UIColor.blackColor.CGColor; card.layer.shadowOpacity=0.2;
        card.layer.shadowRadius=3; card.layer.shadowOffset=CGSizeMake(0,2);
        [map addSubview:card]; objc_setAssociatedObject(map,cardKey,card,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL alertsChanged=!((card.alerts==alerts)||[card.alerts isEqual:alerts]);
    card.alerts=alerts;
    CGRect frame = GVMLayoutSpeedCard(map);
    BOOL changed = alertsChanged || !CGRectEqualToRect(card.frame,frame) || card.night!=night ||
        !((card.speed==speed)||[card.speed isEqual:speed]) || !((card.limit==limit)||[card.limit isEqual:limit]);
    card.frame=frame; card.speed=speed; card.limit=limit; card.night=night;
    if (changed) [card setNeedsDisplay];
    card.accessibilityLabel=[NSString stringWithFormat:@"Speed %@ km/h, limit %@ km/h", speed ?: @"unavailable",limit ?: @"unavailable"];
    for (NSDictionary *alert in alerts) {
        NSString *name=GVMVietMapAssetName([alert[@"kind"] unsignedIntegerValue]) ?: @"road warning";
        id meters=alert[@"distance"];
        card.accessibilityLabel=[card.accessibilityLabel stringByAppendingFormat:@", VietMap %@%@",name,
            meters==NSNull.null ? @"" : [NSString stringWithFormat:@" %@ meters",meters]];
    }
    [map bringSubviewToFront:card];
}
