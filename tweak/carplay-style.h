#import <UIKit/UIKit.h>
#import "tpms-state.h"

void GVMStyleNativeSpeedView(UIView *view);
void GVMUpdateSpeedCard(UIView *map, NSDictionary *output, BOOL night);

CGRect GVMLayoutSpeedCard(UIView *map);
void GVMSetPlacementState(uint64_t state);

void GVMUpdatePhoneSpeedCard(UIView *host, NSDictionary *output, BOOL night);
void GVMRemovePhoneSpeedCard(UIView *host);
BOOL GVMBubbleEnabledForHost(UIView *host);
