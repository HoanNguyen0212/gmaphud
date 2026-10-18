#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <substrate.h>
#import <notify.h>
#import "nav-source.h"
#import "diagnostics.h"
#import "background-location.h"
#ifdef VM_GOOGLE_MAPS_RELAY
#import "speed-state.h"
#import "source-transport.h"
#import "vietmap-output.h"
#import "vietmap-alert-assets.h"
#import "cmu-hud-relay.h"
#import "tpms-state.h"
#import "carplay-nav-hook.h"
static int requestToken=-1, tpmsToken=-1;
static NSTimeInterval lastRequestHandled=-1;
static BOOL forceOutput;
static NSArray<NSDictionary *> *upcomingAlerts, *stickyAlerts;
static NSTimeInterval upcomingReceived, stickyReceived;
// The lanes VietMap Live shows (its overlay's laneInfo): in effect on the stretch being driven, kept
// until VietMap changes or clears them. updateLaneInfo, its advance countdown, is only observed.
static NSArray<NSNumber *> *laneCodes;
static NSTimeInterval laneCodesReceived=-1;
static GVMTPMSData g_liveTPMS;
static void GVMScanUserDefaultsForTPMS(void);
static uint16_t g_vmNavIcon = 0;
static NSUInteger g_vmNavDistance = 0;
static NSString *g_vmNavRoad = nil;
static NSTimeInterval g_vmNavLastReceived = 0;
static void GVMHandleVietMapManeuver(id args, NSTimeInterval received);
static void GVMHandleVietMapProgress(id args, NSTimeInterval received);
static void GVMHandleVietMapNavEnd(void);
static void GVMDispatchVietMapNavMethod(NSString *mLower, id args, NSTimeInterval ts);
#endif

@protocol VMFlutterMethodCall
- (NSString *)method;
- (id)arguments;
@end

typedef void (^VMFlutterResult)(id result);
typedef void (^VMFlutterHandler)(id<VMFlutterMethodCall> call, VMFlutterResult result);
static VMNavSource *source;
static dispatch_source_t heartbeat;
static BOOL hookInstalled;
static Ivar channelNameIvar;
static void (*originalSetHandler)(id, SEL, VMFlutterHandler);

// Diagnostics stay inside the app sandbox and contain no location or route data.
static void BridgeLog(NSString *message) {
#ifdef VM_GOOGLE_MAPS_RELAY
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"googlemaps-vietmap-source.log"];
#else
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"truedash-vietmap.log"];
#endif
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([[fm attributesOfItemAtPath:path error:nil] fileSize] > 65536) [fm removeItemAtPath:path error:nil];
    if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
    @try {
        [file seekToEndOfFile];
        [file writeData:[[NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, message]
            dataUsingEncoding:NSUTF8StringEncoding]];
        [file closeFile];
    } @catch (__unused NSException *exception) {}
}

static void Publish(void) {
#ifdef VM_GOOGLE_MAPS_RELAY
    if (!g_liveTPMS.hasData) GVMScanUserDefaultsForTPMS();
    GVMRefreshLocationSession();
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    NSMutableDictionary *samples=[[source freshSamplesAtUptime:now] mutableCopy] ?: [NSMutableDictionary new];
    GVMDiagnosticsRecord(GVMDiagnosticSamples,(samples[@"speed"] ? 1 : 0) | (samples[@"speedLimit"] ? 2 : 0) | (UIApplication.sharedApplication.applicationState==UIApplicationStateActive ? 4 : 0));
    NSNumber *hudLimit = samples[@"speedLimit"][@"value"];
    if (hudLimit && [hudLimit isKindOfClass:NSNumber.class]) {
        GVMCMURelaySetLimit([hudLimit unsignedIntegerValue]);
    } else {
        GVMCMURelaySetLimit(0);
    }
    if (GVMSelectedSourceID()!=GVMSourceVietMap) return;
    NSDictionary *lanes=GVMVietMapLaneSample(laneCodes,now);
    if (lanes) samples[@"lanes"]=lanes;
    NSMutableArray *entries=[NSMutableArray new];
    for (NSDictionary *alert in upcomingAlerts)
        [entries addObject:@{@"sample":alert,@"receivedAt":@(upcomingReceived)}];
    for (NSDictionary *alert in stickyAlerts)
        [entries addObject:@{@"sample":alert,@"receivedAt":@(stickyReceived),@"active":@YES}];
    NSDictionary *output=GVMVietMapOutput(samples,entries,now);
    if (GVMPublishSourceOutput(output,now,forceOutput)) forceOutput=NO;
    else { BridgeLog(@"common source output publication refused"); GVMDiagnosticsRecord(GVMDiagnosticError,1); }

#else
    NSDictionary *payload = [source payloadAtUptime:NSProcessInfo.processInfo.systemUptime
        timestamp:NSDate.date.timeIntervalSince1970];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"truedash_navprovider.plist"];
    if ([payload writeToFile:path atomically:YES]) notify_post("com.sensetechlab.navprovider.update");
    else BridgeLog(@"publish failed");
#endif
}

#ifdef VM_GOOGLE_MAPS_RELAY
// While observing, keep a copy of each image VietMap registers for its CarPlay views (its own
// lane and maneuver icons), named by key, so the keys used in laneInfo can be matched to icons.
static NSUInteger SaveNavigationImages(id payload,NSString *path,NSUInteger saved) {
    if (saved>=32) return saved;
    NSData *data=GVMVietMapDataValue(payload);
    if (data) {
        if (data.length>131072) return saved;
        NSCharacterSet *unsafe=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"] invertedSet];
        NSString *name=[[path componentsSeparatedByCharactersInSet:unsafe] componentsJoinedByString:@"_"];
        name=[name substringToIndex:MIN(name.length,48)];
        [data writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"gmaphud-navimage-%@.png",name.length ? name : @"value"]] atomically:YES];
        return saved+1;
    }
    if ([payload isKindOfClass:NSDictionary.class])
        for (id key in [[(NSDictionary *)payload allKeys] sortedArrayUsingSelector:@selector(compare:)])
            if ([key isKindOfClass:NSString.class]) saved=SaveNavigationImages(payload[key],[path stringByAppendingFormat:@"%@%@",path.length ? @"." : @"",key],saved);
    if ([payload isKindOfClass:NSArray.class])
        for (NSUInteger i=0;i<MIN([payload count],32);i++) saved=SaveNavigationImages(payload[i],[path stringByAppendingFormat:@"%@%lu",path.length ? @"." : @"",(unsigned long)i],saved);
    return saved;
}
static void ObserveAlerts(NSString *method,id payload,NSUInteger accepted,NSTimeInterval received) {
    NSString *gate=[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-alert-observation.enable"];
    NSDate *modified=[[NSFileManager.defaultManager attributesOfItemAtPath:gate error:nil] fileModificationDate];
    NSTimeInterval age=modified ? -modified.timeIntervalSinceNow : -1;
    if (age<0 || age>180) return;
    static NSMutableDictionary *last;
    @synchronized(source) {
        if (!last) last=[NSMutableDictionary new];
        // Image registrations come in bursts and each one matters; repeated status updates are sampled.
        BOOL burst=[method isEqualToString:@"setNavigationImage"] || [method isEqualToString:@"cacheImage"] ||
            ([method isEqualToString:@"updateMapOverlayData"] && GVMVietMapOverlayCarriesImages(payload));
        if (!burst && last[method] && received-[last[method] doubleValue]<2) return;
        last[method]=@(received);
    }
    // Capture one explicitly selected warning image locally, never its payload or coordinates.
    if ([method isEqualToString:@"updateStickyAlerts"] && [payload isKindOfClass:NSArray.class]) {
        NSString *imageGate=[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-alert-image.enable"];
        NSDate *imageModified=[[NSFileManager.defaultManager attributesOfItemAtPath:imageGate error:nil] fileModificationDate];
        if (imageModified && -imageModified.timeIntervalSinceNow>=0 && -imageModified.timeIntervalSinceNow<=180) {
            for (__strong id item in [payload subarrayWithRange:NSMakeRange(0,MIN([payload count],8))]) {
                if ([item isKindOfClass:NSString.class] && [item length]<=262144)
                    item=[NSJSONSerialization JSONObjectWithData:[item dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                id encoded=[item isKindOfClass:NSDictionary.class] ? item[@"image"] : nil;
                if (![encoded isKindOfClass:NSString.class] || [encoded length]>180000) continue;
                NSData *bytes=[[NSData alloc] initWithBase64EncodedString:encoded options:0];
                NSDictionary *observed=GVMVietMapAlertObservation(@[item],0);
                NSString *hash=[observed[@"items"] firstObject][@"imageSHA256"];
                if (![hash isEqualToString:@"ee9fc9ee37a92ddfa0d9090d7add3172efdced4efa3ac1cc0bf90c310faf1881"] ||
                    !bytes.length || bytes.length>131072) continue;
                NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-alert-image.png"];
                if ([bytes writeToFile:path options:NSDataWritingAtomic error:nil])
                    [NSFileManager.defaultManager removeItemAtPath:imageGate error:nil];
                break;
            }
        }
    }
    BOOL value=[@[@"updateLaneInfo",@"setNavigationImage",@"cacheImage"] containsObject:method];
    NSDictionary *summary=[method isEqualToString:@"updateMapOverlayData"] ? GVMVietMapOverlayObservation(payload) :
        value ? GVMVietMapValueObservation(payload) : GVMVietMapAlertObservation(payload,accepted);
    if ([method isEqualToString:@"setNavigationImage"]) SaveNavigationImages(payload,@"",0);
    if ([method isEqualToString:@"updateMapOverlayData"] && GVMVietMapOverlayCarriesImages(payload)) {
        NSUInteger saved=0;
        NSDictionary *patch=GVMVietMapOverlayPatch(payload);
        for (NSString *key in patch) if (GVMVietMapDataValue(patch[key])) saved=SaveNavigationImages(patch[key],key,saved);
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:summary options:0 error:nil];
    NSString *json=data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (json) dispatch_async(dispatch_get_main_queue(), ^{
        BridgeLog([NSString stringWithFormat:@"alert-observation method=%@ %@",method,json]);
    });
}

static NSString *GetChannelName(id channel, Ivar ivar) {
    if (!channel) return nil;
    if ([channel respondsToSelector:@selector(name)]) {
        @try {
            id n = [channel performSelector:@selector(name)];
            if ([n isKindOfClass:NSString.class]) return (NSString *)n;
        } @catch (__unused NSException *e) {}
    }
    if (ivar) {
        @try {
            id n = object_getIvar(channel, ivar);
            if ([n isKindOfClass:NSString.class]) return (NSString *)n;
        } @catch (__unused NSException *e) {}
    }
    return nil;
}

static void GVMParseTireDict(NSDictionary *d, NSString *explicitPos) {
    if (!d || ![d isKindOfClass:NSDictionary.class]) return;

    // Check nested collections
    for (NSString *key in @[@"tires", @"wheels", @"sensorList", @"sensors", @"data", @"list", @"tiresList"]) {
        id nested = d[key];
        if ([nested isKindOfClass:NSArray.class]) {
            for (id item in (NSArray *)nested) {
                if ([item isKindOfClass:NSDictionary.class]) GVMParseTireDict(item, nil);
            }
        } else if ([nested isKindOfClass:NSDictionary.class] && nested != d) {
            GVMParseTireDict((NSDictionary *)nested, nil);
        }
    }

    // Direct positions inside d
    if (d[@"fl"] && [d[@"fl"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"fl"], @"fl");
    if (d[@"fr"] && [d[@"fr"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"fr"], @"fr");
    if (d[@"rl"] && [d[@"rl"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"rl"], @"rl");
    if (d[@"rr"] && [d[@"rr"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"rr"], @"rr");

    if (d[@"FL"] && [d[@"FL"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"FL"], @"fl");
    if (d[@"FR"] && [d[@"FR"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"FR"], @"fr");
    if (d[@"RL"] && [d[@"RL"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"RL"], @"rl");
    if (d[@"RR"] && [d[@"RR"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"RR"], @"rr");

    if (d[@"frontLeft"] && [d[@"frontLeft"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"frontLeft"], @"fl");
    if (d[@"frontRight"] && [d[@"frontRight"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"frontRight"], @"fr");
    if (d[@"rearLeft"] && [d[@"rearLeft"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"rearLeft"], @"rl");
    if (d[@"rearRight"] && [d[@"rearRight"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"rearRight"], @"rr");

    if (d[@"0"] && [d[@"0"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"0"], @"fl");
    if (d[@"1"] && [d[@"1"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"1"], @"fr");
    if (d[@"2"] && [d[@"2"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"2"], @"rl");
    if (d[@"3"] && [d[@"3"] isKindOfClass:NSDictionary.class]) GVMParseTireDict(d[@"3"], @"rr");

    // Priority 1: Check internal keys in dictionary first
    id posInDict = d[@"position"] ?: d[@"tirePosition"] ?: d[@"pos"] ?: 
                   d[@"wheel"] ?: d[@"wheelPosition"] ?: d[@"code"] ?: 
                   d[@"location"] ?: d[@"index"] ?: d[@"tire_index"] ?: 
                   d[@"tireId"] ?: d[@"tire"];
    
    // Priority 2: Fallback to explicitPos only if no position inside d
    id codeVal = posInDict ?: explicitPos;
    
    // Extract pressure value and explicit unit tag if available
    id pressVal = nil;
    NSString *detectedUnit = nil;
    if (d[@"bar"] != nil && d[@"bar"] != [NSNull null]) {
        pressVal = d[@"bar"];
        detectedUnit = @"bar";
    } else if (d[@"kpa"] != nil && d[@"kpa"] != [NSNull null]) {
        pressVal = d[@"kpa"];
        detectedUnit = @"kpa";
    } else if (d[@"psi"] != nil && d[@"psi"] != [NSNull null]) {
        pressVal = d[@"psi"];
        detectedUnit = @"psi";
    } else {
        pressVal = d[@"pressure"] ?: d[@"press"] ?: d[@"p"] ?: d[@"val"] ?: d[@"value"] ?: 
                   d[@"tirePressure"] ?: d[@"currentPressure"];
    }

    if (!detectedUnit && d[@"unit"]) detectedUnit = [d[@"unit"] description].lowercaseString;
    if (!detectedUnit && d[@"pressureUnit"]) detectedUnit = [d[@"pressureUnit"] description].lowercaseString;
                  
    id tempVal = d[@"temperature"] ?: d[@"temp"] ?: d[@"t"] ?: d[@"celsius"] ?: d[@"tireTemperature"];
    id warnVal = d[@"isPressureWarning"] ?: d[@"warning"] ?: d[@"warn"] ?: d[@"isWarning"];
    id xieYaVal = d[@"isXieYa"] ?: d[@"leak"] ?: d[@"isLeak"];

    if (!codeVal && !pressVal) return;

    GVMTPMSTire *target = NULL;
    NSString *codeStr = [[codeVal description] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if ([codeStr isEqualToString:@"0"] || [codeStr isEqualToString:@"fl"] || [codeStr isEqualToString:@"lf"] ||
        [codeStr isEqualToString:@"tt"] || [codeStr isEqualToString:@"fl_wheel"] ||
        [codeStr containsString:@"front_left"] || [codeStr containsString:@"frontleft"] ||
        [codeStr containsString:@"left_front"] || [codeStr containsString:@"truoc_trai"]) {
        target = &g_liveTPMS.fl;
    } else if ([codeStr isEqualToString:@"1"] || [codeStr isEqualToString:@"fr"] || [codeStr isEqualToString:@"rf"] ||
               [codeStr isEqualToString:@"tp"] || [codeStr isEqualToString:@"fr_wheel"] ||
               [codeStr containsString:@"front_right"] || [codeStr containsString:@"frontright"] ||
               [codeStr containsString:@"right_front"] || [codeStr containsString:@"truoc_phai"]) {
        target = &g_liveTPMS.fr;
    } else if ([codeStr isEqualToString:@"2"] || [codeStr isEqualToString:@"rl"] || [codeStr isEqualToString:@"lr"] ||
               [codeStr isEqualToString:@"st"] || [codeStr isEqualToString:@"rl_wheel"] ||
               [codeStr containsString:@"rear_left"] || [codeStr containsString:@"rearleft"] ||
               [codeStr containsString:@"left_rear"] || [codeStr containsString:@"back_left"] ||
               [codeStr containsString:@"sau_trai"]) {
        target = &g_liveTPMS.rl;
    } else if ([codeStr isEqualToString:@"3"] || [codeStr isEqualToString:@"rr"] ||
               [codeStr isEqualToString:@"sp"] || [codeStr isEqualToString:@"rr_wheel"] ||
               [codeStr containsString:@"rear_right"] || [codeStr containsString:@"rearright"] ||
               [codeStr containsString:@"right_rear"] || [codeStr containsString:@"back_right"] ||
               [codeStr containsString:@"sau_phai"]) {
        target = &g_liveTPMS.rr;
    } else if ([codeStr isEqualToString:@"4"]) {
        target = &g_liveTPMS.rr; // 1-based index support (1=FL, 2=FR, 3=RL, 4=RR)
    }

    if (!target) return;

    if (pressVal != nil && pressVal != [NSNull null]) {
        float p = 0.0f;
        if ([pressVal isKindOfClass:NSNumber.class]) {
            p = [pressVal floatValue];
        } else if ([pressVal isKindOfClass:NSString.class]) {
            NSString *pStr = [(NSString *)pressVal lowercaseString];
            pStr = [pStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            // Discard hex sensor IDs (e.g. 0361DF, A1B2C3, 5+ hex characters)
            if (pStr.length >= 5) {
                NSCharacterSet *hexChars = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
                if ([[pStr stringByTrimmingCharactersInSet:hexChars] length] == 0) {
                    return; // Pure hex sensor ID, not a pressure value
                }
            }
            NSCharacterSet *nonNum = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789.,kKapPbsSiI- "] invertedSet];
            if ([pStr rangeOfCharacterFromSet:nonNum].location != NSNotFound) {
                return; // Contains non-numeric characters (hex sensor ID e.g. "0361D") -> Ignore
            }
            pStr = [pStr stringByReplacingOccurrencesOfString:@"," withString:@"."];
            if (!detectedUnit) {
                if ([pStr containsString:@"kpa"]) detectedUnit = @"kpa";
                else if ([pStr containsString:@"psi"]) detectedUnit = @"psi";
                else if ([pStr containsString:@"bar"]) detectedUnit = @"bar";
            }
            NSScanner *scanner = [NSScanner scannerWithString:pStr];
            scanner.charactersToBeSkipped = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789.-"] invertedSet];
            double dVal = 0.0;
            if ([scanner scanDouble:&dVal] && isfinite(dVal)) {
                p = (float)dVal;
            } else {
                return;
            }
        }
        
        // Intelligent pressure unit conversion:
        if ([detectedUnit containsString:@"kpa"]) {
            p = p / 100.0f; // e.g. 230 kPa -> 2.3 bar
        } else if ([detectedUnit containsString:@"psi"]) {
            if (p > 100.0f) p = p / 10.0f; // e.g. 335 -> 33.5 psi
            p = p / 14.50377f; // e.g. 33 psi -> 2.27 bar
        } else if ([detectedUnit containsString:@"bar"]) {
            if (p >= 100.0f) p = p / 100.0f; // centibar: 230 -> 2.3 bar
            else if (p >= 10.0f) p = p / 10.0f; // decibar: 23 -> 2.3 bar
        } else {
            // Auto-detect unit when no explicit tag
            if (p >= 80.0f && p <= 600.0f) {
                p = p / 100.0f; // kPa: 230 -> 2.3 bar
            } else if (p > 600.0f) {
                p = p / 1000.0f;
            } else if (p >= 15.0f && p < 80.0f) {
                BOOL isExactInteger = (fabsf(p - roundf(p)) < 0.001f);
                BOOL hasBleRawKeys = (d[@"isXieYa"] != nil || d[@"leak"] != nil || d[@"deviceID"] != nil || d[@"sensorID"] != nil || d[@"bt10"] != nil || d[@"tw50"] != nil);
                if (isExactInteger && (hasBleRawKeys || (p >= 18.0f && p <= 32.0f))) {
                    p = p / 10.0f; // Decibar: 23 -> 2.3 bar
                } else {
                    p = p / 14.50377f; // PSI: 32.5 -> 2.24 bar
                }
            } else if (p >= 8.0f && p < 15.0f) {
                p = p / 10.0f; // Low pressure decibar: 12 -> 1.2 bar
            }
            // If 0.0 <= p < 8.0: already in Bar (e.g. 2.2, 2.3)
        }
        if (p < 0.0f) p = 0.0f;
        target->pressure = p;
        target->active = (p > 0.05f);
    }
    if ([tempVal respondsToSelector:@selector(intValue)]) {
        target->temperature = [tempVal intValue];
    }
    BOOL isWarn = [warnVal respondsToSelector:@selector(boolValue)] && [warnVal boolValue];
    BOOL isLeak = [xieYaVal respondsToSelector:@selector(boolValue)] && [xieYaVal boolValue];
    if (isLeak || (target->active && target->pressure <= 0.05f)) target->warning = 2;
    else if (isWarn) target->warning = (target->pressure < 1.8f) ? 1 : 2;
    else if (target->pressure < 1.8f && target->active) target->warning = 1;
    else if (target->pressure > 2.8f) target->warning = 2;
    else target->warning = 0;
}

static void GVMProcessTirePayload(id payload, NSTimeInterval received) {
    if (!payload) return;
    static id s_tpmsLock = nil;
    static dispatch_once_t lockOnce;
    dispatch_once(&lockOnce, ^{ s_tpmsLock = [NSObject new]; });

    @synchronized(s_tpmsLock) {
        static NSTimeInterval lastRawLog = 0;
        if (received - lastRawLog >= 5.0) {
            lastRawLog = received;
            BridgeLog([NSString stringWithFormat:@"[TPMS] Raw payload: %@", payload]);
        }
        if ([payload isKindOfClass:NSString.class]) {
            NSData *data = [(NSString *)payload dataUsingEncoding:NSUTF8StringEncoding];
            if (data) {
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (json) payload = json;
            }
        }
        
        if ([payload isKindOfClass:NSArray.class]) {
            NSArray *arr = (NSArray *)payload;
            for (NSUInteger i = 0; i < [arr count]; i++) {
                id item = arr[i];
                NSString *pos = (i == 0) ? @"fl" : (i == 1) ? @"fr" : (i == 2) ? @"rl" : (i == 3) ? @"rr" : nil;
                if ([item isKindOfClass:NSDictionary.class]) {
                    GVMParseTireDict((NSDictionary *)item, pos);
                } else if ([item isKindOfClass:NSNumber.class]) {
                    if (pos) {
                        GVMParseTireDict(@{ @"pressure": item, @"position": pos }, pos);
                    }
                }
            }
        } else if ([payload isKindOfClass:NSDictionary.class]) {
            NSDictionary *d = (NSDictionary *)payload;
            for (NSString *k in @[@"fl", @"fr", @"rl", @"rr", @"FL", @"FR", @"RL", @"RR", @"frontLeft", @"frontRight", @"rearLeft", @"rearRight"]) {
                id v = d[k];
                if (v && ([v isKindOfClass:NSNumber.class] || [v isKindOfClass:NSString.class])) {
                    NSString *pos = [k lowercaseString];
                    if ([pos containsString:@"frontleft"]) pos = @"fl";
                    else if ([pos containsString:@"frontright"]) pos = @"fr";
                    else if ([pos containsString:@"rearleft"]) pos = @"rl";
                    else if ([pos containsString:@"rearright"]) pos = @"rr";
                    GVMParseTireDict(@{ @"pressure": v, @"position": pos }, pos);
                }
            }
            GVMParseTireDict(d, nil);
        }
        
        g_liveTPMS.hasData = (g_liveTPMS.fl.active || g_liveTPMS.fr.active || g_liveTPMS.rl.active || g_liveTPMS.rr.active);
        if (g_liveTPMS.hasData) {
            g_liveTPMS.receivedAt = received;
            static NSTimeInterval lastNotifyPost = 0;
            if (received - lastNotifyPost >= 0.08) {
                lastNotifyPost = received;
                uint64_t encoded = GVMEncodeTPMS(&g_liveTPMS, received);
                if (tpmsToken < 0) {
                    notify_register_check(GVMTPMSStateName, &tpmsToken);
                }
                if (tpmsToken >= 0 && notify_set_state(tpmsToken, encoded) == NOTIFY_STATUS_OK) {
                    notify_post(GVMTPMSStateName);
                }
            }
            static NSTimeInterval lastBridgeLog = 0;
            if (received - lastBridgeLog >= 2.0) {
                lastBridgeLog = received;
                BridgeLog([NSString stringWithFormat:@"[TPMS] LIVE UPDATE FL=%.1f FR=%.1f RL=%.1f RR=%.1f",
                    g_liveTPMS.fl.pressure, g_liveTPMS.fr.pressure, g_liveTPMS.rl.pressure, g_liveTPMS.rr.pressure]);
            }
        }
    }
}

static void (*originalEventSetHandler)(id, SEL, id);
static Ivar eventChannelNameIvar = NULL;

static void SetEventStreamHandler(id channel, SEL selector, id handler) {
    NSString *name = GetChannelName(channel, eventChannelNameIvar);
    if (!handler) {
        originalEventSetHandler(channel, selector, handler);
        return;
    }
    
    BOOL isTargetChannel = NO;
    if (name) {
        NSString *lower = [name lowercaseString];
        isTargetChannel = [lower containsString:@"tpms"] || [lower containsString:@"tire"] ||
                          [lower containsString:@"ble"] || [lower containsString:@"bluetooth"] ||
                          [lower containsString:@"device"] || [lower containsString:@"hardware"] ||
                          [lower containsString:@"sensor"] || [lower containsString:@"bt10"] ||
                          [lower containsString:@"tw50"] || [lower containsString:@"vml"] ||
                          [lower containsString:@"vietmap"];
    } else {
        isTargetChannel = YES;
    }
    
    if (!isTargetChannel) {
        originalEventSetHandler(channel, selector, handler);
        return;
    }
    
    BridgeLog([NSString stringWithFormat:@"Hooking TPMS EventChannel: %@", name ?: @"unknown"]);
    Class handlerClass = [handler class];
    SEL onListenSel = NSSelectorFromString(@"onListenWithArguments:eventSink:");
    Method m = class_getInstanceMethod(handlerClass, onListenSel);
    static const void *kGVMStreamHookedKey = &kGVMStreamHookedKey;
    if (m && !objc_getAssociatedObject(handlerClass, kGVMStreamHookedKey)) {
        objc_setAssociatedObject(handlerClass, kGVMStreamHookedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __block id (*origOnListen)(id, SEL, id, id) = (id (*)(id, SEL, id, id))method_getImplementation(m);
        NSString *chanName = [name copy];
        id newImp = ^(id selfHandler, id args, id eventSink) {
            BridgeLog([NSString stringWithFormat:@"TPMS event sink registered on %@", chanName ?: @"channel"]);
            id wrappedSink = ^(id event) {
                @try {
                    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
                    GVMProcessTirePayload(event, now);
                } @catch (NSException *ex) {
                    BridgeLog([NSString stringWithFormat:@"TPMS stream exception: %@", ex]);
                }
                if (eventSink) ((void (^)(id))eventSink)(event);
            };
            return origOnListen(selfHandler, onListenSel, args, wrappedSink);
        };
        class_replaceMethod(handlerClass, onListenSel, imp_implementationWithBlock(newImp), method_getTypeEncoding(m));
    }
    originalEventSetHandler(channel, selector, handler);
}

static void GVMDispatchVietMapNavMethod(NSString *mLower, id args, NSTimeInterval ts) {
    BOOL isManeuverCall = [mLower isEqualToString:@"updatemaneuver"] ||
                          [mLower isEqualToString:@"updatenavigationinfo"] ||
                          [mLower isEqualToString:@"onnavigationupdate"] ||
                          [mLower isEqualToString:@"updateturninfo"] ||
                          [mLower containsString:@"maneuver"] ||
                          [mLower isEqualToString:@"updatenavinfo"];
    BOOL isProgressCall = [mLower isEqualToString:@"updateultraprogress"] ||
                          [mLower isEqualToString:@"updateprogress"] ||
                          [mLower isEqualToString:@"onprogressupdate"];
    BOOL isEndNavCall   = [mLower isEqualToString:@"clearmaneuver"] ||
                          [mLower isEqualToString:@"stopnavigation"] ||
                          [mLower isEqualToString:@"finishnavigation"] ||
                          [mLower isEqualToString:@"cancelnavigation"] ||
                          [mLower isEqualToString:@"clearnavigation"];
    if (isManeuverCall) {
        GVMHandleVietMapManeuver(args, ts);
    } else if (isProgressCall) {
        GVMHandleVietMapProgress(args, ts);
    } else if (isEndNavCall) {
        GVMHandleVietMapNavEnd();
    }
}

static void (*originalInvokeMethod)(id, SEL, NSString *, id) = NULL;
static void HookedInvokeMethod(id selfChannel, SEL _cmd, NSString *method, id arguments) {
    if (originalInvokeMethod) originalInvokeMethod(selfChannel, _cmd, method, arguments);
    @try {
        NSString *mLower = [method lowercaseString];
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if ([mLower containsString:@"tpms"] || [mLower containsString:@"tire"] ||
            [mLower containsString:@"pressure"] || [mLower containsString:@"ble"] ||
            [mLower containsString:@"bluetooth"] || [mLower containsString:@"sensor"] ||
            [mLower containsString:@"device"] || [mLower containsString:@"hardware"] ||
            [mLower containsString:@"bt10"] || [mLower containsString:@"tw50"]) {
            GVMProcessTirePayload(arguments, now);
            BridgeLog([NSString stringWithFormat:@"[TPMS] invokeMethod: %@ args=%@", method, arguments]);
        }
        GVMDispatchVietMapNavMethod(mLower, arguments, now);
    } @catch (__unused NSException *e) {}
}

static void (*originalInvokeMethodWithResult)(id, SEL, NSString *, id, id) = NULL;
static void HookedInvokeMethodWithResult(id selfChannel, SEL _cmd, NSString *method, id arguments, id callback) {
    if (originalInvokeMethodWithResult) originalInvokeMethodWithResult(selfChannel, _cmd, method, arguments, callback);
    @try {
        NSString *mLower = [method lowercaseString];
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if ([mLower containsString:@"tpms"] || [mLower containsString:@"tire"] ||
            [mLower containsString:@"pressure"] || [mLower containsString:@"ble"] ||
            [mLower containsString:@"bluetooth"] || [mLower containsString:@"sensor"] ||
            [mLower containsString:@"device"] || [mLower containsString:@"hardware"] ||
            [mLower containsString:@"bt10"] || [mLower containsString:@"tw50"]) {
            GVMProcessTirePayload(arguments, now);
            BridgeLog([NSString stringWithFormat:@"[TPMS] invokeMethodWithResult: %@ args=%@", method, arguments]);
        }
        GVMDispatchVietMapNavMethod(mLower, arguments, now);
    } @catch (__unused NSException *e) {}
}

static void GVMScanUserDefaultsForTPMS(void) {
    if (g_liveTPMS.hasData) return;
    @try {
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        id cacheVal = [defs objectForKey:@"flutter._storedTPMSDeviceCache"] ?: [defs objectForKey:@"_storedTPMSDeviceCache"];
        if (cacheVal) {
            NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
            GVMProcessTirePayload(cacheVal, now);
        }
    } @catch (__unused NSException *e) {}
}

static uint16_t GVMParseVietMapIcon(id iconVal) {
    if (!iconVal || iconVal == [NSNull null]) return 0;
    if ([iconVal isKindOfClass:[NSNumber class]]) {
        int v = [iconVal intValue];
        switch (v) {
            case 1:  return 1;  // HUD_STRAIGHT
            case 2:  return 2;  // HUD_LEFT
            case 3:  return 3;  // HUD_RIGHT
            case 4:  return 4;  // HUD_SLIGHT_LEFT
            case 5:  return 5;  // HUD_SLIGHT_RIGHT
            case 6:  return 11; // HUD_SHARP_LEFT
            case 7:  return 9;  // HUD_SHARP_RIGHT
            case 8:  return 13; // HUD_U_TURN_LEFT
            case 9:  return 16; // HUD_MERGE_LEFT
            case 10: return 10; // HUD_U_TURN_RIGHT
            case 11: return 8;  // HUD_DESTINATION
            case 12:
            case 37:
            case 38: return 37; // HUD_ROUNDABOUT
            default:
                if (v >= 1 && v <= 60) return (uint16_t)v;
                return 1;
        }
    } else if ([iconVal isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)iconVal lowercaseString];
        if ([s containsString:@"straight"] || [s containsString:@"thang"]) return 1;
        if ([s containsString:@"slight-left"] || [s containsString:@"slight_left"] || [s containsString:@"chech trai"] || [s containsString:@"nhe trai"]) return 4;
        if ([s containsString:@"slight-right"] || [s containsString:@"slight_right"] || [s containsString:@"chech phai"] || [s containsString:@"nhe phai"]) return 5;
        if ([s containsString:@"sharp-left"] || [s containsString:@"sharp_left"] || [s containsString:@"gat trai"]) return 11;
        if ([s containsString:@"sharp-right"] || [s containsString:@"sharp_right"] || [s containsString:@"gat phai"]) return 9;
        if ([s containsString:@"u-turn"] || [s containsString:@"uturn"] || [s containsString:@"quay dau"]) return 13;
        if ([s containsString:@"turn-left"] || [s containsString:@"left"] || [s containsString:@"re trai"] || [s containsString:@"queo trai"]) return 2;
        if ([s containsString:@"turn-right"] || [s containsString:@"right"] || [s containsString:@"re phai"] || [s containsString:@"queo phai"]) return 3;
        if ([s containsString:@"roundabout"] || [s containsString:@"rotary"] || [s containsString:@"vong xuyen"] || [s containsString:@"bung binh"]) return 37;
        if ([s containsString:@"fork-left"] || [s containsString:@"ramp-left"]) return 6;
        if ([s containsString:@"fork-right"] || [s containsString:@"ramp-right"]) return 7;
        if ([s containsString:@"merge-left"]) return 16;
        if ([s containsString:@"merge-right"]) return 15;
        if ([s containsString:@"arrive"] || [s containsString:@"destination"] || [s containsString:@"dich den"] || [s containsString:@"den noi"]) return 8;
        int v = [s intValue];
        if (v > 0) return GVMParseVietMapIcon(@(v));
    }
    return 0;
}

static void GVMHandleVietMapNavEnd(void) {
    if (g_vmNavIcon > 0 || g_vmNavDistance > 0) {
        g_vmNavIcon = 0;
        g_vmNavDistance = 0;
        g_vmNavRoad = @"";
        g_vmNavLastReceived = 0;
        GVMCMURelaySetNav(0, 0, @"");
        BridgeLog(@"[VM_NAV] Cleared navigation on HUD");
    }
}

static void GVMHandleVietMapManeuver(id args, NSTimeInterval received) {
    if (!args || args == [NSNull null]) {
        GVMHandleVietMapNavEnd();
        return;
    }

    id payload = args;
    if ([payload isKindOfClass:[NSString class]]) {
        NSData *data = [(NSString *)payload dataUsingEncoding:NSUTF8StringEncoding];
        if (data) {
            id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (parsed) payload = parsed;
        }
    }
    if ([payload isKindOfClass:[NSArray class]] && [(NSArray *)payload count] > 0) {
        payload = [(NSArray *)payload firstObject];
    }

    uint16_t icon = 0;
    double dist = 0.0;
    NSString *road = nil;
    NSString *instruction = nil;

    if ([payload isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)payload;
        id iconObj = dict[@"icon"] ?: dict[@"iconId"] ?: dict[@"icon_id"] ?: dict[@"action"] ?: dict[@"maneuver"] ?: dict[@"type"] ?: dict[@"modifier"] ?: dict[@"turn"];
        icon = GVMParseVietMapIcon(iconObj);

        id roadObj = dict[@"road"] ?: dict[@"street"] ?: dict[@"streetName"] ?: dict[@"street_name"] ?: dict[@"nextRoad"] ?: dict[@"next_street"] ?: dict[@"roadName"] ?: dict[@"target"] ?: dict[@"name"] ?: dict[@"destinationStreetName"];
        if ([roadObj isKindOfClass:[NSString class]]) {
            road = (NSString *)roadObj;
        } else if ([roadObj isKindOfClass:[NSDictionary class]]) {
            road = ((NSDictionary *)roadObj)[@"name"] ?: @"";
        }

        id instObj = dict[@"instruction"] ?: dict[@"text"] ?: dict[@"description"] ?: dict[@"title"] ?: dict[@"bannerText"] ?: dict[@"primaryText"];
        if ([instObj isKindOfClass:[NSString class]]) {
            instruction = (NSString *)instObj;
            if (icon == 0) {
                icon = GVMMapInstructionTextToMazdaHUD(instruction);
            }
            if (!road || road.length == 0) {
                road = GVMExtractRoadName(instruction);
            }
        }

        id distObj = dict[@"distance"] ?: dict[@"length"] ?: dict[@"meters"] ?: dict[@"distanceRemaining"] ?: dict[@"dist"] ?: dict[@"remain"] ?: dict[@"stepDistance"] ?: dict[@"remainDistance"] ?: dict[@"remainingDistance"];
        if ([distObj respondsToSelector:@selector(doubleValue)]) {
            dist = [distObj doubleValue];
            if (dist > 50000.0) {
                dist = dist / 10.0; // decimeter to meter conversion
            }
        }
    } else if ([payload isKindOfClass:[NSString class]]) {
        instruction = (NSString *)payload;
        icon = GVMMapInstructionTextToMazdaHUD(instruction);
        road = GVMExtractRoadName(instruction);
    } else if ([payload isKindOfClass:[NSNumber class]]) {
        icon = GVMParseVietMapIcon(payload);
    }

    // Do NOT force Straight (1) if icon is 0: prevents false straight arrows at turns
    NSString *cleanRoad = GVMExtractRoadName(road ?: instruction ?: @"");
    if (!cleanRoad || cleanRoad.length == 0) {
        cleanRoad = road ?: instruction ?: @"";
    }
    cleanRoad = GVMNormalizeVietnameseForHUD(cleanRoad);

    NSUInteger finalDist = (NSUInteger)fmax(0.0, round(dist));
    if (finalDist == 0 && g_vmNavDistance > 0 && (received - g_vmNavLastReceived < 15.0)) {
        finalDist = g_vmNavDistance;
    }

    g_vmNavIcon = icon;
    g_vmNavDistance = finalDist;
    g_vmNavRoad = [cleanRoad copy];
    g_vmNavLastReceived = received;

    char navLog[512];
    time_t now = (time_t)received;
    struct tm *tm_info = localtime(&now);
    char timeStr[32];
    strftime(timeStr, sizeof(timeStr), "%H:%M:%S", tm_info);
    snprintf(navLog, sizeof(navLog), "[%s] [VM_NAV_INTERCEPT] icon=%u dist=%lu road=\"%s\"\n",
             timeStr, (unsigned int)icon, (unsigned long)finalDist, cleanRoad.UTF8String ?: "");
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-relay.log"];
    FILE *f = fopen(path.UTF8String, "a");
    if (f) {
        fputs(navLog, f);
        fclose(f);
    }

    GVMCMURelaySetNav(icon, finalDist, cleanRoad);
}

static void GVMHandleVietMapProgress(id args, NSTimeInterval received) {
    if (!args || args == [NSNull null]) return;
    id payload = args;
    if ([payload isKindOfClass:[NSArray class]] && [(NSArray *)payload count] > 0) {
        payload = [(NSArray *)payload firstObject];
    }
    double dist = 0.0;
    if ([payload respondsToSelector:@selector(doubleValue)]) {
        dist = [payload doubleValue];
    } else if ([payload isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)payload;
        id distObj = dict[@"distance"] ?: dict[@"distanceRemaining"] ?: dict[@"meters"] ?: dict[@"remain"] ?: dict[@"stepDistance"] ?: dict[@"dist"] ?: dict[@"remainDistance"] ?: dict[@"remainingDistance"];
        if ([distObj respondsToSelector:@selector(doubleValue)]) {
            dist = [distObj doubleValue];
        }
    } else if ([payload isKindOfClass:[NSString class]]) {
        dist = [(NSString *)payload doubleValue];
    }
    if (dist > 50000.0) {
        dist = dist / 10.0; // decimeter to meter conversion
    }

    NSUInteger finalDist = (NSUInteger)fmax(0.0, round(dist));
    g_vmNavDistance = finalDist;
    g_vmNavLastReceived = received;

    uint16_t icon = g_vmNavIcon;
    // Do NOT force Straight (1) if icon is 0: prevents false straight arrows at turns

    NSString *road = g_vmNavRoad ?: @"";
    GVMCMURelaySetNav(icon, finalDist, road);
}
#endif

static void SetMethodCallHandler(id channel, SEL selector, VMFlutterHandler handler) {
    NSString *name = GetChannelName(channel, channelNameIvar);
    if (!handler) {
        originalSetHandler(channel, selector, handler);
        return;
    }
    
    BOOL isTargetChannel = NO;
    if (name) {
        NSString *lower = [name lowercaseString];
        isTargetChannel = [lower isEqualToString:@"vietmap_car_method_channel"] ||
                          [lower isEqualToString:@"vml_main_channel"] ||
                          [lower containsString:@"tpms"] || [lower containsString:@"tire"] ||
                          [lower containsString:@"ble"] || [lower containsString:@"bluetooth"] ||
                          [lower containsString:@"device"] || [lower containsString:@"hardware"] ||
                          [lower containsString:@"sensor"] || [lower containsString:@"bt10"] ||
                          [lower containsString:@"tw50"];
    } else {
        isTargetChannel = YES;
    }
    
    if (!isTargetChannel) {
        originalSetHandler(channel, selector, handler);
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        BridgeLog([NSString stringWithFormat:@"VietMap channel handler registered: %@", name ?: @"unknown"]);
        GVMDiagnosticsRecord(GVMDiagnosticChannel,1);
    });
    VMFlutterHandler wrapped = ^(id<VMFlutterMethodCall> call, VMFlutterResult result) {
        NSArray *update = nil;
#ifdef VM_GOOGLE_MAPS_RELAY
        NSArray *overlaySticky=nil;
        NSArray<NSNumber *> *overlayLanes=nil;
#endif
        id mainLimit=nil; BOOL hasMainLimit=NO;
        NSTimeInterval received = NSProcessInfo.processInfo.systemUptime;
        @try {
#ifdef VM_GOOGLE_MAPS_RELAY
            NSString *cMethod = [call method];
            NSString *methodLower = [cMethod lowercaseString];
            BOOL isTireCall = [methodLower containsString:@"tpms"] ||
                              [methodLower containsString:@"tire"] ||
                              [methodLower containsString:@"pressure"] ||
                              [methodLower containsString:@"ble"] ||
                              [methodLower containsString:@"bluetooth"] ||
                              [methodLower containsString:@"sensor"] ||
                              [methodLower containsString:@"device"] ||
                              [methodLower containsString:@"hardware"] ||
                              [methodLower containsString:@"bt10"] ||
                              [methodLower containsString:@"tw50"];
            if (isTireCall) {
                GVMProcessTirePayload([call arguments], received);
                static NSTimeInterval lastCandidateLog = 0;
                if (received - lastCandidateLog > 2.0) {
                    lastCandidateLog = received;
                    BridgeLog([NSString stringWithFormat:@"[TPMS] Method candidate: %@ (channel: %@)", cMethod, name ?: @"unknown"]);
                }
            }
            if ([name isEqualToString:@"vml_main_channel"] && ([[call method] isEqualToString:@"updateLaneInfo"] ||
                [[call method] isEqualToString:@"cacheImage"]))
                ObserveAlerts([call method],[call arguments],0,received);
            if ([name isEqualToString:@"vietmap_car_method_channel"] && [[call method] isEqualToString:@"setNavigationImage"])
                ObserveAlerts(@"setNavigationImage",[call arguments],0,received);
            if ([name isEqualToString:@"vml_main_channel"] || [name isEqualToString:@"vietmap_car_method_channel"]) {
                NSString *cMethod = [call method];
                NSString *mLower = [cMethod lowercaseString];
                GVMDispatchVietMapNavMethod(mLower, [call arguments], received);
            }
            if ([name isEqualToString:@"vml_main_channel"] &&
                ([[call method] isEqualToString:@"updateUpcommingAlerts"] ||
                 [[call method] isEqualToString:@"updateStickyAlerts"])) {
                BOOL sticky=[[call method] isEqualToString:@"updateStickyAlerts"];
                id alertPayload=[call arguments];
                NSArray<NSDictionary *> *alerts=GVMVietMapAlertsFromPayload(alertPayload);
                ObserveAlerts([call method],alertPayload,alerts.count,received);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (sticky && received>=stickyReceived) { stickyAlerts=alerts; stickyReceived=received; }
                    else if (!sticky && received>=upcomingReceived) { upcomingAlerts=alerts; upcomingReceived=received; }
                    Publish();
                });
            }
#endif
            if ([name isEqualToString:@"vml_main_channel"] &&
                ([[call method] isEqualToString:@"updateCurrentSpeed"] || [[call method] isEqualToString:@"updateSpeedLimit"])) {
                id value=[call arguments];
                if ([[call method] isEqualToString:@"updateSpeedLimit"]) {
                    hasMainLimit=YES;
                    mainLimit=[value isKindOfClass:NSNumber.class] ? [value copy] : NSNull.null;
                }
                NSString *method=[[call method] copy];
                BOOL numeric=[value isKindOfClass:NSNumber.class];
                NSString *type=value ? NSStringFromClass([value class]) : @"nil";
                NSString *safeValue=numeric ? [value description] : @"not-numeric";
                dispatch_async(dispatch_get_main_queue(), ^{
                    static NSMutableDictionary *last;
                    if (!last) last=[NSMutableDictionary new];
                    if (!last[method] || received-[last[method] doubleValue]>=2) {
                        last[method]=@(received);
                        BridgeLog([NSString stringWithFormat:@"source-scalar method=%@ type=%@ value=%@",method,type,safeValue]);
                    }
                });
            }
            // Log only bounded method/type metadata; never argument values or coordinates.
            static NSMutableDictionary *methodTimes;
            @synchronized(source) {
                if (!methodTimes) methodTimes=[NSMutableDictionary new];
                NSString *method=[call method];
                if ([method isKindOfClass:NSString.class] && method.length<=80 &&
                    [method rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"] invertedSet]].location==NSNotFound) {
                    NSString *key=[name stringByAppendingFormat:@"/%@",method];
                    if (methodTimes[key] || methodTimes.count<32) {
                        if (!methodTimes[key] || received-[methodTimes[key] doubleValue]>=10) {
                            methodTimes[key]=@(received);
                            id args=[call arguments];
                            NSString *shape=[args isKindOfClass:NSArray.class] ? @"array" : [args isKindOfClass:NSDictionary.class] ? @"dictionary" : [args isKindOfClass:NSString.class] ? @"string" : @"other";
                            NSString *line=[NSString stringWithFormat:@"channel=%@ method=%@ type=%@",name,method,shape];
                            dispatch_async(dispatch_get_main_queue(), ^{ BridgeLog(line); });
                        }
                    }
                }
            }
            if ([name isEqualToString:@"vietmap_car_method_channel"] && [[call method] isEqualToString:@"updateMapOverlayData"])
            {
                #ifdef VM_GOOGLE_MAPS_RELAY
                overlaySticky=GVMVietMapOverlayStickyAlerts([call arguments]);
                overlayLanes=GVMVietMapOverlayLaneCodes([call arguments]);
                ObserveAlerts(@"updateMapOverlayData",[call arguments],overlaySticky.count,received);
#endif
                update = VMNavCopyOverlayArguments([call arguments]);
                BOOL valid=update!=nil;
                if (valid) {
                    NSUInteger shape=(update[0][@"speed"] ? 1 : 0) | (update[0][@"speedLimit"] ? 2 : 0) | ([update[1] boolValue] ? 4 : 0);
                    dispatch_async(dispatch_get_main_queue(), ^{ GVMDiagnosticsRecord(GVMDiagnosticShape,shape); });
                }
                dispatch_async(dispatch_get_main_queue(), ^{ GVMDiagnosticsRecord(GVMDiagnosticPayload,valid ? 1 : 2); });
            }
        } @catch (__unused NSException *exception) {}
        // Forward every call and its original reply block exactly once.
        handler(call, result);
        if (hasMainLimit) {
            id copiedLimit=mainLimit;
            dispatch_async(dispatch_get_main_queue(), ^{
                [source applyMainSpeedLimit:copiedLimit receivedAt:received];
                Publish();
            });
        }
        if (!update) return;
        dispatch_async(dispatch_get_main_queue(), ^{
#ifdef VM_GOOGLE_MAPS_RELAY
            if (overlaySticky && received>=stickyReceived) {
                stickyAlerts=overlaySticky; stickyReceived=received;
            }
            if (overlayLanes && received>=laneCodesReceived) { laneCodes=overlayLanes; laneCodesReceived=received; }
#endif
            [source applyArguments:update receivedAt:received];
            static NSTimeInterval lastLog;
            if (received - lastLog >= 5) {
                lastLog = received;
                NSDictionary *current = [source payloadAtUptime:NSProcessInfo.processInfo.systemUptime
                    timestamp:NSDate.date.timeIntervalSince1970];
                BridgeLog([NSString stringWithFormat:@"overlay state=%ld speed=%@ limit=%@",
                    (long)UIApplication.sharedApplication.applicationState, current[@"currentSpeed"], current[@"speedLimit"]]);
            }
            Publish();
        });
    };
    originalSetHandler(channel, selector, wrapped);
}

static void InstallHook(void) {
    if (hookInstalled) return;
    Class target = NSClassFromString(@"FlutterMethodChannel");
    SEL selector = NSSelectorFromString(@"setMethodCallHandler:");
    Method method = class_getInstanceMethod(target, selector);
    Ivar name = class_getInstanceVariable(target, "_name");
    if (!method || !name) { GVMDiagnosticsRecord(GVMDiagnosticHook,2); return; }
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 3 || strcmp(signature.methodReturnType, "v") ||
        strcmp([signature getArgumentTypeAtIndex:2], "@?") || ivar_getTypeEncoding(name)[0] != '@') {
        GVMDiagnosticsRecord(GVMDiagnosticHook,3);
        BridgeLog(@"unsupported Flutter channel ABI; provider inactive");
        return;
    }
    channelNameIvar = name;
    MSHookMessageEx(target, selector, (IMP)SetMethodCallHandler, (IMP *)&originalSetHandler);
#ifdef VM_GOOGLE_MAPS_RELAY
    SEL invokeSel = NSSelectorFromString(@"invokeMethod:arguments:");
    if (class_getInstanceMethod(target, invokeSel)) {
        MSHookMessageEx(target, invokeSel, (IMP)HookedInvokeMethod, (IMP *)&originalInvokeMethod);
    }
    SEL invokeResultSel = NSSelectorFromString(@"invokeMethod:arguments:result:");
    if (class_getInstanceMethod(target, invokeResultSel)) {
        MSHookMessageEx(target, invokeResultSel, (IMP)HookedInvokeMethodWithResult, (IMP *)&originalInvokeMethodWithResult);
    }
    // Also install EventChannel hook for tpmsDataStream
    Class eventTarget = NSClassFromString(@"FlutterEventChannel");
    SEL eventSelector = NSSelectorFromString(@"setStreamHandler:");
    Method eventMethod = class_getInstanceMethod(eventTarget, eventSelector);
    Ivar eventName = class_getInstanceVariable(eventTarget, "_name");
    if (eventMethod) {
        eventChannelNameIvar = eventName;
        MSHookMessageEx(eventTarget, eventSelector, (IMP)SetEventStreamHandler, (IMP *)&originalEventSetHandler);
        BridgeLog(@"EventChannel hook installed");
    }
#endif
    hookInstalled = YES;
    GVMDiagnosticsRecord(GVMDiagnosticHook,1);
    BridgeLog(@"overlay hook installed");
}

static void ImageLoaded(const struct mach_header *header, intptr_t slide) {
    // Class realization and hook installation happen outside the loader callback.
    dispatch_async(dispatch_get_main_queue(), ^{ InstallHook(); });
}

%ctor {
    @autoreleasepool {
        GVMDiagnosticsStart(@"vietmap");
#ifdef VM_GOOGLE_MAPS_RELAY
        GVMCMURelayStart();
        notify_register_check(GVMTPMSStateName, &tpmsToken);
#endif
        source = [VMNavSource new];
#ifdef VM_GOOGLE_MAPS_RELAY
        notify_register_dispatch(GVMOutputRequestName(GVMSourceVietMap).UTF8String,&requestToken,dispatch_get_main_queue(), ^(__unused int token) {
            if (GVMSelectedSourceID()!=GVMSourceVietMap) return;
            NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
            if (lastRequestHandled>=0 && now-lastRequestHandled<2) return;
            lastRequestHandled=now;
            NSDictionary *samples=[source freshSamplesAtUptime:now];
            GVMDiagnosticsRecord(GVMDiagnosticResponse,(samples[@"speed"] ? 1 : 0)|(samples[@"speedLimit"] ? 2 : 0));
            // Republish only fresh values with original timestamps. No undocumented Flutter calls.
            forceOutput=YES;
            Publish();
        });
#endif
        // Catch channel registration during application launch when Flutter is already loaded.
        InstallHook();
        _dyld_register_func_for_add_image(ImageLoaded);
        dispatch_async(dispatch_get_main_queue(), ^{
#ifdef VM_GOOGLE_MAPS_RELAY
            BridgeLog(@"independent Google Maps source loaded 0.1.0");
#else
            BridgeLog(@"bridge loaded 0.3.1");
#endif
            InstallHook();
            Publish();
            heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(heartbeat, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                2 * NSEC_PER_SEC, NSEC_PER_SEC / 4);
            dispatch_source_set_event_handler(heartbeat, ^{
                Publish();
#ifdef VM_GOOGLE_MAPS_RELAY
                if (g_vmNavIcon > 0 && g_vmNavLastReceived > 0 &&
                    (NSProcessInfo.processInfo.systemUptime - g_vmNavLastReceived > 25.0)) {
                    GVMHandleVietMapNavEnd();
                }
#endif
            });
            dispatch_resume(heartbeat);
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { Publish(); }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillTerminateNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
#ifdef VM_GOOGLE_MAPS_RELAY
                    upcomingAlerts=@[]; stickyAlerts=@[]; laneCodes=nil; forceOutput=YES;
                    GVMHandleVietMapNavEnd();
#endif
                    source = [VMNavSource new]; Publish();
                }];
        });
    }
}
