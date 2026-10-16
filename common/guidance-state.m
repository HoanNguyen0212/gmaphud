#import "guidance-state.h"
#include <math.h>

const char *const GVMGuidanceStateName = "com.chou.gmaphud.carplay.guidance";
// Four 12-bit fields in half points (up to 2047.5 pt), 15 bits of uptime seconds and a valid bit.
static const uint64_t Valid=1ULL<<63;
static BOOL Field(double value, uint64_t *out) {
    if (!isfinite(value) || value<0 || value>2047.5) return NO;
    *out=(uint64_t)llround(value*2);
    return YES;
}
uint64_t GVMEncodeGuidance(GVMGuidanceColumn c, NSTimeInterval uptime) {
    uint64_t x, w, card, eta;
    if (!Field(c.x,&x) || !Field(c.width,&w) || !Field(c.cardBottom,&card) || !Field(c.etaTop,&eta) ||
        w==0 || eta<card || !isfinite(uptime) || uptime<0) return 0;
    return Valid | x | (w<<12) | (card<<24) | (eta<<36) | (((uint64_t)uptime&32767)<<48);
}
BOOL GVMDecodeGuidance(uint64_t state, NSTimeInterval uptime, GVMGuidanceColumn *column) {
    if (!(state&Valid) || !isfinite(uptime) || uptime<0) return NO;
    uint64_t age=(((uint64_t)uptime&32767)+32768-((state>>48)&32767))&32767;
    GVMGuidanceColumn c={(state&4095)/2.0,((state>>12)&4095)/2.0,((state>>24)&4095)/2.0,((state>>36)&4095)/2.0};
    if (age>3 || c.width<=0 || c.etaTop<c.cardBottom) return NO;
    if (column) *column=c;
    return YES;
}
