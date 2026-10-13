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
static int requestToken=-1;
static NSTimeInterval lastRequestHandled=-1;
static BOOL forceOutput;
static NSArray<NSDictionary *> *upcomingAlerts, *stickyAlerts;
static NSTimeInterval upcomingReceived, stickyReceived;
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
    GVMRefreshLocationSession();
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    NSDictionary *samples=[source freshSamplesAtUptime:now];
    GVMDiagnosticsRecord(GVMDiagnosticSamples,(samples[@"speed"] ? 1 : 0) | (samples[@"speedLimit"] ? 2 : 0) | (UIApplication.sharedApplication.applicationState==UIApplicationStateActive ? 4 : 0));
    if (GVMSelectedSourceID()!=GVMSourceVietMap) return;
    NSMutableArray *entries=[NSMutableArray new];
    for (NSDictionary *alert in upcomingAlerts)
        [entries addObject:@{@"sample":alert,@"receivedAt":@(upcomingReceived)}];
    for (NSDictionary *alert in stickyAlerts)
        [entries addObject:@{@"sample":alert,@"receivedAt":@(stickyReceived)}];
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

static void SetMethodCallHandler(id channel, SEL selector, VMFlutterHandler handler) {
    id name = object_getIvar(channel, channelNameIvar);
    if (!handler || ![name isKindOfClass:NSString.class] || (![name isEqualToString:@"vietmap_car_method_channel"] && ![name isEqualToString:@"vml_main_channel"])) {
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
            if ([name isEqualToString:@"vml_main_channel"] &&
                ([[call method] isEqualToString:@"updateUpcommingAlerts"] ||
                 [[call method] isEqualToString:@"updateStickyAlerts"])) {
                BOOL sticky=[[call method] isEqualToString:@"updateStickyAlerts"];
                id alertPayload=[call arguments];
                NSArray<NSDictionary *> *alerts=GVMVietMapAlertsFromPayload(alertPayload);
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
            dispatch_source_set_event_handler(heartbeat, ^{ Publish(); });
            dispatch_resume(heartbeat);
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { Publish(); }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillTerminateNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
#ifdef VM_GOOGLE_MAPS_RELAY
                    upcomingAlerts=@[]; stickyAlerts=@[]; forceOutput=YES;
#endif
                    source = [VMNavSource new]; Publish();
                }];
        });
    }
}
