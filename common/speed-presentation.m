#import "speed-presentation.h"
#import "placement-state.h"
#include <math.h>
static const double GVMModuleExtent=88, GVMCardPadding=4;

GVMCardSize GVMCardCanvasSize(NSUInteger alerts,BOOL vertical) {
    double length=(2+MIN(alerts,2))*GVMModuleExtent+2*GVMCardPadding;
    double breadth=GVMModuleExtent+2*GVMCardPadding;
    return (GVMCardSize){vertical ? breadth : length,
        vertical ? length : breadth,vertical};
}
GVMWarning GVMWarningFor(NSNumber *speed, NSNumber *limit) {
    if (!speed || !limit || limit.doubleValue <= 0) return GVMWarningNormal;
    if (speed.doubleValue > limit.doubleValue) return GVMWarningOver;
    return speed.doubleValue >= MAX(0, limit.doubleValue - 5) ? GVMWarningNear : GVMWarningNormal;
}
double GVMProgressFor(NSNumber *speed, NSNumber *limit) {
    if (!speed || !limit || limit.doubleValue <= 0) return 0;
    return MIN(1, MAX(0, speed.doubleValue / limit.doubleValue));
}

GVMCardSize GVMCardSizeFor(double availableWidth, double availableHeight,
    double screenWidth, double screenHeight, NSUInteger cameraCount) {
    return GVMCarPlayCardSizeForView(availableWidth,availableHeight,availableWidth,screenWidth,screenHeight,cameraCount);
}
static GVMCardSize GVMCarPlayCardSize(double availableWidth,double availableHeight,
    double screenWidth,double screenHeight,NSUInteger alertCount,BOOL vertical) {
    GVMCardSize canvas=GVMCardCanvasSize(alertCount,vertical);
    double canvasWidth=canvas.width,canvasHeight=canvas.height;
    double displayScale=MIN(1.4,MAX(0.75,MIN(screenWidth/400,screenHeight/240)));
    GVMCardSize baseCanvas=GVMCardCanvasSize(0,vertical);
    double scale=(vertical ? 30.0/baseCanvas.width : 96.0/baseCanvas.width)*displayScale;
    double widthFraction=vertical ? 0.20 : 0.38;
    double heightFraction=vertical ? (alertCount>=2 ? 0.52 : 0.38) : 0.24;
    scale=MIN(scale,MIN(availableWidth*widthFraction/canvasWidth,availableHeight*heightFraction/canvasHeight));
    return (GVMCardSize){canvasWidth*scale,canvasHeight*scale,vertical};
}
GVMCardSize GVMCarPlayCardSizeForView(double availableWidth,double availableHeight,
    double viewWidth,double screenWidth,double screenHeight,NSUInteger cameraCount) {
    if (!isfinite(availableWidth) || !isfinite(availableHeight) ||
        !isfinite(screenWidth) || !isfinite(screenHeight) || !isfinite(viewWidth) || viewWidth<=0 ||
        availableWidth <= 0 || availableHeight <= 0 ||
        screenWidth <= 0 || screenHeight <= 0) return (GVMCardSize){0,0,NO};
    // Classify the actual map viewport, before navigation controls reserve space.
    // Guidance panels must not turn a full-map card into a Dashboard card.
    BOOL compact=viewWidth/screenWidth<0.72;
    // Reserve the majority of the viewport for navigation, including short screens.
    return GVMCarPlayCardSize(availableWidth,availableHeight,screenWidth,screenHeight,cameraCount,compact);
}
GVMCardOrigin GVMCardOriginFor(double left, double right, double top, double bottom,
    GVMCardSize size, GVMCardPlacement placement) {
    BOOL atLeft = placement == GVMCardTopLeft || placement == GVMCardBottomLeft;
    BOOL atBottom = placement == GVMCardBottomLeft || placement == GVMCardBottomRight;
    GVMCardOrigin origin = {atLeft ? left : MAX(left,right-size.width),
        atBottom ? MAX(top,bottom-size.height) : top};
    return origin;
}
GVMCardOrigin GVMClampCardOrigin(GVMCardOrigin origin,GVMCardSize size,
    double left,double right,double top,double bottom) {
    origin.x=MAX(left,MIN(MAX(left,right-size.width),origin.x));
    origin.y=MAX(top,MIN(MAX(top,bottom-size.height),origin.y));
    return origin;
}

GVMCardSize GVMScaleCardSize(GVMCardSize size,double percent,double width,double height) {
    if (!isfinite(percent)) percent=100;
    if (!isfinite(width) || !isfinite(height) || width<=0 || height<=0 || size.width<=0 || size.height<=0)
        return (GVMCardSize){0,0,size.compact};
    double scale=MAX(50,MIN(150,percent))/100;
    scale=MIN(scale,MIN(width/size.width,height/size.height));
    return (GVMCardSize){size.width*scale,size.height*scale,size.compact};
}

GVMCardSize GVMPhoneCardSizeFor(double width,double height,NSUInteger alerts) {
    return GVMPhoneCardSizeForLayout(width,height,alerts,0);
}
GVMCardSize GVMPhoneCardSizeForLayout(double width,double height,NSUInteger alerts,NSUInteger layout) {
    if (!isfinite(width) || !isfinite(height) || width<=0 || height<=0) return (GVMCardSize){0,0,NO};
    BOOL compact=layout==2 || (layout!=1 && height>width);
    GVMCardSize canvas=GVMCardCanvasSize(alerts,compact);
    double canvasWidth=canvas.width,canvasHeight=canvas.height;
    double scale=compact ? 0.55 : 0.70;
    scale=MIN(scale,MIN(width*0.6/canvasWidth,height*0.65/canvasHeight));
    return (GVMCardSize){canvasWidth*scale,canvasHeight*scale,compact};
}

GVMCardOrigin GVMPhoneCardOriginFor(double left,double right,double top,double bottom,
    GVMCardSize size,GVMCardPlacement placement,double offsetX,double offsetY) {
    GVMCardOrigin origin=GVMCardOriginFor(left,right,top,bottom,size,placement);
    origin.x+=offsetX;
    origin.y+=offsetY;
    return GVMClampCardOrigin(origin,size,left,right,top,bottom);
}

GVMCardSize GVMCarPlayCardSizeForLayout(double width,double height,double screenWidth,double screenHeight,NSUInteger alerts,BOOL dashboard,NSUInteger layout,double percent) {
    if (!isfinite(width) || !isfinite(height) || !isfinite(screenWidth) || !isfinite(screenHeight) ||
        width<=0 || height<=0 || screenWidth<=0 || screenHeight<=0) return (GVMCardSize){0,0,NO};
    BOOL vertical=layout==2 || (layout!=1 && dashboard);
    if (!dashboard)
        return GVMScaleCardSize(GVMCarPlayCardSize(width,height,screenWidth,screenHeight,alerts,vertical),percent,width,height);
    GVMCardSize canvas=GVMCardCanvasSize(alerts,vertical);
    GVMCardSize horizontal=GVMCardCanvasSize(2,NO),upright=GVMCardCanvasSize(2,YES);
    double displayScale=MIN(1.4,MAX(0.75,MIN(screenWidth/400,screenHeight/240)));
    double scale=30.0/GVMCardCanvasSize(0,YES).width*displayScale;
    if (!isfinite(percent)) percent=100;
    scale*=MAX(50,MIN(150,percent))/100;
    // Fit the largest supported group once for both arrangements. Adding/removing
    // alerts then changes only the group length, never the existing module scale.
    scale=MIN(scale,MIN(width/MAX(horizontal.width,upright.width),height/MAX(horizontal.height,upright.height)));
    return (GVMCardSize){canvas.width*scale,canvas.height*scale,vertical};
}

GVMModuleRect GVMModuleFrame(NSArray<NSString *> *order,NSString *module,BOOL vertical,
    NSUInteger alerts,NSUInteger alertIndex) {
    alerts=MIN(alerts,2);
    if ([module isEqual:@"alerts"] && alertIndex>=alerts) return (GVMModuleRect){0,0,0,0};
    double cursor=GVMCardPadding;
    for (NSString *item in GVMNormalizeModuleOrder(order,vertical)) {
        if ([item isEqual:module]) {
            if ([item isEqual:@"alerts"]) cursor+=alertIndex*GVMModuleExtent;
            return (GVMModuleRect){vertical ? GVMCardPadding : cursor,
                vertical ? cursor : GVMCardPadding,GVMModuleExtent,GVMModuleExtent};
        }
        cursor+=GVMModuleExtent*([item isEqual:@"alerts"] ? alerts : 1);
    }
    return (GVMModuleRect){0,0,0,0};
}
