#import <Foundation/Foundation.h>
#include <stdint.h>

// The CarPlay navigation guidance column, in CarPlay screen points, as the template host draws it:
// its left edge and width, the bottom of the maneuver card and the top of the arrival estimates.
// Published by GMapHUDGuidanceRelay (CarPlayTemplateUIHost) twice a second with its uptime, so a
// reader can tell a live column from one left behind; 0 when no guidance card is shown.
extern const char *const GVMGuidanceStateName;
typedef struct { double x, width, cardBottom, etaTop; } GVMGuidanceColumn;
uint64_t GVMEncodeGuidance(GVMGuidanceColumn column, NSTimeInterval uptime);
// NO when there is no column or it is more than three seconds old.
BOOL GVMDecodeGuidance(uint64_t state, NSTimeInterval uptime, GVMGuidanceColumn *column);
