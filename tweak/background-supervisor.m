#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "background-policy.h"
#import "source-transport.h"
#include <notify.h>
#include <string.h>

static int heartbeatToken = -1, phoneToken=-1, permissionToken = -1, locationSessionToken=-1, sourceSessionToken=-1;
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
static BOOL wasConnected, exitCompleted;
static double disconnectedAt;
static pid_t managedPID;
static NSString *BundleForSource(NSUInteger source) {
    if (!GVMSourceEnabled(source)) return nil;
    switch(source) {
        case GVMSourceVietMap: return @"vn.vietmap.live";
        case GVMSourceWaze: return @"com.waze.iphone";
        case GVMSourceGofa: return @"com.lumi.GOFA";
        default: return nil;
    }
}
static const char *Base(const char *type);
static BOOL BooleanPreference(CFStringRef key) {
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesAppSynchronize(domain);
    id value=CFBridgingRelease(CFPreferencesCopyAppValue(key,domain));
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
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
    id service=Shared(@"FBSOpenApplicationService",@"serviceWithDefaultShellEndpoint");
    Class optionsClass=NSClassFromString(@"FBSOpenApplicationOptions");
    if (!Matches(service,@"openApplication:withOptions:completion:","v",@[@"@",@"@",@"@?"]) ||
        !Matches(optionsClass,@"optionsWithDictionary:","@",@[@"@"])) {
        Record(@"background launch unavailable: private ABI"); return;
    }
    id options=((id (*)(id,SEL,id))objc_msgSend)(optionsClass,NSSelectorFromString(@"optionsWithDictionary:"),
        @{@"__ActivateSuspended":@YES,@"__PromptUnlockDevice":@NO,@"__UnlockDevice":@NO});
    if (!options) return;
    ((void (*)(id,SEL,id,id,id))objc_msgSend)(service,NSSelectorFromString(@"openApplication:withOptions:completion:"),providerID,options,nil);
    Record(@"suspended launch requested; fresh source data still requires verification");
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
    if (connected) { disconnectedAt=0; exitCompleted=NO; }
    else if (wasConnected) {
        disconnectedAt=now;
        Record(@"CarPlay disconnected; 20 second exit countdown started");
    }
    wasConnected=connected;
    BOOL autoExit=BooleanPreference(CFSTR("autoExit"));
    if (!autoExit) { disconnectedAt=0; exitCompleted=NO; }
    if (connected && autoExit && providerID && Matches(service,@"pidForApplication:","i",@[@"@"]))
        managedPID=((pid_t (*)(id,SEL,id))objc_msgSend)(service,NSSelectorFromString(@"pidForApplication:"),providerID);
    if (autoExit && !connected && GVMBackgroundDisconnectDue(now,disconnectedAt)) {
        ClearLease(); CloseManagedProvider(service,@"GMapHUD CarPlay disconnected for 20 seconds");
        disconnectedAt=0; exitCompleted=YES;
    }
    BOOL enabled=BooleanPreference(CFSTR("autoWake"));
    NSInteger permission=providerID ? ProviderLocationPermission() : NSIntegerMin;
    BOOL allowed=GVMBackgroundLocationAuthorized((int)permission) && CLLocationManager.locationServicesEnabled;
    if (permissionToken>=0) notify_set_state(permissionToken,GVMBackgroundPermissionState(now,allowed));
    if (enabled!=lastEnabled || permission!=lastPermission) {
        Record([NSString stringWithFormat:@"automatic wake enabled=%d source=%lu permission=%ld",enabled,(unsigned long)selected,(long)permission]);
        lastEnabled=enabled; lastPermission=permission;
    }
    uint64_t heartbeat=0,phoneHeartbeat=0;
    if (heartbeatToken>=0) notify_get_state(heartbeatToken,&heartbeat);
    if (phoneToken>=0) notify_get_state(phoneToken,&phoneHeartbeat);
    // CarPlay connection is distinct from a visible-map heartbeat. Phone display works when
    // no disconnect countdown is pending; it cannot re-wake a just-closed CarPlay source.
    BOOL hostActive=GVMBackgroundAnyHostActive(now,connected ? heartbeat : 0,phoneHeartbeat);
    BOOL active=enabled && allowed && providerID && hostActive &&
        !(autoExit && !connected && (disconnectedAt>0 || exitCompleted));
    if (!active || !Matches(service,@"pidForApplication:","i",@[@"@"])) { ClearLease(); return; }
    pid_t clientPID=((pid_t (*)(id,SEL,id))objc_msgSend)(service,NSSelectorFromString(@"pidForApplication:"),@"com.google.Maps");
    if (clientPID<=0) { ClearLease(); return; }
    if (GVMBackgroundNewClient(googlePID,clientPID)) { attempts=0; nextLaunch=0; }
    googlePID=clientPID;
    if (!sessionActive) { sessionActive=YES; Record(@"selected source supervisor started"); }
    if (sourceSessionToken>=0) notify_set_state(sourceSessionToken,selected);
    if (locationSessionToken>=0) notify_set_state(locationSessionToken,GVMBackgroundPermissionState(now,YES));
    RefreshLocationUsage(permission,YES,now);
    pid_t pid=((pid_t (*)(id,SEL,id))objc_msgSend)(service,NSSelectorFromString(@"pidForApplication:"),providerID);
    if (heldPID && heldPID!=pid) { Release(); nextAssertion=0; }
    if (pid>0) {
        managedPID=pid; attempts=0; nextLaunch=0;
        // Acquiring a background-active assertion resumes a suspended process as well.
        if (!assertion && now>=nextAssertion) { nextAssertion=now+30; Acquire(pid); }
        return;
    }
    managedPID=0;
    if (GVMBackgroundMayLaunch(now,nextLaunch,attempts)) {
        attempts++; nextLaunch=now+GVMBackgroundRetryDelay(attempts); Launch();
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
        Class statusClass=NSClassFromString(@"CARSessionStatus");
        if (Matches(statusClass,@"new","@",@[])) carplayStatus=[statusClass new];
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
