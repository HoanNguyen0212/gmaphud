#import "speed-presentation.h"
#include <math.h>
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
GVMCardSize GVMCarPlayCardSizeForView(double availableWidth,double availableHeight,
    double viewWidth,double screenWidth,double screenHeight,NSUInteger cameraCount) {
    GVMCardSize result = {0, 0, NO};
    if (!isfinite(availableWidth) || !isfinite(availableHeight) ||
        !isfinite(screenWidth) || !isfinite(screenHeight) || !isfinite(viewWidth) || viewWidth<=0 ||
        availableWidth <= 0 || availableHeight <= 0 ||
        screenWidth <= 0 || screenHeight <= 0) return result;
    // Classify the actual map viewport, before navigation controls reserve space.
    // Guidance panels must not turn a full-map card into a Dashboard card.
    result.compact = viewWidth / screenWidth < 0.72;
    double displayScale = MIN(screenWidth / 400.0, screenHeight / 240.0);
    displayScale = MIN(1.4, MAX(0.75, displayScale));
    double canvasWidth = result.compact ? 84 : (cameraCount>=2 ? 296 : cameraCount ? 240 : 208);
    double canvasHeight = result.compact ? (cameraCount>=2 ? 350 : cameraCount ? 260 : 160) : 106;
    double scale = (result.compact ? 30.0 / 84 : 96.0 / 208) * displayScale;
    // Reserve the majority of the viewport for navigation, including short screens.
    scale = MIN(scale, availableWidth * (result.compact ? 0.20 : 0.38) / canvasWidth);
    scale = MIN(scale, availableHeight * (result.compact ? (cameraCount>=2 ? 0.52 : 0.38) : 0.24) / canvasHeight);
    result.width = canvasWidth * scale;
    result.height = canvasHeight * scale;
    return result;
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
    double canvasWidth=compact ? 84 : alerts>=2 ? 296 : alerts ? 240 : 208;
    double canvasHeight=compact ? (alerts>=2 ? 350 : alerts ? 260 : 160) : 106;
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
