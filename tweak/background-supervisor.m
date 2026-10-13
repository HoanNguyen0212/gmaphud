#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "background-policy.h"
#import "source-transport.h"
#include <notify.h>
#include <string.h>

static int heartbeatToken = -1, phoneToken=-1, permissionToken = -1, locationSessionToken=-1;
static id assertion;
static id locationUsageContext;
static pid_t heldPID, googlePID;
static unsigned attempts;
static double nextLaunch, nextAssertion;
static double nextUsageContext;
static BOOL sessionActive;
static NSInteger lastPermission = NSIntegerMin;
static BOOL lastEnabled;
static NSString *const providerID = @"vn.vietmap.live";
static const char *Base(const char *type);
static BOOL AutoWakeEnabled(void) {
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesAppSynchronize(domain);
    id value=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("autoWake"),domain));
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
static void Tick(void) {
    uint64_t heartbeat=0, phoneHeartbeat=0;
    double now=NSProcessInfo.processInfo.systemUptime;
    BOOL enabled=AutoWakeEnabled();
    NSInteger permission=ProviderLocationPermission();
    BOOL allowed=GVMBackgroundLocationAuthorized((int)permission) && [CLLocationManager locationServicesEnabled];
    if (permissionToken>=0) notify_set_state(permissionToken,GVMBackgroundPermissionState(now,allowed));
    if (enabled && !allowed) {
        CFPreferencesSetAppValue(CFSTR("autoWake"),kCFBooleanFalse,CFSTR("com.chou.gmaphud"));
        CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"));
        enabled=NO;
    }
    if (enabled!=lastEnabled || (enabled && permission!=lastPermission)) {
        Record([NSString stringWithFormat:@"automatic wake enabled=%d VietMap Always=%d permission=%ld",enabled,
            permission==kCLAuthorizationStatusAuthorizedAlways,(long)permission]);
        lastEnabled=enabled; lastPermission=permission;
    }
    if (!enabled || !allowed) {
        if (locationSessionToken>=0) notify_set_state(locationSessionToken,0);
        ReleaseLocationUsage();
        Release();
        sessionActive=NO; googlePID=0; attempts=0; nextLaunch=0; nextAssertion=0;
        return;
    }
    if (heartbeatToken>=0) notify_get_state(heartbeatToken,&heartbeat);
    if (phoneToken>=0) notify_get_state(phoneToken,&phoneHeartbeat);
    BOOL active=GVMSelectedSourceID()==GVMSourceVietMap && GVMBackgroundAnyHostActive(now,heartbeat,phoneHeartbeat);
    if (locationSessionToken>=0) notify_set_state(locationSessionToken,GVMBackgroundPermissionState(now,active));
    if (!active) {
        ReleaseLocationUsage();
        Release();
        if (sessionActive) Record(@"Google Maps no longer visible; supervisor released");
        sessionActive=NO; googlePID=0; attempts=0; nextLaunch=0; nextAssertion=0; return;
    }
    if (!sessionActive) {
        sessionActive=YES;
        Record([NSString stringWithFormat:@"Google Maps visible; supervisor started CarPlay=%d iPhone=%d",
            GVMBackgroundActive(now,heartbeat),GVMBackgroundActive(now,phoneHeartbeat)]);
    }
    id service=Shared(@"FBSSystemService",@"sharedService");
    if (!Matches(service,@"pidForApplication:","i",@[@"@"])) { ReleaseLocationUsage(); Release(); return; }
    pid_t clientPID=((pid_t (*)(id,SEL,id))objc_msgSend)(service,NSSelectorFromString(@"pidForApplication:"),@"com.google.Maps");
    if (GVMBackgroundNewClient(googlePID,clientPID)) {
        attempts=0; nextLaunch=0;
        Record(@"Google Maps restarted; background launch budget renewed");
    }
    if (clientPID<=0) { ReleaseLocationUsage(); Release(); return; }
    googlePID=clientPID;
    // Establish bundle-scoped usage before suspended launch, including completely cold starts.
    RefreshLocationUsage(permission,active,now);
    pid_t pid=((pid_t (*)(id,SEL,id))objc_msgSend)(service,NSSelectorFromString(@"pidForApplication:"),providerID);
    if (heldPID && heldPID!=pid) Release();
    if (pid>0) {
        if (!assertion && now>=nextAssertion) { nextAssertion=now+30; Acquire(pid); }
        return;
    }
    if (GVMBackgroundMayLaunch(now,nextLaunch,attempts)) {
        attempts++; nextLaunch=now+GVMBackgroundRetryDelay(attempts);
        Launch();
        if (attempts==3) Record(@"automatic launch budget exhausted for this Google Maps session");
    }
}
__attribute__((constructor)) static void Start(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices",RTLD_NOW);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (notify_register_check(GVM_BACKGROUND_SIGNAL,&heartbeatToken)!=NOTIFY_STATUS_OK) return;
        notify_register_check(GVM_BACKGROUND_PHONE_SIGNAL,&phoneToken);
        notify_register_check(GVM_BACKGROUND_PERMISSION,&permissionToken);
        notify_register_check(GVM_BACKGROUND_LOCATION_SESSION,&locationSessionToken);
        Tick();
        Record(@"supervisor 0.1.21 loaded; awaiting visible Google Maps on CarPlay or iPhone");
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
