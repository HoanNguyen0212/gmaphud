#import <UIKit/UIKit.h>
void GVMStyleNativeSpeedView(UIView *view);
void GVMUpdateSpeedCard(UIView *map, NSDictionary *output, BOOL night);

CGRect GVMLayoutSpeedCard(UIView *map);
void GVMSetPlacementState(uint64_t state);

void GVMUpdatePhoneSpeedCard(UIView *host, NSDictionary *output, BOOL night);
void GVMRemovePhoneSpeedCard(UIView *host);
BOOL GVMBubbleEnabledForHost(UIView *host);
// Shows the TEST chip in the source tag while a test sample is on screen.
void GVMSetSpeedCardTest(UIView *map, BOOL test);
