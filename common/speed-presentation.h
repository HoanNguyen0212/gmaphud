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
GVMCardOrigin GVMClampCardOrigin(GVMCardOrigin origin,GVMCardSize size,
    double left,double right,double top,double bottom);
GVMCardOrigin GVMCardOriginFor(double left, double right, double top, double bottom,
    GVMCardSize size, GVMCardPlacement placement);

GVMCardSize GVMScaleCardSize(GVMCardSize size, double percent, double width, double height);

GVMCardSize GVMPhoneCardSizeFor(double width, double height, NSUInteger alerts);

GVMCardSize GVMPhoneCardSizeForLayout(double width,double height,NSUInteger alerts,NSUInteger layout);

GVMCardOrigin GVMPhoneCardOriginFor(double left,double right,double top,double bottom,
    GVMCardSize size,GVMCardPlacement placement,double offsetX,double offsetY);

GVMCardSize GVMCarPlayCardSizeForView(double availableWidth,double availableHeight,
    double viewWidth,double screenWidth,double screenHeight,NSUInteger alerts);

GVMCardSize GVMCarPlayCardSizeForLayout(double width,double height,double screenWidth,double screenHeight,NSUInteger alerts,BOOL dashboard,NSUInteger layout,double percent);

// Each visible value or warning occupies one equal cell. Alerts move as a group.
typedef struct { double x, y, width, height; } GVMModuleRect;
GVMCardSize GVMCardCanvasSize(NSUInteger alerts,BOOL vertical);
GVMModuleRect GVMModuleFrame(NSArray<NSString *> *order,NSString *module,
    BOOL vertical,NSUInteger alerts,NSUInteger alertIndex);
