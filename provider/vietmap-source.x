#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <substrate.h>
#import <notify.h>
#import "nav-source.h"
#ifdef VM_GOOGLE_MAPS_RELAY
#import "speed-state.h"
#import "alert-state.h"
#import "vietmap-alert-assets.h"
static int speedToken = -1, limitToken = -1, firstAlertToken = -1, secondAlertToken = -1;
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
    uint64_t speed = GVMEncodeSample(samples[@"speed"][@"value"], [samples[@"speed"][@"receivedAt"] doubleValue]);
    uint64_t limit = GVMEncodeSample(samples[@"speedLimit"][@"value"], [samples[@"speedLimit"][@"receivedAt"] doubleValue]);
    if (!speedPublished || speed != lastSpeed) {
        if (notify_set_state(speedToken, speed) == NOTIFY_STATUS_OK) { speedPublished = YES; lastSpeed = speed; notify_post(GVMSpeedStateName); }
        else BridgeLog(@"speed publication refused");
    }
    if (!limitPublished || limit != lastLimit) {
        if (notify_set_state(limitToken, limit) == NOTIFY_STATUS_OK) { limitPublished = YES; lastLimit = limit; notify_post(GVMLimitStateName); }
        else BridgeLog(@"limit publication refused");
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

static void SetMethodCallHandler(id channel, SEL selector, VMFlutterHandler handler) {
    id name = object_getIvar(channel, channelNameIvar);
    if (!handler || ![name isKindOfClass:NSString.class] || (![name isEqualToString:@"vietmap_car_method_channel"] && ![name isEqualToString:@"vml_main_channel"])) {
        originalSetHandler(channel, selector, handler);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ BridgeLog(@"VietMap overlay handler registered"); });
    VMFlutterHandler wrapped = ^(id<VMFlutterMethodCall> call, VMFlutterResult result) {
        NSArray *update = nil;
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
                    if (sticky) { stickyAlerts=alerts; stickyReceived=received; }
                    else { upcomingAlerts=alerts; upcomingReceived=received; }
                    Publish();
                });
            }
#endif
            if ([name isEqualToString:@"vietmap_car_method_channel"] && [[call method] isEqualToString:@"updateMapOverlayData"])
                update = VMNavCopyOverlayArguments([call arguments]);
        } @catch (__unused NSException *exception) {}
        // Forward every call and its original reply block exactly once.
        handler(call, result);
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
    if (!method || !name) return;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 3 || strcmp(signature.methodReturnType, "v") ||
        strcmp([signature getArgumentTypeAtIndex:2], "@?") || ivar_getTypeEncoding(name)[0] != '@') {
        BridgeLog(@"unsupported Flutter channel ABI; provider inactive");
        return;
    }
    channelNameIvar = name;
    MSHookMessageEx(target, selector, (IMP)SetMethodCallHandler, (IMP *)&originalSetHandler);
    hookInstalled = YES;
    BridgeLog(@"overlay hook installed");
}

static void ImageLoaded(const struct mach_header *header, intptr_t slide) {
    // Class realization and hook installation happen outside the loader callback.
    dispatch_async(dispatch_get_main_queue(), ^{ InstallHook(); });
}

%ctor {
    @autoreleasepool {
#ifdef VM_GOOGLE_MAPS_RELAY
        relayReady = notify_register_check(GVMSpeedStateName, &speedToken) == NOTIFY_STATUS_OK &&
            notify_register_check(GVMLimitStateName, &limitToken) == NOTIFY_STATUS_OK;
#endif
#ifdef VM_GOOGLE_MAPS_RELAY
        if (notify_register_check(GVMFirstAlertStateName,&firstAlertToken)==NOTIFY_STATUS_OK) {
            notify_set_state(firstAlertToken,0); notify_post(GVMFirstAlertStateName);
        }
        if (notify_register_check(GVMSecondAlertStateName,&secondAlertToken)==NOTIFY_STATUS_OK) {
            notify_set_state(secondAlertToken,0); notify_post(GVMSecondAlertStateName);
        }
#endif
        source = [VMNavSource new];
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
#endif
                    source = [VMNavSource new]; Publish();
                }];
        });
    }
}
