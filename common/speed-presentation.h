#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, GVMWarning) { GVMWarningNormal, GVMWarningNear, GVMWarningOver };
GVMWarning GVMWarningFor(NSNumber *speed, NSNumber *limit);
double GVMProgressFor(NSNumber *speed, NSNumber *limit);

// All dimensions use UIKit points; scale stays uniform across the artwork.
typedef struct {
    double width;
    double height;
    BOOL compact;
} GVMCardSize;
GVMCardSize GVMCardSizeFor(double availableWidth, double availableHeight,
    double screenWidth, double screenHeight, NSUInteger cameraCount);
typedef NS_ENUM(NSInteger, GVMCardPlacement) {
    GVMCardTopLeft, GVMCardTopRight, GVMCardBottomLeft, GVMCardBottomRight
};
typedef struct { double x; double y; } GVMCardOrigin;
GVMCardOrigin GVMCardOriginFor(double left, double right, double top, double bottom,
    GVMCardSize size, GVMCardPlacement placement);
