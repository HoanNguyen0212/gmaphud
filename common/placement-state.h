#import <Foundation/Foundation.h>

extern const char *GVMPlacementStateName;
uint64_t GVMEncodePlacement(NSString *full, NSString *dashboard);
BOOL GVMDecodePlacement(uint64_t state, NSUInteger *full, BOOL *dashboardLeft);
