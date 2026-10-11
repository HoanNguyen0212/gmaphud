#import "placement-state.h"

const char *GVMPlacementStateName = "com.chou.gmaphud.placement-state";

uint64_t GVMEncodePlacement(NSString *full, NSString *dashboard) {
    NSUInteger corner=[full isEqualToString:@"top-left"] ? 0 :
        [full isEqualToString:@"bottom-left"] ? 2 :
        [full isEqualToString:@"bottom-right"] ? 3 : 1;
    return 1 + corner + ([dashboard isEqualToString:@"left"] ? 4 : 0);
}
BOOL GVMDecodePlacement(uint64_t state, NSUInteger *full, BOOL *dashboardLeft) {
    if (state<1 || state>8) return NO;
    if (full) *full=(NSUInteger)((state-1)%4);
    if (dashboardLeft) *dashboardLeft=(state-1)>=4;
    return YES;
}
