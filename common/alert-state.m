#import "alert-state.h"
#include <math.h>

const char *const GVMFirstAlertStateName = "com.chou.googlemaps.vietmap.alert.first";
const char *const GVMSecondAlertStateName = "com.chou.googlemaps.vietmap.alert.second";
const char *const GVMTestFirstAlertStateName = "com.chou.googlemaps.vietmap.test.alert.first";
const char *const GVMTestSecondAlertStateName = "com.chou.googlemaps.vietmap.test.alert.second";

uint64_t GVMEncodeAlert(NSDictionary *alert, NSTimeInterval receivedAt) {
    if (![alert isKindOfClass:NSDictionary.class] || !isfinite(receivedAt) || receivedAt<0 ||
        receivedAt>=(double)(UINT64_MAX>>24)/1000) return 0;
    id provider=alert[@"provider"], kind=alert[@"kind"], distance=alert[@"distance"];
    if (![provider isKindOfClass:NSNumber.class] || ![kind isKindOfClass:NSNumber.class] ||
        [provider integerValue]<1 || [provider integerValue]>7 || [kind integerValue]<1 || [kind integerValue]>127) return 0;
    NSUInteger meters=16383;
    if (distance && distance!=NSNull.null) {
        if (![distance isKindOfClass:NSNumber.class]) return 0;
        double d=[distance doubleValue];
        if (!isfinite(d) || d<0 || d>10000 || floor(d)!=d) return 0;
        meters=(NSUInteger)d;
    }
    return ((uint64_t)floor(receivedAt*1000)<<24) | ((uint64_t)[provider unsignedIntegerValue]<<21) |
        ((uint64_t)[kind unsignedIntegerValue]<<14) | meters;
}
NSDictionary *GVMDecodeAlert(uint64_t state, NSTimeInterval uptime) {
    return GVMDecodeAlertWithin(state,uptime,5);
}
NSDictionary *GVMDecodeAlertWithin(uint64_t state, NSTimeInterval uptime, NSTimeInterval maxAge) {
    if (!state || !isfinite(uptime)) return nil;
    NSUInteger provider=(state>>21)&7, kind=(state>>14)&127, meters=state&16383;
    double age=uptime-(double)(state>>24)/1000;
    if (!provider || !kind || (meters>10000 && meters!=16383) ||
        !isfinite(maxAge) || maxAge<=0 || maxAge>300 || age<0 || age>=maxAge) return nil;
    return @{@"provider":@(provider),@"kind":@(kind),
        @"distance":meters==16383 ? NSNull.null : @(meters)};
}
