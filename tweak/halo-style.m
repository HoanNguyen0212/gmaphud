#import "halo-style.h"
#import "source-output.h"
#import <CoreText/CoreText.h>
#import <rootless.h>

UIColor *GVMHaloColor(uint32_t rgb, CGFloat alpha) {
    return [UIColor colorWithRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:alpha];
}
uint32_t GVMHaloSourceColor(NSUInteger sourceID) {
    return sourceID==GVMSourceWaze ? 0x3FA9F5 : sourceID==GVMSourceGofa ? 0x9D7BFF :
        sourceID==GVMSourceVietMap ? 0x19C2B0 : GVMHaloIce;
}
NSString *GVMHaloSourceTag(NSUInteger sourceID) {
    return sourceID==GVMSourceWaze ? @"WAZE" : sourceID==GVMSourceGofa ? @"GOFA" :
        sourceID==GVMSourceVietMap ? @"VIETMAP" : @"GMAPHUD";
}

void GVMHaloRegisterFonts(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *folder=ROOT_PATH_NS(@"/usr/share/gmaphud/fonts");
        for (NSString *name in @[@"SairaCondensed-Bold",@"Saira-Medium",@"Saira-SemiBold",@"Saira-Bold"]) {
            NSURL *url=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:[name stringByAppendingString:@".ttf"]]];
            if ([NSFileManager.defaultManager fileExistsAtPath:url.path])
                CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url,kCTFontManagerScopeProcess,NULL);
        }
    });
}
static UIFont *Condensed(CGFloat size, UIFontWeight weight) {
    UIFont *system=[UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *descriptor=[system.fontDescriptor fontDescriptorWithSymbolicTraits:
        system.fontDescriptor.symbolicTraits|UIFontDescriptorTraitCondensed];
    return descriptor ? [UIFont fontWithDescriptor:descriptor size:size] : system;
}
UIFont *GVMHaloNumberFont(CGFloat size) {
    GVMHaloRegisterFonts();
    UIFont *font=[UIFont fontWithName:@"SairaCondensed-Bold" size:size] ?: Condensed(size,UIFontWeightBold);
    // Tabular figures keep the speed from jumping as digits change.
    UIFontDescriptor *tabular=[font.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorFeatureSettingsAttribute:
        @[@{UIFontFeatureTypeIdentifierKey:@(kNumberSpacingType),UIFontFeatureSelectorIdentifierKey:@(kMonospacedNumbersSelector)}]}];
    return [UIFont fontWithDescriptor:tabular size:size];
}
UIFont *GVMHaloFont(CGFloat size, UIFontWeight weight) {
    GVMHaloRegisterFonts();
    NSString *name=weight>=UIFontWeightBold ? @"Saira-Bold" : weight>=UIFontWeightSemibold ? @"Saira-SemiBold" : @"Saira-Medium";
    return [UIFont fontWithName:name size:size] ?: [UIFont systemFontOfSize:size weight:weight];
}
// Sign artwork is a sticker: the sign itself fills this share of the image.
static const CGFloat GVMStickerSign=0.86;
UIImage *GVMHaloSignArtwork(NSUInteger type, NSNumber *value) {
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
void GVMHaloDrawSticker(UIImage *image, CGPoint centre, CGFloat diameter) {
    CGFloat side=diameter/GVMStickerSign;
    // The sticker sits slightly above the image centre to leave room for its shadow.
    [image drawInRect:CGRectMake(centre.x-side/2,centre.y-side*0.477,side,side)];
}
void GVMHaloDrawSign(NSUInteger type, NSNumber *value, CGPoint centre, CGFloat diameter) {
    UIImage *artwork=GVMHaloSignArtwork(type,value);
    if (artwork) { GVMHaloDrawSticker(artwork,centre,diameter); return; }
    CGRect disc=CGRectMake(centre.x-diameter/2,centre.y-diameter/2,diameter,diameter);
    UIBezierPath *face=[UIBezierPath bezierPathWithOvalInRect:disc];
    [GVMHaloColor(GVMHaloInk900,0.95) setFill]; [face fill];
    face.lineWidth=3*diameter/58; [UIColor.whiteColor setStroke]; [face stroke];
    BOOL camera=type==GVMRoadAlertCameraAI || type==GVMRoadAlertPenaltyCamera || type==GVMRoadAlertSpeedCamera ||
        type==GVMRoadAlertTrafficCamera || type==GVMRoadAlertRedLightCamera;
    UIImage *symbol=[[UIImage systemImageNamed:camera ? @"video.fill" : @"exclamationmark.triangle.fill"]
        imageWithTintColor:GVMHaloColor(GVMHaloIce,1) renderingMode:UIImageRenderingModeAlwaysOriginal];
    CGFloat unit=diameter/58;
    [symbol drawInRect:CGRectMake(centre.x-17*unit,centre.y-15*unit,34*unit,30*unit)];
}
// Halo distance: 5 m steps below 100 m, 10 m below 1 km, one decimal below 10 km.
static NSArray<NSString *> *DistanceParts(id meters) {
    if (![meters isKindOfClass:NSNumber.class]) return @[@"",@""];
    double m=MAX(0,[meters doubleValue]);
    if (m<100) return @[[NSString stringWithFormat:@"%ld",lround(m/5)*5],@"m"];
    if (m<1000) return @[[NSString stringWithFormat:@"%ld",lround(m/10)*10],@"m"];
    if (m<10000) return @[[[NSString stringWithFormat:@"%.1f",round(m/100)/10] stringByReplacingOccurrencesOfString:@"." withString:@","],@"km"];
    return @[[NSString stringWithFormat:@"%ld",lround(m/1000)],@"km"];
}
void GVMHaloDrawDistanceTag(CGFloat centreX,CGFloat top,id meters,CGFloat progress) {
    NSArray<NSString *> *parts=DistanceParts(meters);
    if (!parts[0].length) return;
    UIFont *numberFont=GVMHaloNumberFont(15), *unitFont=GVMHaloFont(8,UIFontWeightBold);
    NSAttributedString *number=GVMHaloText(parts[0],numberFont,GVMHaloColor(GVMHaloInk050,1),0);
    NSAttributedString *unit=GVMHaloText(parts[1],unitFont,GVMHaloColor(GVMHaloInk200,1),0);
    CGFloat textWidth=number.size.width+2+unit.size.width;
    CGFloat width=MAX(56,textWidth+16);
    CGRect tag=CGRectMake(centreX-width/2,top,width,18);
    UIBezierPath *pill=[UIBezierPath bezierPathWithRoundedRect:tag cornerRadius:9];
    [GVMHaloColor(GVMHaloInk900,1) setFill]; [pill fill];
    if (progress>0) {
        CGContextRef context=UIGraphicsGetCurrentContext();
        CGContextSaveGState(context); [pill addClip];
        [GVMHaloColor(GVMHaloIce,0.24) setFill];
        UIRectFill(CGRectMake(tag.origin.x,tag.origin.y,tag.size.width*MIN(1,progress),tag.size.height));
        CGContextRestoreGState(context);
    }
    pill.lineWidth=1; [GVMHaloColor(GVMHaloInk600,1) setStroke]; [pill stroke];
    CGFloat baseline=CGRectGetMidY(tag)+5.5, x=CGRectGetMidX(tag)-textWidth/2;
    [number drawAtPoint:CGPointMake(x,baseline-numberFont.ascender)];
    [unit drawAtPoint:CGPointMake(x+number.size.width+2,baseline-unitFont.ascender)];
}
NSAttributedString *GVMHaloText(NSString *text, UIFont *font, UIColor *color, CGFloat tracking) {
    return [[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{NSFontAttributeName:font,
        NSForegroundColorAttributeName:color,NSKernAttributeName:@(font.pointSize*tracking)}];
}
