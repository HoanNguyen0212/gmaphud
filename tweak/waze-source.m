#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <notify.h>
#import "alert-state.h"
#import "waze-output.h"
#import "source-transport.h"
#import "speed-state.h"
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif
#include <string.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#include <math.h>

static GVMWazeOutputStore *store;
static int requestToken=-1;
static double lastStatusTime=-1;
static void Publish(BOOL force);
// Bounded support inventory; no IDs, coordinates, titles or accounts.
static void ObserveAlert(NSString *icon,NSInteger type,NSInteger subtype,NSInteger trait,
                         NSInteger distance,BOOL valid,BOOL passed,double uptime) {
    if (![icon isKindOfClass:NSString.class] || icon.length>128 || !isfinite(uptime)) return;
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    if ([icon rangeOfCharacterFromSet:allowed.invertedSet].location!=NSNotFound) return;
    static NSMutableDictionary *catalog;
    static BOOL pending;
    if (!catalog) catalog=[NSMutableDictionary new];
    NSString *key=[NSString stringWithFormat:@"%ld:%ld:%ld:%@",(long)type,(long)subtype,(long)trait,icon];
    NSDictionary *previous=catalog[key];
    if (!previous && catalog.count>=64) return;
    if (previous && [previous[@"valid"] boolValue]==valid && [previous[@"passed"] boolValue]==passed) return;
    catalog[key]=@{@"icon":icon,@"type":@(type),@"subtype":@(subtype),@"trait":@(trait),
        @"distance":distance>=0 && distance<=10000 ? @(distance) : NSNull.null,
        @"valid":@(valid),@"passed":@(passed),@"uptime":@(uptime),
        @"appState":@(UIApplication.sharedApplication.applicationState)};
    // Coalesce semantic/lifecycle changes; never renew source timestamps.
    if (pending) return;
    pending=YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        pending=NO;
        NSData *data=[NSJSONSerialization dataWithJSONObject:catalog.allValues options:NSJSONWritingSortedKeys error:nil];
        [data writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-waze-alert-catalog.json"] atomically:YES];
    });
}

static uint64_t (*ReadNativeLimit)(void);
// Set once a native GPS position has been processed, so the native limit state exists.
static BOOL nativeLimitReady;
static NSString *limitGuardStatus=@"not checked";
typedef id (*GPSInit)(id __attribute__((ns_consumed)),SEL,double,double,double,double,double,double,double,BOOL,double,double) __attribute__((ns_returns_retained));
static GPSInit OriginalGPS;
static id GPS(id self __attribute__((ns_consumed)),SEL cmd,double longitude,double latitude,double altitude,
 double speed,double steering,double accuracy,double time,BOOL hasSteering,double speedAccuracy,double steeringAccuracy) __attribute__((ns_returns_retained));
static id GPS(id self __attribute__((ns_consumed)),SEL cmd,double longitude,double latitude,double altitude,
 double speed,double steering,double accuracy,double time,BOOL hasSteering,double speedAccuracy,double steeringAccuracy) {
    id result=OriginalGPS(self,cmd,longitude,latitude,altitude,speed,steering,accuracy,time,hasSteering,speedAccuracy,steeringAccuracy);
    double now=NSDate.date.timeIntervalSince1970;
    double uptime=NSProcessInfo.processInfo.systemUptime;
    dispatch_async(dispatch_get_main_queue(), ^{
        // A delayed queue must not make the original GPS sample fresh again.
        double current=NSProcessInfo.processInfo.systemUptime;
        if (current-uptime>=5) return;
        uint64_t limit=ReadNativeLimit ? ReadNativeLimit() : 0;
        nativeLimitReady=ReadNativeLimit!=NULL;
        [store updateSpeed:speed timestamp:time now:now uptime:uptime optionalLimit:limit];
        Publish(NO);
        if (lastStatusTime<0 || current-lastStatusTime>=5) {
            lastStatusTime=current;
            NSDictionary *output=[store outputAtUptime:current];
            NSString *line=[NSString stringWithFormat:@"speed=%@ limit=%@ guard=%@ appState=%ld rawMMSec=%.2f sampleAge=%.3f uptime=%.2f",
                output[@"speed"][@"value"] ?: @"unavailable",output[@"speedLimit"][@"value"] ?: @"unavailable",
                limitGuardStatus,(long)UIApplication.sharedApplication.applicationState,speed,now-time,current];
            [line writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-waze-gps.status"]
                atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    });
    return result;
}
static void ConfigureNativeLimit(void) {
    const uint8_t expectedUUID[]={0x90,0x94,0x7e,0x86,0xbf,0xf2,0x34,0x34,0xa2,0x8b,0x97,0x9c,0x65,0xdb,0x88,0x46};
    BOOL matched=NO;
    intptr_t slide=0;
    // Injection can reorder dyld images: locate the verified Waze image by UUID.
    for (uint32_t image=0;image<_dyld_image_count() && !matched;image++) {
        const struct mach_header_64 *header=(const struct mach_header_64 *)_dyld_get_image_header(image);
        if (!header || header->magic!=MH_MAGIC_64) continue;
        const struct load_command *command=(const struct load_command *)(header+1);
        for (uint32_t i=0;i<header->ncmds;i++) {
            if (command->cmd==LC_UUID && !memcmp(((const struct uuid_command *)command)->uuid,expectedUUID,16)) {
                matched=YES; slide=_dyld_get_image_vmaddr_slide(image); break;
            }
            command=(const struct load_command *)((const uint8_t *)command+command->cmdsize);
        }
    }
    if (!matched) { limitGuardStatus=@"Waze image UUID mismatch"; return; }
    const uint8_t expected[]={0xff,0xc3,0x00,0xd1,0xf4,0x4f,0x01,0xa9,0xfd,0x7b,0x02,0xa9,0xfd,0x83,0x00,0x91};
    void *address=(void *)(slide+0x101028ff4);
    if (memcmp(address,expected,sizeof(expected))) {
        NSMutableString *bytes=[NSMutableString stringWithString:@"entry:"];
        for (unsigned i=0;i<16;i++) [bytes appendFormat:@"%02x",((uint8_t *)address)[i]];
        limitGuardStatus=bytes; return;
    }
    limitGuardStatus=@"matched";
#if __has_feature(ptrauth_calls)
    address=ptrauth_sign_unauthenticated(address,ptrauth_key_function_pointer,0);
#endif
    ReadNativeLimit=(uint64_t (*)(void))address;
}
static void Status(NSString *message) {
    [message writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-waze-source.status"]
             atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static void Publish(BOOL force) {
    double now=NSProcessInfo.processInfo.systemUptime;
    GVMPublishSourceOutput([store outputAtUptime:now],now,force);
}

// Waze 5.25.0 measured signature. Preserve init-family ownership and all arguments.
typedef id (*DescriptorInit)(id __attribute__((ns_consumed)), SEL, id alertId, NSInteger priority, BOOL isPreemptive, BOOL isValid, NSInteger distanceMeters, id title, id carplayTitle, id alertDescription, id carplayAlertDescription, id iconName, BOOL isCancellable, BOOL canSendThumbsUp, BOOL isCloseOnly, id primaryButtonText, id secondaryButtonText, BOOL disableCompactEtaBarTaps, BOOL showDistance, BOOL keepOpenAfterAction, BOOL closeOnlyOnSelection, double timeoutSeconds, NSInteger timerType, id zoneAlertData, BOOL shouldShowStillThere, BOOL didPassAlert, NSInteger triggerDistanceMeters, BOOL primaryButtonIsClose, BOOL secondaryButtonIsClose, BOOL shouldShowFocusedAlert, NSInteger silentActivationReason, id coordinate, BOOL shouldCheckDistanceFromLastAlert, NSInteger statsAlertId, NSInteger statsType, NSInteger statsSubtype, NSInteger statsSubtypeTrait, id statsUniqueId, BOOL dismissImmediatelyUponRemoval, BOOL isApproachingWithValidationHasValue, BOOL isApproachingWithValidation, BOOL hideActionsWhenInvalid, BOOL showOnCarPlayDashboard, BOOL doNotHideOnMapMovement) __attribute__((ns_returns_retained));
static DescriptorInit OriginalDescriptor;
static id Descriptor(id self __attribute__((ns_consumed)), SEL cmd, id alertId, NSInteger priority, BOOL isPreemptive, BOOL isValid, NSInteger distanceMeters, id title, id carplayTitle, id alertDescription, id carplayAlertDescription, id iconName, BOOL isCancellable, BOOL canSendThumbsUp, BOOL isCloseOnly, id primaryButtonText, id secondaryButtonText, BOOL disableCompactEtaBarTaps, BOOL showDistance, BOOL keepOpenAfterAction, BOOL closeOnlyOnSelection, double timeoutSeconds, NSInteger timerType, id zoneAlertData, BOOL shouldShowStillThere, BOOL didPassAlert, NSInteger triggerDistanceMeters, BOOL primaryButtonIsClose, BOOL secondaryButtonIsClose, BOOL shouldShowFocusedAlert, NSInteger silentActivationReason, id coordinate, BOOL shouldCheckDistanceFromLastAlert, NSInteger statsAlertId, NSInteger statsType, NSInteger statsSubtype, NSInteger statsSubtypeTrait, id statsUniqueId, BOOL dismissImmediatelyUponRemoval, BOOL isApproachingWithValidationHasValue, BOOL isApproachingWithValidation, BOOL hideActionsWhenInvalid, BOOL showOnCarPlayDashboard, BOOL doNotHideOnMapMovement) __attribute__((ns_returns_retained));
static id Descriptor(id self __attribute__((ns_consumed)), SEL cmd, id alertId, NSInteger priority, BOOL isPreemptive, BOOL isValid, NSInteger distanceMeters, id title, id carplayTitle, id alertDescription, id carplayAlertDescription, id iconName, BOOL isCancellable, BOOL canSendThumbsUp, BOOL isCloseOnly, id primaryButtonText, id secondaryButtonText, BOOL disableCompactEtaBarTaps, BOOL showDistance, BOOL keepOpenAfterAction, BOOL closeOnlyOnSelection, double timeoutSeconds, NSInteger timerType, id zoneAlertData, BOOL shouldShowStillThere, BOOL didPassAlert, NSInteger triggerDistanceMeters, BOOL primaryButtonIsClose, BOOL secondaryButtonIsClose, BOOL shouldShowFocusedAlert, NSInteger silentActivationReason, id coordinate, BOOL shouldCheckDistanceFromLastAlert, NSInteger statsAlertId, NSInteger statsType, NSInteger statsSubtype, NSInteger statsSubtypeTrait, id statsUniqueId, BOOL dismissImmediatelyUponRemoval, BOOL isApproachingWithValidationHasValue, BOOL isApproachingWithValidation, BOOL hideActionsWhenInvalid, BOOL showOnCarPlayDashboard, BOOL doNotHideOnMapMovement) {
    id result = OriginalDescriptor(self, cmd, alertId, priority, isPreemptive, isValid, distanceMeters, title, carplayTitle, alertDescription, carplayAlertDescription, iconName, isCancellable, canSendThumbsUp, isCloseOnly, primaryButtonText, secondaryButtonText, disableCompactEtaBarTaps, showDistance, keepOpenAfterAction, closeOnlyOnSelection, timeoutSeconds, timerType, zoneAlertData, shouldShowStillThere, didPassAlert, triggerDistanceMeters, primaryButtonIsClose, secondaryButtonIsClose, shouldShowFocusedAlert, silentActivationReason, coordinate, shouldCheckDistanceFromLastAlert, statsAlertId, statsType, statsSubtype, statsSubtypeTrait, statsUniqueId, dismissImmediatelyUponRemoval, isApproachingWithValidationHasValue, isApproachingWithValidation, hideActionsWhenInvalid, showOnCarPlayDashboard, doNotHideOnMapMovement);
    @try {
        Class idClass=NSClassFromString(@"Waze.CommonCodeAlertId");
        SEL selector=sel_registerName("commonCodeUniqueId");
        Method method=class_getInstanceMethod(idClass,selector);
        if (idClass && [alertId isKindOfClass:idClass] && method &&
            !strcmp(method_getTypeEncoding(method),"@16@0:8")) {
            id identifier=((id (*)(id,SEL))objc_msgSend)(alertId,selector);
            if ([identifier isKindOfClass:NSString.class]) {
                NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
                dispatch_async(dispatch_get_main_queue(), ^{
                    ObserveAlert(iconName,statsType,statsSubtype,statsSubtypeTrait,distanceMeters,isValid,didPassAlert,now);
                    [store updateIdentifier:identifier icon:iconName type:statsType subtype:statsSubtype
                        trait:statsSubtypeTrait distance:distanceMeters
                        valid:isValid passed:didPassAlert atUptime:now];
                    Publish(NO);
                });
            }
        }
    } @catch (__unused NSException *exception) {}
    return result;
}

__attribute__((constructor)) static void Start(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.waze.iphone"]) return;
    // Waze's private model is version-specific; skip unknown builds safely.
    if (![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"5.25.0"]) {
        Status(@"Unsupported Waze version"); return;
    }
    Class cls=NSClassFromString(@"third_party_waze_client_ios_modules_WazeCommonCodeAlerts_WazeCommonCodeAlerts.CommonCodeAlertDescriptorData");
    SEL selector=sel_registerName("initWithAlertId:priority:isPreemptive:isValid:distanceMeters:title:carplayTitle:alertDescription:carplayAlertDescription:iconName:isCancellable:canSendThumbsUp:isCloseOnly:primaryButtonText:secondaryButtonText:disableCompactEtaBarTaps:showDistance:keepOpenAfterAction:closeOnlyOnSelection:timeoutSeconds:timerType:zoneAlertData:shouldShowStillThere:didPassAlert:triggerDistanceMeters:primaryButtonIsClose:secondaryButtonIsClose:shouldShowFocusedAlert:silentActivationReason:coordinate:shouldCheckDistanceFromLastAlert:statsAlertId:statsType:statsSubtype:statsSubtypeTrait:statsUniqueId:dismissImmediatelyUponRemoval:isApproachingWithValidationHasValue:isApproachingWithValidation:hideActionsWhenInvalid:showOnCarPlayDashboard:doNotHideOnMapMovement:");
    Method method=class_getInstanceMethod(cls,selector);
    const char *encoding="@268@0:8@16q24B32B36q40@48@56@64@72@80B88B92B96@100@108B116B120B124B128d132q140@148B156B160q164B172B176B180q184@192B200q204q212q220q228@236B244B248B252B256B260B264";
    store=[GVMWazeOutputStore new];
    if (method && !strcmp(method_getTypeEncoding(method),encoding)) {
        MSHookMessageEx(cls,selector,(IMP)Descriptor,(IMP *)&OriginalDescriptor);
        Status(@"Waze output v1 alert hook active 5.25.0");
    } else Status(@"Waze alert ABI mismatch; scalar fields checked independently");
    notify_register_dispatch(GVMOutputRequestName(GVMSourceWaze).UTF8String,&requestToken,
        dispatch_get_main_queue(),^(__unused int token) { Publish(YES); });
    ConfigureNativeLimit();
    Class gpsClass=NSClassFromString(@"WSVLocationGPSPosition");
    SEL gpsSelector=sel_registerName("initWithLongitude:latitude:altitudeMeters:speedMMSec:steering:accuracyMeters:timeSec:hasSteering:speedAccuracyMMsec:steeringAccuracy:");
    Method gpsMethod=class_getInstanceMethod(gpsClass,gpsSelector);
    if (gpsMethod && !strcmp(method_getTypeEncoding(gpsMethod),"@92@0:8d16d24d32d40d48d56d64B72d76d84"))
        MSHookMessageEx(gpsClass,gpsSelector,(IMP)GPS,(IMP *)&OriginalGPS);
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) {
            // iOS may deliver no GPS while stationary; Waze still holds its current limit, so
            // re-read that live native state each second as VietMap's engine re-sends it.
            if (nativeLimitReady) [store updateLimit:ReadNativeLimit() uptime:NSProcessInfo.processInfo.systemUptime];
            Publish(NO);
        }];
    });
}
