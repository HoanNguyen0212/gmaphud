#import <UIKit/UIKit.h>
#import "tpms-state.h"

void GVMStyleNativeSpeedView(UIView *view);
void GVMUpdateSpeedCard(UIView *map, NSNumber *speed, NSNumber *limit, NSArray<NSDictionary *> *alerts, const GVMTPMSData *tpms, BOOL night);

CGRect GVMLayoutSpeedCard(UIView *map);
void GVMSetPlacementState(uint64_t state);

void GVMUpdatePhoneSpeedCard(UIView *host, NSNumber *speed, NSNumber *limit, NSArray<NSDictionary *> *alerts, const GVMTPMSData *tpms, BOOL night);
void GVMRemovePhoneSpeedCard(UIView *host);
