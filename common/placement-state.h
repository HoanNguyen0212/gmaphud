#import <Foundation/Foundation.h>

extern const char *GVMPlacementStateName;
uint64_t GVMEncodePlacement(NSString *full, NSString *dashboard);
BOOL GVMDecodePlacement(uint64_t state, NSUInteger *full, BOOL *dashboardLeft);

extern const char *GVMSizeStateName;
extern const char *GVMSizeChangedName;
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
