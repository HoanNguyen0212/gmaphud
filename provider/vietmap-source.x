#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <substrate.h>
#import <notify.h>
#import "nav-source.h"
#import "diagnostics.h"
#ifdef VM_GOOGLE_MAPS_RELAY
#import "speed-state.h"
#import "alert-state.h"
#import "tpms-state.h"
#import "vietmap-alert-assets.h"
static int speedToken = -1, limitToken = -1, firstAlertToken = -1, secondAlertToken = -1, tpmsToken = -1;
static int requestToken=-1;
static NSTimeInterval lastRequestHandled=-1;
static BOOL relayReady, speedPublished, limitPublished;
static uint64_t lastSpeed, lastLimit;
static NSArray<NSDictionary *> *upcomingAlerts, *stickyAlerts;
static NSTimeInterval upcomingReceived, stickyReceived;
static uint64_t lastFirstAlert, lastSecondAlert;
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
    if (!relayReady) return;
    NSDictionary *samples = [source freshSamplesAtUptime:NSProcessInfo.processInfo.systemUptime];
    GVMDiagnosticsRecord(GVMDiagnosticSamples,(samples[@"speed"] ? 1 : 0) | (samples[@"speedLimit"] ? 2 : 0) | (UIApplication.sharedApplication.applicationState==UIApplicationStateActive ? 4 : 0));
    uint64_t speed = GVMEncodeSample(samples[@"speed"][@"value"], [samples[@"speed"][@"receivedAt"] doubleValue]);
    uint64_t limit = GVMEncodeSample(samples[@"speedLimit"][@"value"], [samples[@"speedLimit"][@"receivedAt"] doubleValue]);
    if (!speedPublished || speed != lastSpeed) {
        if (notify_set_state(speedToken, speed) == NOTIFY_STATUS_OK) { speedPublished = YES; lastSpeed = speed; notify_post(GVMSpeedStateName); }
        else { BridgeLog(@"speed publication refused"); GVMDiagnosticsRecord(GVMDiagnosticError,1); }
    }
    if (!limitPublished || limit != lastLimit) {
        if (notify_set_state(limitToken, limit) == NOTIFY_STATUS_OK) { limitPublished = YES; lastLimit = limit; notify_post(GVMLimitStateName); }
        else { BridgeLog(@"limit publication refused"); GVMDiagnosticsRecord(GVMDiagnosticError,1); }
    }
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    NSMutableArray<NSDictionary *> *entries=[NSMutableArray array];
    if (now-upcomingReceived<5)
        for (NSDictionary *alert in upcomingAlerts)
            [entries addObject:@{@"sample":alert,@"receivedAt":@(upcomingReceived)}];
    if (now-stickyReceived<5)
        for (NSDictionary *alert in stickyAlerts)
            [entries addObject:@{@"sample":alert,@"receivedAt":@(stickyReceived)}];
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        id da=a[@"sample"][@"distance"], db=b[@"sample"][@"distance"];
        if (da==NSNull.null && db==NSNull.null)
            return [b[@"receivedAt"] compare:a[@"receivedAt"]];
        if (da==NSNull.null) return NSOrderedDescending;
        if (db==NSNull.null) return NSOrderedAscending;
        NSComparisonResult order=[da compare:db];
        return order==NSOrderedSame ? [b[@"receivedAt"] compare:a[@"receivedAt"]] : order;
    }];
    NSMutableArray<NSDictionary *> *selected=[NSMutableArray arrayWithCapacity:2];
    for (NSDictionary *entry in entries) {
        BOOL duplicate=NO;
        for (NSDictionary *prior in selected)
            if ([prior[@"sample"] isEqual:entry[@"sample"]]) { duplicate=YES; break; }
        if (!duplicate) [selected addObject:entry];
        if (selected.count==2) break;
    }
    NSDictionary *firstEntry=selected.firstObject;
    NSDictionary *secondEntry=selected.count>1 ? selected[1] : nil;
    uint64_t first=GVMEncodeAlert(firstEntry[@"sample"],[firstEntry[@"receivedAt"] doubleValue]);
    uint64_t second=GVMEncodeAlert(secondEntry[@"sample"],[secondEntry[@"receivedAt"] doubleValue]);
    if (firstAlertToken>=0 && first!=lastFirstAlert && notify_set_state(firstAlertToken,first)==NOTIFY_STATUS_OK) {
        lastFirstAlert=first; notify_post(GVMFirstAlertStateName);
    }
    if (secondAlertToken>=0 && second!=lastSecondAlert && notify_set_state(secondAlertToken,second)==NOTIFY_STATUS_OK) {
        lastSecondAlert=second; notify_post(GVMSecondAlertStateName);
    }
#else
    NSDictionary *payload = [source payloadAtUptime:NSProcessInfo.processInfo.systemUptime
        timestamp:NSDate.date.timeIntervalSince1970];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"truedash_navprovider.plist"];
    if ([payload writeToFile:path atomically:YES]) notify_post("com.sensetechlab.navprovider.update");
    else BridgeLog(@"publish failed");
#endif
}

static GVMTPMSData g_liveTPMS;

static void GVMProcessTirePayload(id payload, NSTimeInterval received) {
    if (!payload) return;
    if ([payload isKindOfClass:NSString.class]) {
        NSData *data = [(NSString *)payload dataUsingEncoding:NSUTF8StringEncoding];
        if (data) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (json) payload = json;
        }
    }
    __block void (^parseTireEntry)(NSDictionary *);
    parseTireEntry = ^(NSDictionary *d) {
        if (!d || ![d isKindOfClass:NSDictionary.class]) return;
        id codeVal = d[@"code"] ?: d[@"position"] ?: d[@"tireId"] ?: d[@"tire"] ?: d[@"id"] ?: d[@"deviceID"];
        id pressVal = d[@"pressure"] ?: d[@"press"] ?: d[@"bar"] ?: d[@"kpa"] ?: d[@"p"];
        id tempVal = d[@"temperature"] ?: d[@"temp"] ?: d[@"t"];
        id warnVal = d[@"isPressureWarning"] ?: d[@"warning"] ?: d[@"warn"];
        id xieYaVal = d[@"isXieYa"] ?: d[@"leak"];
        
        GVMTPMSTire *target = NULL;
        NSString *codeStr = [codeVal description].lowercaseString;
        if ([codeStr isEqualToString:@"0"] || [codeStr containsString:@"fl"] || [codeStr containsString:@"front_left"] || [codeStr containsString:@"frontleft"]) {
            target = &g_liveTPMS.fl;
        } else if ([codeStr isEqualToString:@"1"] || [codeStr containsString:@"fr"] || [codeStr containsString:@"front_right"] || [codeStr containsString:@"frontright"]) {
            target = &g_liveTPMS.fr;
        } else if ([codeStr isEqualToString:@"2"] || [codeStr containsString:@"rl"] || [codeStr containsString:@"rear_left"] || [codeStr containsString:@"rearleft"]) {
            target = &g_liveTPMS.rl;
        } else if ([codeStr isEqualToString:@"3"] || [codeStr containsString:@"rr"] || [codeStr containsString:@"rear_right"] || [codeStr containsString:@"rearright"]) {
            target = &g_liveTPMS.rr;
        }
        
        if (!target) {
            if (d[@"fl"] || d[@"fr"] || d[@"rl"] || d[@"rr"] || d[@"0"] || d[@"1"] || d[@"2"] || d[@"3"]) {
                if (d[@"fl"] || d[@"0"]) { id sub = d[@"fl"] ?: d[@"0"]; if ([sub isKindOfClass:NSDictionary.class]) parseTireEntry(sub); }
                if (d[@"fr"] || d[@"1"]) { id sub = d[@"fr"] ?: d[@"1"]; if ([sub isKindOfClass:NSDictionary.class]) parseTireEntry(sub); }
                if (d[@"rl"] || d[@"2"]) { id sub = d[@"rl"] ?: d[@"2"]; if ([sub isKindOfClass:NSDictionary.class]) parseTireEntry(sub); }
                if (d[@"rr"] || d[@"3"]) { id sub = d[@"rr"] ?: d[@"3"]; if ([sub isKindOfClass:NSDictionary.class]) parseTireEntry(sub); }
            }
            return;
        }
        
        float p = 0.0f;
        if ([pressVal isKindOfClass:NSNumber.class]) p = [pressVal floatValue];
        else if ([pressVal isKindOfClass:NSString.class]) p = [pressVal floatValue];
        if (p > 50.0f) p = p / 100.0f;
        
        if (p > 0.01f) {
            target->pressure = p;
            target->active = YES;
        }
        if ([tempVal respondsToSelector:@selector(intValue)]) {
            target->temperature = [tempVal intValue];
        }
        BOOL isWarn = [warnVal respondsToSelector:@selector(boolValue)] && [warnVal boolValue];
        BOOL isLeak = [xieYaVal respondsToSelector:@selector(boolValue)] && [xieYaVal boolValue];
        if (isLeak) target->warning = 3;
        else if (isWarn) target->warning = (target->pressure < 1.8f) ? 1 : 2;
        else if (target->pressure < 1.8f && target->pressure > 0.1f) target->warning = 1;
        else if (target->pressure > 2.8f) target->warning = 2;
        else target->warning = 0;
    };
    
    if ([payload isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)payload) {
            if ([item isKindOfClass:NSDictionary.class]) parseTireEntry(item);
        }
    } else if ([payload isKindOfClass:NSDictionary.class]) {
        parseTireEntry((NSDictionary *)payload);
    }
    
    g_liveTPMS.hasData = (g_liveTPMS.fl.active || g_liveTPMS.fr.active || g_liveTPMS.rl.active || g_liveTPMS.rr.active);
    if (g_liveTPMS.hasData) {
        g_liveTPMS.receivedAt = received;
        uint64_t encoded = GVMEncodeTPMS(&g_liveTPMS, received);
        if (tpmsToken >= 0 && notify_set_state(tpmsToken, encoded) == NOTIFY_STATUS_OK) {
            notify_post(GVMTPMSStateName);
        }
        BridgeLog([NSString stringWithFormat:@"tpms update fl=%.1f fr=%.1f rl=%.1f rr=%.1f",
            g_liveTPMS.fl.pressure, g_liveTPMS.fr.pressure, g_liveTPMS.rl.pressure, g_liveTPMS.rr.pressure]);
    }
}

static GVMTPMSData GVMParseTPMSPayload(id args) {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    GVMProcessTirePayload(args, now);
    return g_liveTPMS;
}

static void (*originalEventSetHandler)(id, SEL, id);
static Ivar eventChannelNameIvar = NULL;

static void SetEventStreamHandler(id channel, SEL selector, id handler) {
    id name = object_getIvar(channel, eventChannelNameIvar);
    if (!handler || ![name isKindOfClass:NSString.class] ||
        ([name rangeOfString:@"tpms" options:NSCaseInsensitiveSearch].location == NSNotFound &&
         [name rangeOfString:@"tire" options:NSCaseInsensitiveSearch].location == NSNotFound)) {
        originalEventSetHandler(channel, selector, handler);
        return;
    }
    BridgeLog([NSString stringWithFormat:@"Hooking TPMS EventChannel: %@", name]);
    Class handlerClass = [handler class];
    SEL onListenSel = NSSelectorFromString(@"onListenWithArguments:eventSink:");
    Method m = class_getInstanceMethod(handlerClass, onListenSel);
    if (m) {
        __block id (*origOnListen)(id, SEL, id, id) = (id (*)(id, SEL, id, id))method_getImplementation(m);
        id newImp = ^(id selfHandler, id args, id eventSink) {
            BridgeLog(@"TPMS event sink registered");
            id wrappedSink = ^(id event) {
                NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
                GVMProcessTirePayload(event, now);
                if (eventSink) ((void (^)(id))eventSink)(event);
            };
            return origOnListen(selfHandler, onListenSel, args, wrappedSink);
        };
        class_replaceMethod(handlerClass, onListenSel, imp_implementationWithBlock(newImp), method_getTypeEncoding(m));
    }
    originalEventSetHandler(channel, selector, handler);
}

static void SetMethodCallHandler(id channel, SEL selector, VMFlutterHandler handler) {
    id name = object_getIvar(channel, channelNameIvar);
    BOOL isKnownChannel = [name isEqualToString:@"vietmap_car_method_channel"] || [name isEqualToString:@"vml_main_channel"] ||
        [name rangeOfString:@"tpms" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [name rangeOfString:@"tire" options:NSCaseInsensitiveSearch].location != NSNotFound;
    if (!handler || ![name isKindOfClass:NSString.class] || !isKnownChannel) {
        originalSetHandler(channel, selector, handler);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ BridgeLog(@"VietMap overlay handler registered"); GVMDiagnosticsRecord(GVMDiagnosticChannel,1); });
    VMFlutterHandler wrapped = ^(id<VMFlutterMethodCall> call, VMFlutterResult result) {
        NSArray *update = nil;
        id mainLimit=nil; BOOL hasMainLimit=NO;
        NSTimeInterval received = NSProcessInfo.processInfo.systemUptime;
        @try {
    #ifdef VM_GOOGLE_MAPS_RELAY
            NSString *cMethod = [call method];
            if ([cMethod rangeOfString:@"tpms" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [cMethod rangeOfString:@"tire" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [cMethod rangeOfString:@"pressure" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                GVMTPMSData tpmsData = GVMParseTPMSPayload([call arguments]);
                if (tpmsData.hasData) {
                    tpmsData.receivedAt = received;
                    uint64_t encoded = GVMEncodeTPMS(&tpmsData, received);
                    if (tpmsToken >= 0 && notify_set_state(tpmsToken, encoded) == NOTIFY_STATUS_OK) {
                        notify_post(GVMTPMSStateName);
                    }
                    BridgeLog([NSString stringWithFormat:@"tpms published fl=%.1f fr=%.1f rl=%.1f rr=%.1f",
                        tpmsData.fl.pressure, tpmsData.fr.pressure, tpmsData.rl.pressure, tpmsData.rr.pressure]);
                }
            }
            if ([name isEqualToString:@"vml_main_channel"] &&
                ([[call method] isEqualToString:@"updateUpcommingAlerts"] ||
                 [[call method] isEqualToString:@"updateStickyAlerts"])) {
                BOOL sticky=[[call method] isEqualToString:@"updateStickyAlerts"];
                id alertPayload=[call arguments];
                NSArray<NSDictionary *> *alerts=GVMVietMapAlertsFromPayload(alertPayload);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (sticky) { stickyAlerts=alerts; stickyReceived=received; }
                    else { upcomingAlerts=alerts; upcomingReceived=received; }
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
    
    // Also install EventChannel hook for tpmsDataStream
    Class eventTarget = NSClassFromString(@"FlutterEventChannel");
    SEL eventSelector = NSSelectorFromString(@"setStreamHandler:");
    Method eventMethod = class_getInstanceMethod(eventTarget, eventSelector);
    Ivar eventName = class_getInstanceVariable(eventTarget, "_name");
    if (eventMethod && eventName) {
        eventChannelNameIvar = eventName;
        MSHookMessageEx(eventTarget, eventSelector, (IMP)SetEventStreamHandler, (IMP *)&originalEventSetHandler);
        BridgeLog(@"EventChannel hook installed");
    }
    
    // Also hook native TPMSData if loaded
    Class tpmsDataCls = NSClassFromString(@"TPMSData");
    if (tpmsDataCls) {
        SEL setPressSel = NSSelectorFromString(@"setPressure:");
        Method setPressMethod = class_getInstanceMethod(tpmsDataCls, setPressSel);
        if (setPressMethod) {
            static void (*origSetPress)(id, SEL, float);
            void (^newSetPress)(id, float) = ^(id tpmsObj, float p) {
                if (origSetPress) origSetPress(tpmsObj, setPressSel, p);
                NSString *devId = [tpmsObj respondsToSelector:NSSelectorFromString(@"deviceID")] ?
                    ((NSString *(*)(id, SEL))objc_msgSend)(tpmsObj, NSSelectorFromString(@"deviceID")) : nil;
                NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
                NSDictionary *d = @{@"code": devId ?: @"0", @"pressure": @(p)};
                GVMProcessTirePayload(d, now);
            };
            MSHookMessageEx(tpmsDataCls, setPressSel, imp_implementationWithBlock(newSetPress), (IMP *)&origSetPress);
            BridgeLog(@"TPMSData hook installed");
        }
    }
    
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
        relayReady = notify_register_check(GVMSpeedStateName, &speedToken) == NOTIFY_STATUS_OK &&
            notify_register_check(GVMLimitStateName, &limitToken) == NOTIFY_STATUS_OK;
        notify_register_check(GVMTPMSStateName, &tpmsToken);
#endif
#ifdef VM_GOOGLE_MAPS_RELAY
        if (notify_register_check(GVMFirstAlertStateName,&firstAlertToken)==NOTIFY_STATUS_OK) {
            notify_set_state(firstAlertToken,0); notify_post(GVMFirstAlertStateName);
        }
        if (notify_register_check(GVMSecondAlertStateName,&secondAlertToken)==NOTIFY_STATUS_OK) {
            notify_set_state(secondAlertToken,0); notify_post(GVMSecondAlertStateName);
        }
#endif
#ifdef VM_GOOGLE_MAPS_RELAY
        if (!relayReady) GVMDiagnosticsRecord(GVMDiagnosticError,1);
#endif
        source = [VMNavSource new];
#ifdef VM_GOOGLE_MAPS_RELAY
        notify_register_dispatch(GVMSourceRequestName,&requestToken,dispatch_get_main_queue(), ^(__unused int token) {
            NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
            if (lastRequestHandled>=0 && now-lastRequestHandled<2) return;
            lastRequestHandled=now;
            NSDictionary *samples=[source freshSamplesAtUptime:now];
            GVMDiagnosticsRecord(GVMDiagnosticResponse,(samples[@"speed"] ? 1 : 0)|(samples[@"speedLimit"] ? 2 : 0));
            // Republish only fresh values with original timestamps. No undocumented Flutter calls.
            speedPublished=NO; limitPublished=NO;
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
            dispatch_source_set_event_handler(heartbeat, ^{ Publish(); });
            dispatch_resume(heartbeat);
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { Publish(); }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillTerminateNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
#ifdef VM_GOOGLE_MAPS_RELAY
                    if (firstAlertToken>=0) { notify_set_state(firstAlertToken,0); notify_post(GVMFirstAlertStateName); }
                    if (secondAlertToken>=0) { notify_set_state(secondAlertToken,0); notify_post(GVMSecondAlertStateName); }
                    if (tpmsToken>=0) { notify_set_state(tpmsToken,0); notify_post(GVMTPMSStateName); }
#endif
                    source = [VMNavSource new]; Publish();
                }];
        });
    }
}
