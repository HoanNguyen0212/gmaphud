#import <rootless.h>
#import "carplay-style.h"
#import "overspeed-frame.h"
#import "speed-presentation.h"
#import "source-output.h"
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
static void DrawText(NSString *text, CGRect rect, UIFont *font, UIColor *color) {
    if (!text.length) return;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    CGSize measured=[text sizeWithAttributes:@{NSFontAttributeName:font}];
    CGFloat fit=MIN(1,MIN(rect.size.width/MAX(1,measured.width),rect.size.height/MAX(1,measured.height)));
    if (fit<1) font=[font fontWithSize:font.pointSize*fit];
    measured=[text sizeWithAttributes:@{NSFontAttributeName:font}];
    rect.origin.y+=(rect.size.height-measured.height)/2;
    rect.size.height=measured.height;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:font,
        NSForegroundColorAttributeName:color, NSParagraphStyleAttributeName:paragraph}];
}
static void Text(NSString *text, CGRect rect, CGFloat size, UIFontWeight weight, UIColor *color) {
    DrawText(text,rect,[UIFont monospacedDigitSystemFontOfSize:size weight:weight],color);
}
static UIFont *LimitFont(CGFloat size) {
    UIFont *font=[UIFont fontWithName:@"SFProCondensed-Semibold" size:size];
    if (font) return font;
    UIFont *system=[UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
    UIFontDescriptor *descriptor=[system.fontDescriptor fontDescriptorWithSymbolicTraits:
        system.fontDescriptor.symbolicTraits|UIFontDescriptorTraitCondensed];
    return descriptor ? [UIFont fontWithDescriptor:descriptor size:size] : system;
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
static UIImage *AlertArtwork(NSUInteger type,NSNumber *value) {
    NSString *name=GVMRoadAlertIconName(type,value);
    if (!name) return nil;
    static NSMutableDictionary<NSString *,UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache=[NSMutableDictionary new]; });
    UIImage *image=cache[name];
    if (!image) {
        image=[UIImage imageWithContentsOfFile:[ROOT_PATH_NS(@"/usr/share/gmaphud/gmaphud") stringByAppendingPathComponent:name]];
        if (image) cache[name]=image;
    }
    return image;
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
    UIBezierPath *bubble=[UIBezierPath bezierPathWithRoundedRect:body cornerRadius:self.compact ? body.size.width/2 : 24];
    [RGB(self.night ? 0x303642 : 0x59616f,0.60) setFill]; [bubble fill];
    [RGB(0x303947,0.8) setStroke]; bubble.lineWidth=1.5; [bubble stroke];
    if (count && self.compact) {
        UIBezierPath *sourceRegion=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(alertRegion,2,2) cornerRadius:18];
        [RGB(0x162b35,0.22) setFill]; [sourceRegion fill];
    }
    // Identical cells stay balanced even when the alert group is first or between values.
    CGRect firstCell=ModuleRect(@[@"speed",@"limit",@"alerts"],@"speed",self.compact,count,0);
    UIBezierPath *dividers=[UIBezierPath bezierPath];
    for (NSUInteger i=1;self.compact && i<2+count;i++) {
        CGFloat edge=self.compact ? firstCell.origin.y+i*firstCell.size.height : firstCell.origin.x+i*firstCell.size.width;
        [dividers moveToPoint:self.compact ? CGPointMake(CGRectGetMinX(firstCell)+12,edge) : CGPointMake(edge,CGRectGetMinY(firstCell)+12)];
        [dividers addLineToPoint:self.compact ? CGPointMake(CGRectGetMaxX(firstCell)-12,edge) : CGPointMake(edge,CGRectGetMaxY(firstCell)-12)];
    }
    [RGB(0x303947,0.35) setStroke]; dividers.lineWidth=1; [dividers stroke];

    // The visible rim and all alert artwork share a 64-point optical envelope.
    CGFloat signDiameter=64;
    CGRect signRect=CenteredRect(limitCell,signDiameter,signDiameter);
    if (!self.compact) signRect.origin.y=limitCell.origin.y+2;
    UIImage *limitArtwork=AlertArtwork(GVMRoadAlertSpeedLimit,self.limit);
    if (limitArtwork) DrawArtwork(limitArtwork,signRect);
    else {
        UIBezierPath *sign=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(signRect,3,3)];
        sign.lineWidth=self.limit ? 6 : 2.5;
        if (self.limit) {
            [UIColor.whiteColor setFill]; [sign fill]; [RGB(0xff3b30,1) setStroke];
        } else {
            CGFloat dash[]={5,3}; [sign setLineDash:dash count:2 phase:0]; [muted setStroke];
        }
        [sign stroke];
        DrawText(self.limit ? self.limit.stringValue : @"–",CGRectInset(signRect,7,7),
            LimitFont(self.limit.doubleValue>=100 ? 28 : 32),self.limit ? RGB(0x17191d,1) : muted);
    }
    CGRect speedGroup=CenteredRect(speedCell,speedCell.size.width-8,self.compact ? 62 : 84);
    CGFloat speedHeight=self.compact ? 44 : 64;
    DrawText(self.speed ? self.speed.stringValue : @"--",
        CGRectMake(speedGroup.origin.x,speedGroup.origin.y,speedGroup.size.width,speedHeight),
        LimitFont(self.compact ? 36 : 56),self.speed ? accent : muted);
    Text(@"km/h",CGRectMake(speedGroup.origin.x,speedGroup.origin.y+speedHeight+2,speedGroup.size.width,18),
        self.compact ? 14 : 16,UIFontWeightSemibold,muted);
    if (count) {
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
            if (!self.compact) alertRect.origin.y=cell.origin.y+2;
            UIImage *artwork=AlertArtwork([alert[@"type"] unsignedIntegerValue],alert[@"value"]);
            if (artwork) DrawArtwork(artwork,alertRect);
            else if ([alert[@"type"] unsignedIntegerValue]==GVMRoadAlertSpeedLimit) {
                UIBezierPath *nextLimit=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(alertRect,3,3)];
                [UIColor.whiteColor setFill]; [nextLimit fill]; [RGB(0xff3b30,1) setStroke];
                nextLimit.lineWidth=6; [nextLimit stroke];
                DrawText([alert[@"value"] stringValue],CGRectInset(alertRect,7,7),
                    LimitFont([alert[@"value"] doubleValue]>=100 ? 28 : 32),RGB(0x17191d,1));
            } else {
                BOOL camera=[alert[@"type"] unsignedIntegerValue]==GVMRoadAlertCameraAI ||
                    [alert[@"type"] unsignedIntegerValue]==GVMRoadAlertPenaltyCamera ||
                    [alert[@"type"] unsignedIntegerValue]==GVMRoadAlertSpeedCamera ||
                    [alert[@"type"] unsignedIntegerValue]==GVMRoadAlertTrafficCamera ||
                    [alert[@"type"] unsignedIntegerValue]==GVMRoadAlertRedLightCamera;
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
static void UpdateOverspeedBorder(UIView *map,NSDictionary *output) {
    static const void *key=&key;
    NSUInteger mode=GVMOverspeedMode();
    BOOL visible=ExternalMap(map) && GVMBubbleEnabledForHost(map);
    for (UIView *view=map;view;view=view.superview) if (view.hidden || view.alpha<=0.01) visible=NO;
    if (map.window.windowScene.activationState!=UISceneActivationStateForegroundActive) visible=NO;
    uint64_t lease=visible ? GVMEncodeOverspeedLease(output,NSProcessInfo.processInfo.systemUptime) : 0;
    // Hidden retained maps must not clear the visible map's shared warning.
    // With no visible publisher the bounded lease expires on its own.
    if (visible || mode!=2) GVMPublishOverspeedLease(mode==2 ? lease : 0);
    GVMOverspeedFrame *frame=objc_getAssociatedObject(map,key);
    if (mode==1 && lease && !frame) {
        frame=[[GVMOverspeedFrame alloc] initWithFrame:map.bounds]; [map.layer addSublayer:frame.layer];
        objc_setAssociatedObject(map,key,frame,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Draw inside the visible viewport so clipping/sidebar cannot remove an edge.
    CGRect viewport=map.bounds;
    UIWindow *window=map.window;
    if (window) {
        // Safe-area insets also reserve Google's buttons, not just the sidebar.
        // Intersect actual host geometry; coordinate conversion handles any screen ratio.
        CGRect visibleWindow=window.bounds;
        // Full map can extend under the CarPlay rail. Keep only the dominant
        // edge reservation; other safe-area edges belong to Google controls.
        CGSize screenSize=window.screen.bounds.size;
        BOOL dashboard=screenSize.width>0 && map.bounds.size.width/screenSize.width<0.72;
        if (!dashboard) {
            UIEdgeInsets rail=window.safeAreaInsets;
            CGFloat edge=MAX(MAX(rail.left,rail.right),MAX(rail.top,rail.bottom));
            UIEdgeInsets exclusion=UIEdgeInsetsZero;
            if (edge>0) {
                if (rail.left==edge) exclusion.left=edge;
                else if (rail.right==edge) exclusion.right=edge;
                else if (rail.top==edge) exclusion.top=edge;
                else exclusion.bottom=edge;
            }
            visibleWindow=UIEdgeInsetsInsetRect(visibleWindow,exclusion);
        }
        viewport=CGRectIntersection(viewport,[map convertRect:visibleWindow fromView:window]);
        for (UIView *parent=map.superview;parent;parent=parent.superview)
            if (parent.clipsToBounds) viewport=CGRectIntersection(viewport,[map convertRect:parent.bounds fromView:parent]);
    }
    BOOL valid=!CGRectIsNull(viewport) && !CGRectIsEmpty(viewport);
    frame.autoresizingMask=UIViewAutoresizingNone;
    frame.frame=valid ? viewport : CGRectZero;
    [frame setWarningLevel:mode==1 && valid ? (NSUInteger)(lease&3) : 0];
    if (frame && !frame.hidden) { [frame setNeedsLayout]; [frame layoutIfNeeded]; frame.layer.zPosition=10000; }
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
    if (ExternalMap(map)) UpdateOverspeedBorder(map,output);
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
