#import <rootless.h>
#import "classic-card.h"
#import "speed-presentation.h"
#import "source-output.h"

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
static void DrawTire(NSString *pos, float press, uint8_t warn, BOOL active, CGRect rect, BOOL night) {
    if (!active) {
        UIColor *bg = RGB(night ? 0x181c22 : 0x323842, 0.6);
        UIBezierPath *box = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:6];
        [bg setFill]; [box fill];
        [RGB(0x404854, 0.5) setStroke]; box.lineWidth = 1; [box stroke];
        Text(@"--", CGRectMake(rect.origin.x, rect.origin.y + 2, rect.size.width, 13), 11, UIFontWeightMedium, RGB(0x888e99, 1));
        Text(pos, CGRectMake(rect.origin.x, rect.origin.y + 15, rect.size.width, 10), 8, UIFontWeightBold, RGB(0x666c77, 1));
        return;
    }
    UIColor *bg = warn == 1 ? RGB(0xff9f0a, 0.95) :  // warning low (amber)
                  warn >= 2 ? RGB(0xff3b30, 0.95) :  // warning high/leak/flat (red)
                  RGB(night ? 0x242b35 : 0x48515f, 0.85); // normal
    UIBezierPath *box = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:6];
    [bg setFill]; [box fill];
    [RGB(0x303947, 0.7) setStroke]; box.lineWidth = 1; [box stroke];
    NSString *text = [NSString stringWithFormat:@"%.1f", press];
    Text(text, CGRectMake(rect.origin.x, rect.origin.y + 2, rect.size.width, 13), 11, UIFontWeightBold, UIColor.whiteColor);
    Text(pos, CGRectMake(rect.origin.x, rect.origin.y + 15, rect.size.width, 10), 8, UIFontWeightBold, RGB(0xd0d4dc, 1));
}
@implementation GVMClassicSpeedCard
@synthesize speed=_speed, limit=_limit, alerts=_alerts, night=_night, compact=_compact, sourceID=_sourceID, moduleOrder=_moduleOrder, tpms=_tpms;
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    NSUInteger count=MIN(self.alerts.count,2);
    GVMCardSize canvas=GVMCardCanvasSize(GVMInterfaceClassic,count,self.compact);
    if (self.tpms.hasData) {
        if (self.compact) canvas.height += 65;
        else canvas.width += 80;
    }
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
    CGFloat modulesEnd = self.compact ? CGRectGetMaxY(body) : CGRectGetMaxX(body);
    if (self.tpms.hasData) {
        if (self.compact) body.size.height += 65;
        else body.size.width += 80;
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
    if (self.tpms.hasData) {
        if (self.compact) {
            CGFloat tpmsY = modulesEnd + 5;
            UIBezierPath *tpmsDiv = [UIBezierPath bezierPath];
            [tpmsDiv moveToPoint:CGPointMake(CGRectGetMinX(firstCell)+12, modulesEnd + 1)];
            [tpmsDiv addLineToPoint:CGPointMake(CGRectGetMaxX(firstCell)-12, modulesEnd + 1)];
            [RGB(0x303947, 0.65) setStroke]; tpmsDiv.lineWidth = 1; [tpmsDiv stroke];

            DrawTire(@"FL", self.tpms.fl.pressure, self.tpms.fl.warning, self.tpms.fl.active, CGRectMake(6, tpmsY, 34, 26), self.night);
            DrawTire(@"FR", self.tpms.fr.pressure, self.tpms.fr.warning, self.tpms.fr.active, CGRectMake(44, tpmsY, 34, 26), self.night);
            DrawTire(@"RL", self.tpms.rl.pressure, self.tpms.rl.warning, self.tpms.rl.active, CGRectMake(6, tpmsY + 30, 34, 26), self.night);
            DrawTire(@"RR", self.tpms.rr.pressure, self.tpms.rr.warning, self.tpms.rr.active, CGRectMake(44, tpmsY + 30, 34, 26), self.night);
        } else {
            CGFloat tpmsX = modulesEnd + 5;
            UIBezierPath *tpmsDiv = [UIBezierPath bezierPath];
            [tpmsDiv moveToPoint:CGPointMake(modulesEnd + 1, 34)];
            [tpmsDiv addLineToPoint:CGPointMake(modulesEnd + 1, 96)];
            [RGB(0x303947, 0.65) setStroke]; tpmsDiv.lineWidth = 1; [tpmsDiv stroke];

            DrawTire(@"FL", self.tpms.fl.pressure, self.tpms.fl.warning, self.tpms.fl.active, CGRectMake(tpmsX, 34, 34, 27), self.night);
            DrawTire(@"FR", self.tpms.fr.pressure, self.tpms.fr.warning, self.tpms.fr.active, CGRectMake(tpmsX + 38, 34, 34, 27), self.night);
            DrawTire(@"RL", self.tpms.rl.pressure, self.tpms.rl.warning, self.tpms.rl.active, CGRectMake(tpmsX, 65, 34, 27), self.night);
            DrawTire(@"RR", self.tpms.rr.pressure, self.tpms.rr.warning, self.tpms.rr.active, CGRectMake(tpmsX + 38, 65, 34, 27), self.night);
        }
    }
    CGContextRestoreGState(context);
}
@end
