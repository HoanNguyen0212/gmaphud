#import <Foundation/Foundation.h>

extern const char *GVMPlacementStateName;
uint64_t GVMEncodePlacement(NSString *full, NSString *dashboard);
BOOL GVMDecodePlacement(uint64_t state, NSUInteger *full, BOOL *dashboardLeft);

extern const char *GVMSizeStateName;
extern const char *GVMSizeChangedName;
extern const char *GVMBubbleVisibilityStateName;
uint64_t GVMEncodeBubbleVisibility(id enabled,id full,id dashboard,id phone);
BOOL GVMDecodeBubbleVisibility(uint64_t state,NSUInteger surface);
BOOL GVMBubbleEnabled(NSUInteger surface);
NSUInteger GVMSizePercent(id value);
uint64_t GVMEncodeSizes(id full, id dashboard, id phone);
NSUInteger GVMDecodeSize(uint64_t state, NSUInteger surface);
void GVMPublishSavedSizes(void);

extern const char *GVMPhonePlacementStateName;
NSInteger GVMOffsetPercent(id value);
uint64_t GVMEncodePhonePlacement(NSString *corner,id x,id y,NSString *layout);
void GVMDecodePhonePlacement(uint64_t state,NSUInteger *corner,NSInteger *x,NSInteger *y,NSUInteger *layout);

NSInteger GVMOffsetPercentFromPoints(id value,double dimension);
void GVMMigratePhoneOffsets(double width,double height);

extern const char *GVMBubbleConfigurationStateName;
NSArray<NSString *> *GVMNormalizeModuleOrder(id value,BOOL vertical);
uint64_t GVMEncodeBubbleConfiguration(NSArray *layouts,NSArray *orders);
NSUInteger GVMDecodeBubbleLayout(uint64_t state,NSUInteger surface);
NSArray<NSString *> *GVMDecodeModuleOrder(uint64_t state,NSUInteger surface,BOOL vertical);
