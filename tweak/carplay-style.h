#import <UIKit/UIKit.h>
void GVMStyleNativeSpeedView(UIView *view);
void GVMUpdateSpeedCard(UIView *map, NSNumber *speed, NSNumber *limit, NSArray<NSDictionary *> *alerts, BOOL night);

CGRect GVMLayoutSpeedCard(UIView *map);
void GVMSetPlacementState(uint64_t state);

void GVMUpdatePhoneSpeedCard(UIView *host, NSNumber *speed, NSNumber *limit, NSArray<NSDictionary *> *alerts, BOOL night);
void GVMRemovePhoneSpeedCard(UIView *host);
