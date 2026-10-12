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

#include <math.h>
#include <notify.h>
const char *GVMSizeStateName="com.chou.gmaphud.size-state";
const char *GVMSizeChangedName="com.chou.gmaphud.size-changed";
NSUInteger GVMSizePercent(id value) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()) return 100;
    double number=[value doubleValue];
    return isfinite(number) ? (NSUInteger)lround(MAX(50,MIN(150,number))) : 100;
}
uint64_t GVMEncodeSizes(id full,id dashboard,id phone) {
    return (1ULL<<24) | GVMSizePercent(full) | (GVMSizePercent(dashboard)<<8) | (GVMSizePercent(phone)<<16);
}
NSUInteger GVMDecodeSize(uint64_t state,NSUInteger surface) {
    if (state>>24!=1 || surface>2) return 100;
    NSUInteger value=(state>>(surface*8))&255;
    return value>=50 && value<=150 ? value : 100;
}
void GVMPublishSavedSizes(void) {
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesAppSynchronize(domain);
    id full=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("fullScale"),domain));
    id dashboard=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("dashboardScale"),domain));
    id phone=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("phoneScale"),domain));
    static int token=-1;
    if (token<0 && notify_register_check(GVMSizeStateName,&token)!=NOTIFY_STATUS_OK) return;
    notify_set_state(token,GVMEncodeSizes(full,dashboard,phone));
    notify_post(GVMSizeStateName);
    static int phoneToken=-1;
    if (phoneToken<0 && notify_register_check(GVMPhonePlacementStateName,&phoneToken)!=NOTIFY_STATUS_OK) return;
    id corner=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("phonePosition"),domain));
    id x=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("phoneXPercent"),domain));
    id y=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("phoneYPercent"),domain));
    id layout=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("phoneLayout"),domain));
    notify_set_state(phoneToken,GVMEncodePhonePlacement(corner,x,y,layout));
    notify_post(GVMPhonePlacementStateName);
}

const char *GVMPhonePlacementStateName="com.chou.gmaphud.phone-placement-percent";
NSInteger GVMOffsetPercent(id value) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()) return 0;
    double number=[value doubleValue];
    return isfinite(number) ? (NSInteger)lround(MAX(-100,MIN(100,number))) : 0;
}
uint64_t GVMEncodePhonePlacement(NSString *corner,id x,id y,NSString *layout) {
    if (![corner isKindOfClass:NSString.class]) corner=nil;
    NSUInteger mode=[layout isKindOfClass:NSString.class] ? ([layout isEqual:@"horizontal"] ? 1 : [layout isEqual:@"vertical"] ? 2 : 0) : 0;
    return (2ULL<<32) | (GVMEncodePlacement(corner,nil)-1) | ((uint64_t)(GVMOffsetPercent(x)+100)<<2) | ((uint64_t)(GVMOffsetPercent(y)+100)<<10) | ((uint64_t)mode<<18);
}
void GVMDecodePhonePlacement(uint64_t state,NSUInteger *corner,NSInteger *x,NSInteger *y,NSUInteger *layout) {
    NSUInteger c=1,mode=0; NSInteger dx=0,dy=0;
    if ((state>>32)==2 && ((state>>20)&4095)==0 && ((state>>2)&255)<=200 && ((state>>10)&255)<=200 && ((state>>18)&3)<=2) {
        c=state&3; dx=(NSInteger)((state>>2)&255)-100; dy=(NSInteger)((state>>10)&255)-100; mode=(state>>18)&3;
    }
    if (corner) *corner=c; if (x) *x=dx; if (y) *y=dy; if (layout) *layout=mode;
}
NSInteger GVMOffsetPercentFromPoints(id value,double dimension) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID() || !isfinite(dimension) || dimension<=0) return 0;
    return GVMOffsetPercent(@([value doubleValue]*100.0/dimension));
}
void GVMMigratePhoneOffsets(double width,double height) {
    if (!isfinite(width) || !isfinite(height) || width<=0 || height<=0) return;
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesAppSynchronize(domain);
    NSArray *oldKeys=@[@"phoneX",@"phoneY"], *keys=@[@"phoneXPercent",@"phoneYPercent"];
    for (NSUInteger i=0;i<2;i++) {
        id saved=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)keys[i],domain));
        if (saved) continue;
        id old=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)oldKeys[i],domain));
        NSNumber *percent=@(GVMOffsetPercentFromPoints(old,i==0 ? width : height));
        CFPreferencesSetAppValue((__bridge CFStringRef)keys[i],(__bridge CFNumberRef)percent,domain);
    }
    CFPreferencesAppSynchronize(domain);
}
