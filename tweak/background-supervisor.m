#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "background-policy.h"
#import "source-transport.h"
#import "cmu-wifi-autoconnect.h"
#include <notify.h>
#include <string.h>

static int heartbeatToken = -1, phoneToken=-1, permissionToken = -1, locationSessionToken=-1, sourceSessionToken=-1, wakeRequestToken=-1;
static id assertion;
static id locationUsageContext;
static pid_t heldPID, googlePID;
static unsigned attempts;
static double nextLaunch, nextAssertion;
static double nextUsageContext;
static BOOL sessionActive;
static NSInteger lastPermission = NSIntegerMin;
static BOOL lastEnabled;
static NSString *providerID;
static NSUInteger managedSource;
static id carplayStatus;
static BOOL wasConnected, exitCompleted, exitDeferred;
static double disconnectedAt;
static pid_t managedPID;
static NSString *BundleForSource(NSUInteger source) {
    if (!GVMSourceEnabled(source)) return @"vn.vietmap.live";
    switch(source) {
        case GVMSourceVietMap: return @"vn.vietmap.live";
        case GVMSourceWaze: return @"com.waze.iphone";
        case GVMSourceGofa: return @"com.lumi.GOFA";
        default: return @"vn.vietmap.live";
    }
}
static const char *Base(const char *type);
static BOOL BooleanPreference(CFStringRef key, BOOL defaultValue) {
    CFStringRef domain = CFSTR("com.chou.gmaphud");
    CFPreferencesAppSynchronize(domain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(key, domain));
    if (!value) return defaultValue;
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : defaultValue;
}
static NSInteger ProviderLocationPermission(void) {
    Class manager=NSClassFromString(@"CLLocationManager");
    SEL selector=NSSelectorFromString(@"authorizationStatusForBundleIdentifier:");
    NSMethodSignature *signature=[manager methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments!=3 || strcmp(Base(signature.methodReturnType),"i") ||
        strcmp(Base([signature getArgumentTypeAtIndex:2]),"@")) return NSIntegerMin;
    return ((int (*)(id,SEL,id))objc_msgSend)(manager,selector,providerID);
}

static void Record(NSString *message) {
    NSString *path = @"/var/mobile/Library/Logs/gmaphud-background.log";
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    if ([[fm attributesOfItemAtPath:path error:nil] fileSize] > 32768) [fm removeItemAtPath:path error:nil];
    if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
    @try {
        [file seekToEndOfFile];
        [file writeData:[[NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, message] dataUsingEncoding:NSUTF8StringEncoding]];
    } @finally { [file closeFile]; }
}
static const char *Base(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}
static BOOL Matches(id object, NSString *name, const char *result, NSArray<NSString *> *arguments) {
    NSMethodSignature *signature = [object methodSignatureForSelector:NSSelectorFromString(name)];
    if (!signature || signature.numberOfArguments != arguments.count + 2 || strcmp(Base(signature.methodReturnType), result)) return NO;
    for (NSUInteger i=0; i<arguments.count; i++)
        if (strcmp(Base([signature getArgumentTypeAtIndex:i+2]), arguments[i].UTF8String)) return NO;
    return YES;
}
static id Shared(NSString *name, NSString *selector) {
    Class cls=NSClassFromString(name);
    return Matches(cls,selector,"@",@[]) ? ((id (*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(selector)) : nil;
}
static void ReleaseLocationUsage(void) {
    id previous=locationUsageContext; locationUsageContext=nil;
    nextUsageContext=0;
    if (previous && Matches(previous,@"invalidate","v",@[])) {
        ((void (*)(id,SEL))objc_msgSend)(previous,@selector(invalidate));
        Record(@"temporary location in-use context released");
    }
}
static void RefreshLocationUsage(NSInteger permission,BOOL active,double now) {
    if (!GVMBackgroundNeedsUsageContext((int)permission,active)) {
        ReleaseLocationUsage(); return;
    }
    if (locationUsageContext || now<nextUsageContext) return;
    nextUsageContext=now+30;
    Class cls=NSClassFromString(@"CLInUseAssertion");
    NSString *name=@"newAssertionForBundleIdentifier:withReason:";
    Method end=class_getInstanceMethod(cls,@selector(invalidate));
    NSMethodSignature *signature=end ? [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(end)] : nil;
    if (!Matches(cls,name,"@",@[@"@",@"@"]) || !signature ||
        signature.numberOfArguments!=2 || strcmp(Base(signature.methodReturnType),"v")) {
        Record(@"temporary location in-use context unavailable: private ABI"); return;
    }
    // The new-family factory returns an owned assertion; this does not alter authorization.
    @try {
        void *owned=((void * (*)(id,SEL,id,id))objc_msgSend)(cls,NSSelectorFromString(name),
            providerID,@"GMapHUD visible Google Maps source");
        locationUsageContext=(__bridge_transfer id)owned;
        Record([NSString stringWithFormat:@"temporary location in-use context requested=%d; GPS activation unverified",locationUsageContext!=nil]);
    } @catch (NSException *exception) {
        Record([@"temporary location in-use context request failed: " stringByAppendingString:exception.name]);
    }
}
static void Release(void) {
    id previous=assertion; assertion=nil; heldPID=0;
    if (previous && Matches(previous,@"invalidate","v",@[])) {
        ((void (*)(id,SEL))objc_msgSend)(previous,NSSelectorFromString(@"invalidate"));
        Record(@"background execution released");
    }
}
static BOOL Acquire(pid_t pid) {
    Class attributeClass=NSClassFromString(@"RBSDomainAttribute"), targetClass=NSClassFromString(@"RBSTarget");
    id candidate=[NSClassFromString(@"RBSAssertion") alloc];
    if (!Matches(attributeClass,@"attributeWithDomain:name:","@",@[@"@",@"@"]) ||
        !Matches(targetClass,@"targetWithPid:","@",@[@"i"]) ||
        !Matches(candidate,@"initWithExplanation:target:attributes:","@",@[@"@",@"@",@"@"]) ||
        !Matches(candidate,@"acquireWithError:","B",@[@"^@"]) || !Matches(candidate,@"invalidate","v",@[])) {
        Record(@"background execution unavailable: private ABI"); return NO;
    }
    id attribute=((id (*)(id,SEL,id,id))objc_msgSend)(attributeClass,NSSelectorFromString(@"attributeWithDomain:name:"),@"com.apple.frontboard",@"Workspace-BackgroundActive");
    id target=((id (*)(id,SEL,pid_t))objc_msgSend)(targetClass,NSSelectorFromString(@"targetWithPid:"),pid);
    if (!attribute || !target) return NO;
    candidate=((id (*)(id,SEL,id,id,id))objc_msgSend)(candidate,NSSelectorFromString(@"initWithExplanation:target:attributes:"),@"GMapHUD visible Google Maps source",target,@[attribute]);
    NSError *error=nil;
    BOOL acquired=((BOOL (*)(id,SEL,NSError *__autoreleasing *))objc_msgSend)(candidate,NSSelectorFromString(@"acquireWithError:"),&error);
    Record([NSString stringWithFormat:@"background execution acquired=%d error=%@ code=%ld",acquired,error.domain ?: @"none",(long)error.code]);
    if (acquired) { assertion=candidate; heldPID=pid; }
    else if (candidate) ((void (*)(id,SEL))objc_msgSend)(candidate,NSSelectorFromString(@"invalidate"));
    return acquired;
}
static void Launch(void) {
    if (!providerID) providerID = @"vn.vietmap.live";
    id service = Shared(@"FBSOpenApplicationService", @"serviceWithDefaultShellEndpoint");
    Class optionsClass = NSClassFromString(@"FBSOpenApplicationOptions");
    if (service && optionsClass) {
        SEL optSel = NSSelectorFromString(@"optionsWithDictionary:");
        SEL openSel = NSSelectorFromString(@"openApplication:withOptions:completion:");
        if ([optionsClass respondsToSelector:optSel] && [service respondsToSelector:openSel]) {
            id options = ((id (*)(id, SEL, id))objc_msgSend)(optionsClass, optSel,
                @{@"__ActivateSuspended": @YES, @"__PromptUnlockDevice": @NO, @"__UnlockDevice": @NO});
            if (options) {
                ((void (*)(id, SEL, id, id, id))objc_msgSend)(service, openSel, providerID, options, nil);
                Record([NSString stringWithFormat:@"[AutoWake] FBSOpenApplicationService suspended launch requested for %@", providerID]);
                return;
            }
        }
    }
    // Fallback via LSApplicationWorkspace
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (wsClass && [wsClass respondsToSelector:NSSelectorFromString(@"defaultWorkspace")]) {
        id workspace = ((id (*)(id, SEL))objc_msgSend)(wsClass, NSSelectorFromString(@"defaultWorkspace"));
        SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
        if (workspace && [workspace respondsToSelector:openSel]) {
            ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, openSel, providerID);
            Record([NSString stringWithFormat:@"[AutoWake] LSApplicationWorkspace launch requested for %@", providerID]);
        }
    }
}
static void ClearLease(void) {
    if (locationSessionToken>=0) notify_set_state(locationSessionToken,0);
    if (sourceSessionToken>=0) notify_set_state(sourceSessionToken,0);
    ReleaseLocationUsage(); Release();
    sessionActive=NO; googlePID=0; attempts=0; nextLaunch=0; nextAssertion=0;
}
static void CloseManagedProvider(id service,NSString *reason) {
    if (!providerID || managedPID<=0 || !Matches(service,@"pidForApplication:","i",@[@"@"]) ||
        !Matches(service,@"terminateApplication:forReason:andReport:withDescription:","v",@[@"@",@"q",@"B",@"@"])) return;
    pid_t pid=((pid_t (*)(id,SEL,id))objc_msgSend)(service,NSSelectorFromString(@"pidForApplication:"),providerID);
    // Never close a replacement process we did not manage.
    if (pid==managedPID) {
        ((void (*)(id,SEL,id,NSInteger,BOOL,id))objc_msgSend)(service,
            NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:"),providerID,1,NO,reason);
        Record([NSString stringWithFormat:@"close requested source=%lu pid=%d reason=%@",(unsigned long)managedSource,pid,reason]);
    }
    managedPID=0;
}
static void Tick(void) {
    double now=NSProcessInfo.processInfo.systemUptime;
    id service=Shared(@"FBSSystemService",@"sharedService");
    NSUInteger selected=GVMSelectedSourceID();
    if (selected!=managedSource) {
        ClearLease();
        CloseManagedProvider(service,@"GMapHUD warning source changed");
        providerID=BundleForSource(selected); managedSource=selected; disconnectedAt=0;
        Record([NSString stringWithFormat:@"selected source=%lu",(unsigned long)selected]);
    }
    BOOL connected=carplayStatus && Matches(carplayStatus,@"currentSession","@",@[]) &&
        ((id (*)(id,SEL))objc_msgSend)(carplayStatus,NSSelectorFromString(@"currentSession"))!=nil;
    uint64_t heartbeat=0,phoneHeartbeat=0;
    if (heartbeatToken>=0) notify_get_state(heartbeatToken,&heartbeat);
    if (phoneToken>=0) notify_get_state(phoneToken,&phoneHeartbeat);
    BOOL phoneVisible=GVMBackgroundActive(now,phoneHeartbeat);
    if (connected) { disconnectedAt=0; exitCompleted=NO; }
    else if (wasConnected) {
        disconnectedAt=now;
        Record(@"CarPlay disconnected; 20 second exit countdown started");
    }
    if (connected != wasConnected) {
        GVMCMUOnCarPlayConnectionChanged(connected);
    }
    if (connected) {
        GVMCMUWiFiAutoConnectTick();
    }
    wasConnected=connected;
    BOOL autoExit = BooleanPreference(CFSTR("autoExit"), NO);
    if (!autoExit) { disconnectedAt = 0; exitCompleted = NO; }
    // Google Maps visible on the iPhone is still in use: restart the exit countdown from when
    // it is hidden, and let it wake a source that auto-exit already closed.
    if (phoneVisible && (disconnectedAt > 0 || exitCompleted)) {
        if (!exitDeferred) Record(@"iPhone Google Maps visible; CarPlay exit deferred");
        exitDeferred = YES; exitCompleted = NO;
        if (disconnectedAt > 0) disconnectedAt = now;
    } else exitDeferred = NO;
    if (connected && autoExit && providerID && Matches(service, @"pidForApplication:", "i", @[@"@"]))
        managedPID = ((pid_t (*)(id, SEL, id))objc_msgSend)(service, NSSelectorFromString(@"pidForApplication:"), providerID);
    if (autoExit && !connected && GVMBackgroundDisconnectDue(now, disconnectedAt)) {
        ClearLease(); CloseManagedProvider(service, @"GMapHUD CarPlay disconnected for 20 seconds");
        disconnectedAt = 0; exitCompleted = YES;
    }
    
    BOOL enabled = BooleanPreference(CFSTR("autoWake"), YES);
    NSInteger permission = providerID ? ProviderLocationPermission() : NSIntegerMin;
    BOOL allowed = (permission == NSIntegerMin) || (GVMBackgroundLocationAuthorized((int)permission) && CLLocationManager.locationServicesEnabled);
    if (permissionToken >= 0) notify_set_state(permissionToken, GVMBackgroundPermissionState(now, allowed));
    if (enabled != lastEnabled || permission != lastPermission) {
        Record([NSString stringWithFormat:@"automatic wake enabled=%d source=%lu permission=%ld", enabled, (unsigned long)selected, (long)permission]);
        lastEnabled = enabled; lastPermission = permission;
    }
    
    pid_t clientPID = 0;
    if (service && Matches(service, @"pidForApplication:", "i", @[@"@"])) {
        clientPID = ((pid_t (*)(id, SEL, id))objc_msgSend)(service, NSSelectorFromString(@"pidForApplication:"), @"com.google.Maps");
    }

    // Auto-wake trigger condition:
    // When CarPlay is connected, OR when Google Maps is running on CarPlay/iPhone, OR when iPhone map visible
    BOOL shouldRun = (connected || clientPID > 0 || phoneVisible);
    BOOL active = enabled && allowed && providerID && shouldRun &&
        !GVMBackgroundExitHolds(autoExit, connected, phoneVisible, disconnectedAt, exitCompleted);
        
    if (!active || !service || !Matches(service, @"pidForApplication:", "i", @[@"@"])) {
        if (!connected && !phoneVisible && clientPID <= 0) {
            ClearLease();
        }
        return;
    }
    
    if (clientPID > 0 && GVMBackgroundNewClient(googlePID, clientPID)) { attempts = 0; nextLaunch = 0; }
    if (clientPID > 0) googlePID = clientPID;
    
    if (!sessionActive) { sessionActive = YES; Record(@"selected source supervisor started"); }
    if (sourceSessionToken >= 0) notify_set_state(sourceSessionToken, selected ?: 1);
    if (locationSessionToken >= 0) notify_set_state(locationSessionToken, GVMBackgroundPermissionState(now, YES));
    RefreshLocationUsage(permission, YES, now);
    
    pid_t pid = ((pid_t (*)(id, SEL, id))objc_msgSend)(service, NSSelectorFromString(@"pidForApplication:"), providerID);
    if (heldPID && heldPID != pid) { Release(); nextAssertion = 0; }
    if (pid > 0) {
        managedPID = pid; attempts = 0; nextLaunch = 0;
        // Acquiring a background-active assertion resumes a suspended process as well.
        if (!assertion && now >= nextAssertion) { nextAssertion = now + 15; Acquire(pid); }
        return;
    }
    managedPID = 0;
    if (now >= nextLaunch) {
        attempts++; nextLaunch = now + 10; Launch();
    }
}
__attribute__((constructor)) static void Start(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
    dlopen("/System/Library/PrivateFrameworks/CarKit.framework/CarKit",RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices",RTLD_NOW);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (notify_register_check(GVM_BACKGROUND_SIGNAL,&heartbeatToken)!=NOTIFY_STATUS_OK) return;
        notify_register_check(GVM_BACKGROUND_PHONE_SIGNAL,&phoneToken);
        notify_register_check(GVM_BACKGROUND_PERMISSION,&permissionToken);
        notify_register_check(GVM_BACKGROUND_LOCATION_SESSION,&locationSessionToken);
        notify_register_check(GVM_BACKGROUND_LOCATION_SOURCE,&sourceSessionToken);
        notify_register_dispatch("com.chou.gmaphud.autowake.request", &wakeRequestToken, dispatch_get_main_queue(), ^(__unused int token) {
            Record(@"[AutoWake] Wake request signal received, triggering immediate Tick()");
            Tick();
        });
        Class statusClass=NSClassFromString(@"CARSessionStatus");
        if (Matches(statusClass,@"new","@",@[])) carplayStatus=[statusClass new];
        GVMCMUWiFiAutoConnectStart();
        Tick();
        Record(@"supervisor 0.1.24 loaded; awaiting visible Google Maps on CarPlay or iPhone");
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(__unused NSTimer *timer) {
            @try { Tick(); }
            @catch (__unused NSException *exception) {
                @try { ReleaseLocationUsage(); } @catch (__unused NSException *cleanup) {}
                @try { Release(); } @catch (__unused NSException *cleanup) {}
                nextUsageContext=NSProcessInfo.processInfo.systemUptime+30;
                nextAssertion=NSProcessInfo.processInfo.systemUptime+30;
            }
        }];
    });
}
