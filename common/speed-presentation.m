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
    GVMCardSize result = {0, 0, NO};
    if (!isfinite(availableWidth) || !isfinite(availableHeight) ||
        !isfinite(screenWidth) || !isfinite(screenHeight) ||
        availableWidth <= 0 || availableHeight <= 0 ||
        screenWidth <= 0 || screenHeight <= 0) return result;
    // Dashboard occupies part of the external display. Absolute width alone
    // mistakes large Dashboard panes for full maps and tiny full maps for panes.
    result.compact = availableWidth / screenWidth < 0.72;
    double displayScale = MIN(screenWidth / 400.0, screenHeight / 240.0);
    displayScale = MIN(1.4, MAX(0.75, displayScale));
    double canvasWidth = result.compact ? 84 : (cameraCount>=2 ? 296 : cameraCount ? 240 : 208);
    double canvasHeight = result.compact ? (cameraCount>=2 ? 350 : cameraCount ? 260 : 160) : 106;
    double scale = (result.compact ? 30.0 / 84 : 96.0 / 208) * displayScale;
    // Reserve the majority of the map for navigation, including short screens
    // and the space left when Google's toolbar appears.
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
