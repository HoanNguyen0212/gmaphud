#import <rootless.h>
#import "carplay-style.h"
#import "speed-presentation.h"
#import "vietmap-alert-assets.h"
#import "placement-state.h"
#import "tpms-state.h"
#import <objc/runtime.h>
#include <notify.h>

@interface GVMSpeedCard : UIView
@property(nonatomic, copy) NSNumber *speed, *limit;
@property(nonatomic, copy) NSArray<NSDictionary *> *alerts;
@property(nonatomic) GVMTPMSData tpms;
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

static void DrawTire(NSString *pos, float press, uint8_t warn, CGRect rect, BOOL night) {
    if (press <= 0.01f) return;
    UIColor *bg = warn == 1 ? RGB(0xff9f0a, 0.95) :  // warning low
                  warn >= 2 ? RGB(0xff3b30, 0.95) :  // warning high/leak
                  RGB(night ? 0x242b35 : 0x48515f, 0.85); // normal
    UIBezierPath *box = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:6];
    [bg setFill]; [box fill];
    [RGB(0x303947, 0.7) setStroke]; box.lineWidth = 1; [box stroke];
    NSString *text = [NSString stringWithFormat:@"%.1f", press];
    Text(text, CGRectMake(rect.origin.x, rect.origin.y + 2, rect.size.width, 13), 11, UIFontWeightBold, UIColor.whiteColor);
    Text(pos, CGRectMake(rect.origin.x, rect.origin.y + 15, rect.size.width, 10), 8, UIFontWeightBold, RGB(0xd0d4dc, 1));
}

@implementation GVMSpeedCard
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    NSUInteger count = MIN(self.alerts.count, 2);
    
    BOOL hasTpms = self.tpms.hasData;
    CGFloat canvasWidth = self.compact ? 84 : 
        (hasTpms ? (count==2 ? 375 : count==1 ? 320 : 288) : (count==2 ? 296 : count==1 ? 240 : 208));
    CGFloat canvasHeight = self.compact ? 
        (hasTpms ? (count==2 ? 415 : count ? 325 : 225) : (count==2 ? 350 : count ? 260 : 160)) : 106;
        
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
    
    // Draw TPMS (Áp suất lốp)
    if (hasTpms) {
        if (self.compact) {
            CGFloat tpmsY = count == 2 ? 335 : count == 1 ? 245 : 155;
            UIBezierPath *tpmsDiv = [UIBezierPath bezierPath];
            [tpmsDiv moveToPoint:CGPointMake(10, tpmsY - 5)];
            [tpmsDiv addLineToPoint:CGPointMake(74, tpmsY - 5)];
            [RGB(0x303947, 0.65) setStroke]; tpmsDiv.lineWidth = 1; [tpmsDiv stroke];
            
            DrawTire(@"FL", self.tpms.fl.pressure, self.tpms.fl.warning, CGRectMake(6, tpmsY, 34, 26), self.night);
            DrawTire(@"FR", self.tpms.fr.pressure, self.tpms.fr.warning, CGRectMake(44, tpmsY, 34, 26), self.night);
            DrawTire(@"RL", self.tpms.rl.pressure, self.tpms.rl.warning, CGRectMake(6, tpmsY + 30, 34, 26), self.night);
            DrawTire(@"RR", self.tpms.rr.pressure, self.tpms.rr.warning, CGRectMake(44, tpmsY + 30, 34, 26), self.night);
        } else {
            CGFloat tpmsX = count == 2 ? 300 : count == 1 ? 244 : 210;
            UIBezierPath *tpmsDiv = [UIBezierPath bezierPath];
            [tpmsDiv moveToPoint:CGPointMake(tpmsX - 8, 34)];
            [tpmsDiv addLineToPoint:CGPointMake(tpmsX - 8, 96)];
            [RGB(0x303947, 0.65) setStroke]; tpmsDiv.lineWidth = 1; [tpmsDiv stroke];
            
            DrawTire(@"FL", self.tpms.fl.pressure, self.tpms.fl.warning, CGRectMake(tpmsX, 34, 34, 27), self.night);
            DrawTire(@"FR", self.tpms.fr.pressure, self.tpms.fr.warning, CGRectMake(tpmsX + 38, 34, 34, 27), self.night);
            DrawTire(@"RL", self.tpms.rl.pressure, self.tpms.rl.warning, CGRectMake(tpmsX, 65, 34, 27), self.night);
            DrawTire(@"RR", self.tpms.rr.pressure, self.tpms.rr.warning, CGRectMake(tpmsX + 38, 65, 34, 27), self.night);
        }
    }
    
    CGContextRestoreGState(context);
}
@end

static const void *cardKey = &cardKey, *phoneKey=&phoneKey;
static NSUInteger SizePercent(NSUInteger surface) {
    static int token=-1; uint64_t state=0;
    if (token<0) notify_register_check(GVMSizeStateName,&token);
    if (token>=0) notify_get_state(token,&state);
    return GVMDecodeSize(state,surface);
}
static GVMCardPlacement fullPlacement = GVMCardTopRight;
static BOOL dashboardLeft;

void GVMSetPlacementState(uint64_t state) {
    NSUInteger corner=0;
    BOOL left=NO;
    if (!GVMDecodePlacement(state,&corner,&left)) return;
    fullPlacement=(GVMCardPlacement)corner;
    dashboardLeft=left;
}

static UIWindow *HostWindow(UIView *host) {
    return [host isKindOfClass:UIWindow.class] ? (UIWindow *)host : host.window;
}
static BOOL ExternalMap(UIView *map) {
    return NSThread.isMainThread && [map isKindOfClass:NSClassFromString(@"AZCarPlayView")] &&
        map.window && map.window.screen != UIScreen.mainScreen;
}
void GVMStyleNativeSpeedView(UIView *view) {
    UIView *owner = view.superview;
    while (owner && ![owner isKindOfClass:NSClassFromString(@"AZCarPlayView")]) owner=owner.superview;
    if (ExternalMap(owner)) view.alpha=0;
}
CGRect GVMLayoutSpeedCard(UIView *map) {
    BOOL phone=[objc_getAssociatedObject(map,phoneKey) boolValue];
    if (!ExternalMap(map) && !(phone && NSThread.isMainThread && HostWindow(map).screen==UIScreen.mainScreen)) return CGRectZero;
    GVMSpeedCard *card = objc_getAssociatedObject(map,cardKey);
    CGRect screen=HostWindow(map).screen.bounds;
    UIEdgeInsets insets=map.safeAreaInsets;
    CGFloat margin=MIN(10,MAX(5,MIN(screen.size.width,screen.size.height)*0.03));
    CGFloat left=CGRectGetMinX(map.bounds)+margin;
    CGFloat right=CGRectGetMaxX(map.bounds)-margin;
    CGFloat top=CGRectGetMinY(map.bounds)+margin;
    CGFloat bottom=CGRectGetMaxY(map.bounds)-margin;
    GVMCardSize size=GVMCarPlayCardSizeForView(MAX(0,right-left),MAX(0,bottom-top),
        map.bounds.size.width,screen.size.width,screen.size.height,card.alerts.count);
    if (phone) {
        size=GVMPhoneCardSizeFor(map.bounds.size.width,map.bounds.size.height,card.alerts.count);
        left=CGRectGetMinX(map.bounds); right=CGRectGetMaxX(map.bounds);
        top=CGRectGetMinY(map.bounds); bottom=CGRectGetMaxY(map.bounds);
    }
    NSUInteger phoneLayout=0;
    NSUInteger phoneCorner=1; NSInteger offsetX=0,offsetY=0;
    if (phone) {
        static int token=-1; uint64_t state=0;
        if (token<0) notify_register_check(GVMPhonePlacementStateName,&token);
        if (token>=0) notify_get_state(token,&state);
        GVMDecodePhonePlacement(state,&phoneCorner,&offsetX,&offsetY,&phoneLayout);
        size=GVMPhoneCardSizeForLayout(map.bounds.size.width,map.bounds.size.height,card.alerts.count,phoneLayout);
    }
    BOOL compact=size.compact;
    GVMCardPlacement placement=phone ? (GVMCardPlacement)phoneCorner : compact ? (dashboardLeft ? GVMCardTopLeft : GVMCardTopRight) : fullPlacement;
    size=GVMScaleCardSize(size,SizePercent(phone ? 2 : compact ? 1 : 0),MAX(0,right-left),MAX(0,bottom-top));
    CGFloat viewportLeft=left, viewportRight=right, viewportTop=top, viewportBottom=bottom;
    if (!phone) {
        top+=insets.top;
        bottom-=insets.bottom;
        if (placement==GVMCardTopLeft || placement==GVMCardBottomLeft) left+=insets.left;
        if (placement==GVMCardBottomRight) right-=insets.right;
        if (placement==GVMCardBottomLeft || placement==GVMCardBottomRight)
            bottom-=MAX(0,25-insets.bottom);
    }
    GVMCardOrigin origin=GVMCardOriginFor(left,right,top,bottom,size,placement);
    if (phone) {
        origin=GVMPhoneCardOriginFor(left,right,top,bottom,size,placement,
            offsetX*map.bounds.size.width/100.0,offsetY*map.bounds.size.height/100.0);
    } else {
        origin=GVMClampCardOrigin(origin,size,viewportLeft,viewportRight,viewportTop,viewportBottom);
    }
    CGRect frame=CGRectMake(origin.x,origin.y,size.width,size.height);
    if (card && card.compact!=compact) { card.compact=compact; [card setNeedsDisplay]; }
    if (card && !CGRectEqualToRect(card.frame,frame)) { card.frame=frame; [card setNeedsDisplay]; }
    return frame;
}

void GVMUpdateSpeedCard(UIView *map, NSNumber *speed, NSNumber *limit, NSArray<NSDictionary *> *alerts, const GVMTPMSData *tpms, BOOL night) {
    if (!ExternalMap(map) && !([objc_getAssociatedObject(map,phoneKey) boolValue] && NSThread.isMainThread && HostWindow(map).screen==UIScreen.mainScreen)) return;
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
    if (tpms) card.tpms = *tpms;
    
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

void GVMUpdatePhoneSpeedCard(UIView *host, NSNumber *speed, NSNumber *limit, NSArray<NSDictionary *> *alerts, const GVMTPMSData *tpms, BOOL night) {
    if (!host || !NSThread.isMainThread) return;
    objc_setAssociatedObject(host,phoneKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    GVMUpdateSpeedCard(host,speed,limit,alerts,tpms,night);
}

void GVMRemovePhoneSpeedCard(UIView *host) {
    UIView *card=objc_getAssociatedObject(host,cardKey);
    [card removeFromSuperview];
    objc_setAssociatedObject(host,cardKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host,phoneKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
