#import <rootless.h>
#import "carplay-style.h"
#import "speed-presentation.h"
#import "vietmap-alert-assets.h"
#import "placement-state.h"
#import "source-transport.h"
#import <objc/runtime.h>
#include <notify.h>

@interface GVMSpeedCard : UIView
@property(nonatomic, copy) NSNumber *speed, *limit;
@property(nonatomic, copy) NSArray<NSDictionary *> *alerts;
@property(nonatomic) BOOL night, compact;
@property(nonatomic) NSUInteger sourceID;
@property(nonatomic,copy) NSArray<NSString *> *moduleOrder;
@end

static UIColor *RGB(unsigned value, CGFloat alpha) {
    return [UIColor colorWithRed:((value >> 16) & 255)/255.0 green:((value >> 8) & 255)/255.0
        blue:(value & 255)/255.0 alpha:alpha];
}
static void Text(NSString *text, CGRect rect, CGFloat size, UIFontWeight weight, UIColor *color) {
    if (!text.length) return;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    UIFont *font=[UIFont monospacedDigitSystemFontOfSize:size weight:weight];
    CGSize measured=[text sizeWithAttributes:@{NSFontAttributeName:font}];
    CGFloat fit=MIN(1,MIN(rect.size.width/MAX(1,measured.width),rect.size.height/MAX(1,measured.height)));
    if (fit<1) font=[UIFont monospacedDigitSystemFontOfSize:size*fit weight:weight];
    measured=[text sizeWithAttributes:@{NSFontAttributeName:font}];
    rect.origin.y+=(rect.size.height-measured.height)/2;
    rect.size.height=measured.height;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:font,
        NSForegroundColorAttributeName:color, NSParagraphStyleAttributeName:paragraph}];
}
static CGRect ModuleRect(NSArray *order,NSString *module,BOOL vertical,NSUInteger count,NSUInteger index) {
    GVMModuleRect frame=GVMModuleFrame(order,module,vertical,count,index);
    return CGRectMake(frame.x,frame.y,frame.width,frame.height);
}
static CGRect CenteredRect(CGRect frame,CGFloat width,CGFloat height) {
    return CGRectMake(CGRectGetMidX(frame)-width/2,CGRectGetMidY(frame)-height/2,width,height);
}
static void DrawArtwork(UIImage *image,CGRect frame) {
    if (!image || image.size.width<=0 || image.size.height<=0) return;
    CGFloat scale=MIN(frame.size.width/image.size.width,frame.size.height/image.size.height);
    [image drawInRect:CenteredRect(frame,image.size.width*scale,image.size.height*scale)];
}
@implementation GVMSpeedCard
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    NSUInteger count=MIN(self.alerts.count,2);
    GVMCardSize canvas=GVMCardCanvasSize(count,self.compact);
    CGContextScaleCTM(context,self.bounds.size.width/canvas.width,self.bounds.size.height/canvas.height);
    GVMWarning warning = GVMWarningFor(self.speed, self.limit);
    UIColor *accent = warning == GVMWarningOver ? RGB(0xff6868,1) :
        warning == GVMWarningNear ? RGB(0xffd15c,1) : UIColor.whiteColor;
    UIColor *muted = RGB(0xe0e3e8,1);
    CGRect speedCell=ModuleRect(self.moduleOrder,@"speed",self.compact,count,0);
    CGRect limitCell=ModuleRect(self.moduleOrder,@"limit",self.compact,count,0);
    CGRect body=CGRectUnion(speedCell,limitCell);
    CGRect alertRegion=CGRectZero;
    for (NSUInteger i=0;i<count;i++) {
        CGRect cell=ModuleRect(self.moduleOrder,@"alerts",self.compact,count,i);
        body=CGRectUnion(body,cell);
        alertRegion=i ? CGRectUnion(alertRegion,cell) : cell;
    }
    body=CGRectInset(body,-3,-3);
    if (!self.compact) {
        CGFloat badgeX=(canvas.width-112)/2;
        UIBezierPath *badge=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(badgeX,1,112,32) cornerRadius:12];
        [RGB(0x202631,0.94) setFill]; [badge fill];
        Text(GVMSourceDisplayName(self.sourceID).uppercaseString,CGRectMake(badgeX+2,4,108,20),13,UIFontWeightBold,UIColor.whiteColor);
    }
    UIBezierPath *bubble=[UIBezierPath bezierPathWithRoundedRect:body cornerRadius:self.compact ? body.size.width/2 : 24];
    [RGB(self.night ? 0x303642 : 0x59616f,0.60) setFill]; [bubble fill];
    [RGB(0x303947,0.8) setStroke]; bubble.lineWidth=1.5; [bubble stroke];
    if (count) {
        UIBezierPath *sourceRegion=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(alertRegion,2,2) cornerRadius:18];
        [RGB(0x162b35,0.22) setFill]; [sourceRegion fill];
    }
    // Identical cells stay balanced even when the alert group is first or between values.
    CGRect firstCell=ModuleRect(@[@"speed",@"limit",@"alerts"],@"speed",self.compact,count,0);
    UIBezierPath *dividers=[UIBezierPath bezierPath];
    for (NSUInteger i=1;i<2+count;i++) {
        CGFloat edge=self.compact ? firstCell.origin.y+i*firstCell.size.height : firstCell.origin.x+i*firstCell.size.width;
        [dividers moveToPoint:self.compact ? CGPointMake(CGRectGetMinX(firstCell)+12,edge) : CGPointMake(edge,CGRectGetMinY(firstCell)+12)];
        [dividers addLineToPoint:self.compact ? CGPointMake(CGRectGetMaxX(firstCell)-12,edge) : CGPointMake(edge,CGRectGetMaxY(firstCell)-12)];
    }
    [RGB(0x303947,0.35) setStroke]; dividers.lineWidth=1; [dividers stroke];

    // The visible rim and all alert artwork share a 64-point optical envelope.
    CGFloat signDiameter=64;
    CGRect signRect=CenteredRect(limitCell,signDiameter,signDiameter);
    UIBezierPath *sign=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(signRect,3,3)];
    sign.lineWidth=self.limit ? 6 : 2.5;
    if (self.limit) {
        [UIColor.whiteColor setFill]; [sign fill]; [RGB(0xff3b30,1) setStroke];
    } else {
        CGFloat dash[]={5,3}; [sign setLineDash:dash count:2 phase:0]; [muted setStroke];
    }
    [sign stroke];
    Text(self.limit ? self.limit.stringValue : @"–",CGRectInset(signRect,7,7),
        self.limit.doubleValue>=100 ? 28 : 32,UIFontWeightBold,self.limit ? RGB(0x17191d,1) : muted);
    CGRect speedGroup=CenteredRect(speedCell,speedCell.size.width-8,62);
    Text(self.speed ? self.speed.stringValue : @"--",CGRectMake(speedGroup.origin.x,speedGroup.origin.y,speedGroup.size.width,44),
        36,UIFontWeightBold,self.speed ? accent : muted);
    Text(@"km/h",CGRectMake(speedGroup.origin.x,speedGroup.origin.y+44,speedGroup.size.width,18),14,UIFontWeightMedium,muted);
    if (count) {
        static NSMutableDictionary<NSNumber *, UIImage *> *artworkCache;
        static dispatch_once_t artworkOnce;
        dispatch_once(&artworkOnce, ^{ artworkCache=[NSMutableDictionary dictionary]; });
        for (NSUInteger i=0;i<count;i++) {
            NSDictionary *alert=self.alerts[i];
            id meters=alert[@"distance"];
            NSString *distance=(!meters || meters==NSNull.null) ? @"" : ([meters integerValue]>=1000 ?
                [NSString stringWithFormat:@"%.1f km",[meters doubleValue]/1000] :
                [NSString stringWithFormat:@"%@ m",meters]);
            CGRect cell=ModuleRect(self.moduleOrder,@"alerts",self.compact,count,i);
            CGFloat groupHeight=signDiameter+(distance.length ? 20 : 0);
            CGRect group=CenteredRect(cell,cell.size.width-8,groupHeight);
            CGRect alertRect=CGRectMake(CGRectGetMidX(cell)-signDiameter/2,group.origin.y,signDiameter,signDiameter);
            NSNumber *kind=alert[@"artworkID"];
            NSNumber *cacheKey=@((self.sourceID<<8)|kind.unsignedIntegerValue);
            UIImage *artwork=artworkCache[cacheKey];
            if (!artwork && self.sourceID==GVMVietMapProviderID) {
                NSString *name=GVMVietMapAssetName(kind.unsignedIntegerValue);
                if (name) {
                    NSString *path=[ROOT_PATH_NS(@"/usr/share/gmaphud/vietmap") stringByAppendingPathComponent:name];
                    artwork=[UIImage imageWithContentsOfFile:path];
                    if (artwork) artworkCache[cacheKey]=artwork;
                }
            }
            if (artwork) DrawArtwork(artwork,alertRect);
            else if ([alert[@"type"] unsignedIntegerValue]==GVMRoadAlertSpeedLimit) {
                UIBezierPath *nextLimit=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(alertRect,3,3)];
                [UIColor.whiteColor setFill]; [nextLimit fill]; [RGB(0xff3b30,1) setStroke];
                nextLimit.lineWidth=6; [nextLimit stroke];
                Text([alert[@"value"] stringValue],CGRectInset(alertRect,7,7),
                    [alert[@"value"] doubleValue]>=100 ? 28 : 32,UIFontWeightBold,RGB(0x17191d,1));
            } else {
                BOOL camera=[alert[@"type"] unsignedIntegerValue]==GVMRoadAlertCameraAI ||
                    [alert[@"type"] unsignedIntegerValue]==GVMRoadAlertPenaltyCamera ||
                    [alert[@"type"] unsignedIntegerValue]==GVMRoadAlertSpeedCamera ||
                    [alert[@"type"] unsignedIntegerValue]==GVMRoadAlertTrafficCamera;
                UIImage *symbol=[[UIImage systemImageNamed:camera ? @"camera.fill" : @"exclamationmark.triangle.fill"]
                    imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
                DrawArtwork(symbol,CGRectInset(alertRect,5,5));
            }
            Text(distance,CGRectMake(group.origin.x,CGRectGetMaxY(alertRect)+2,group.size.width,18),14,UIFontWeightMedium,UIColor.whiteColor);
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
BOOL GVMBubbleEnabledForHost(UIView *host) {
    BOOL phone=[objc_getAssociatedObject(host,phoneKey) boolValue];
    CGFloat screenWidth=HostWindow(host).screen.bounds.size.width;
    BOOL dashboard=!phone && screenWidth>0 && host.bounds.size.width/screenWidth<0.72;
    return GVMBubbleEnabled(phone ? 2 : dashboard ? 1 : 0);
}
void GVMStyleNativeSpeedView(UIView *view) {
    UIView *owner = view.superview;
    while (owner && ![owner isKindOfClass:NSClassFromString(@"AZCarPlayView")]) owner=owner.superview;
    if (ExternalMap(owner)) view.alpha=0; // Keep Google's model/layout boundary, replace only its artwork.
}
CGRect GVMLayoutSpeedCard(UIView *map) {
    BOOL phone=[objc_getAssociatedObject(map,phoneKey) boolValue];
    if (!ExternalMap(map) && !(phone && NSThread.isMainThread && HostWindow(map).screen==UIScreen.mainScreen)) return CGRectZero;
    GVMSpeedCard *card = objc_getAssociatedObject(map,cardKey);
    card.hidden=!GVMBubbleEnabledForHost(map);
    if (card.hidden) return card.frame;
    CGRect screen=HostWindow(map).screen.bounds;
    UIEdgeInsets insets=map.safeAreaInsets;
    CGFloat margin=MIN(10,MAX(5,MIN(screen.size.width,screen.size.height)*0.03));
    // Google propagates horizontal control exclusions into map/window safe
    // areas. Anchor to the map bounds so disappearing alerts cannot shift it.
    CGFloat left=CGRectGetMinX(map.bounds)+margin;
    CGFloat right=CGRectGetMaxX(map.bounds)-margin;
    CGFloat top=CGRectGetMinY(map.bounds)+margin;
    CGFloat bottom=CGRectGetMaxY(map.bounds)-margin;
    if (phone) {
        // Phone placement spans the whole app window, including system safe areas.
        left=CGRectGetMinX(map.bounds); right=CGRectGetMaxX(map.bounds);
        top=CGRectGetMinY(map.bounds); bottom=CGRectGetMaxY(map.bounds);
    }
    NSUInteger phoneLayout=0;
    NSUInteger phoneCorner=1; NSInteger offsetX=0,offsetY=0;
    GVMCardSize size={0,0,NO};
    if (phone) {
        static int token=-1; uint64_t state=0;
        if (token<0) notify_register_check(GVMPhonePlacementStateName,&token);
        if (token>=0) notify_get_state(token,&state);
        GVMDecodePhonePlacement(state,&phoneCorner,&offsetX,&offsetY,&phoneLayout);
        size=GVMPhoneCardSizeForLayout(map.bounds.size.width,map.bounds.size.height,card.alerts.count,phoneLayout);
    }
    BOOL dashboard=!phone && map.bounds.size.width/screen.size.width<0.72;
    NSUInteger surface=phone ? 2 : dashboard ? 1 : 0;
    static int configurationToken=-1; uint64_t configuration=0;
    if (configurationToken<0) notify_register_check(GVMBubbleConfigurationStateName,&configurationToken);
    if (configurationToken>=0) notify_get_state(configurationToken,&configuration);
    if (!phone) {
        NSUInteger layout=GVMDecodeBubbleLayout(configuration,surface);
        size=GVMCarPlayCardSizeForLayout(MAX(0,right-left),MAX(0,bottom-top),screen.size.width,
            screen.size.height,card.alerts.count,dashboard,layout,SizePercent(surface));
    }
    NSArray *moduleOrder=GVMDecodeModuleOrder(configuration,surface,size.compact);
    if (![card.moduleOrder isEqual:moduleOrder]) { card.moduleOrder=moduleOrder; [card setNeedsDisplay]; }
    BOOL compact=size.compact;
    GVMCardPlacement placement=phone ? (GVMCardPlacement)phoneCorner : dashboard ? (dashboardLeft ? GVMCardTopLeft : GVMCardTopRight) : fullPlacement;
    // Size belongs to the viewport and user preference, never to the chosen
    // corner or the space left by Google's navigation controls.
    if (phone) size=GVMScaleCardSize(size,SizePercent(surface),MAX(0,right-left),MAX(0,bottom-top));
    CGFloat viewportLeft=left, viewportRight=right, viewportTop=top, viewportBottom=bottom;
    if (!phone) {
        top+=insets.top;
        bottom-=insets.bottom;
        if (placement==GVMCardTopLeft || placement==GVMCardBottomLeft) left+=insets.left;
        if (placement==GVMCardBottomRight) right-=insets.right;
        if (placement==GVMCardBottomLeft || placement==GVMCardBottomRight)
            bottom-=MAX(0,25-insets.bottom); // Leave Google's map attribution clear.
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
void GVMUpdateSpeedCard(UIView *map, NSDictionary *output, BOOL night) {
    NSNumber *speed=output[@"speed"][@"value"], *limit=output[@"speedLimit"][@"value"];
    // Freshness is validated upstream; a new receive time alone must not repaint.
    NSMutableArray *visibleAlerts=[NSMutableArray new];
    for (NSDictionary *alert in output[@"alerts"])
        [visibleAlerts addObject:@{@"type":alert[@"type"],@"value":alert[@"value"],
            @"distance":alert[@"distance"],@"artworkID":alert[@"artworkID"]}];
    NSArray *alerts=[visibleAlerts copy];
    NSUInteger sourceID=output ? [output[@"sourceID"] unsignedIntegerValue] : GVMSelectedSourceID();
    if (!ExternalMap(map) && !([objc_getAssociatedObject(map,phoneKey) boolValue] && NSThread.isMainThread && HostWindow(map).screen==UIScreen.mainScreen)) return;
    GVMSpeedCard *card = objc_getAssociatedObject(map,cardKey);
    if (!GVMBubbleEnabledForHost(map)) { card.hidden=YES; return; }
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
    BOOL changed = card.sourceID!=sourceID || alertsChanged || !CGRectEqualToRect(card.frame,frame) || card.night!=night ||
        !((card.speed==speed)||[card.speed isEqual:speed]) || !((card.limit==limit)||[card.limit isEqual:limit]);
    card.sourceID=sourceID; card.frame=frame; card.speed=speed; card.limit=limit; card.night=night;
    if (changed) [card setNeedsDisplay];
    card.accessibilityLabel=[NSString stringWithFormat:@"Speed %@ km/h, limit %@ km/h", speed ?: @"unavailable",limit ?: @"unavailable"];
    for (NSDictionary *alert in alerts) {
        NSString *name=GVMRoadAlertName([alert[@"type"] unsignedIntegerValue]) ?: @"road warning";
        id meters=alert[@"distance"];
        card.accessibilityLabel=[card.accessibilityLabel stringByAppendingFormat:@", %@ %@%@%@",GVMSourceDisplayName(sourceID),name,
            alert[@"value"]==NSNull.null ? @"" : [NSString stringWithFormat:@" %@ km/h",alert[@"value"]],
            meters==NSNull.null ? @"" : [NSString stringWithFormat:@" %@ meters",meters]];
    }
    [map bringSubviewToFront:card];
}

void GVMUpdatePhoneSpeedCard(UIView *host,NSDictionary *output,BOOL night) {
    if (!host || !NSThread.isMainThread) return;
    objc_setAssociatedObject(host,phoneKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    GVMUpdateSpeedCard(host,output,night);
}
void GVMRemovePhoneSpeedCard(UIView *host) {
    UIView *card=objc_getAssociatedObject(host,cardKey);
    [card removeFromSuperview];
    objc_setAssociatedObject(host,cardKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host,phoneKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
