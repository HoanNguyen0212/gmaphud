#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>
#import "source-transport.h"
#import "background-policy.h"
#include <notify.h>
#include <string.h>

static __weak id dashboardWorkspace;
static id (*originalWorkspace)(id __attribute__((ns_consumed)),SEL,id) __attribute__((ns_returns_retained));
static id Workspace(id self __attribute__((ns_consumed)),SEL cmd,id owner) __attribute__((ns_returns_retained));
static id Workspace(id self __attribute__((ns_consumed)),SEL cmd,id owner) {
    id result=originalWorkspace(self,cmd,owner);
    Class dashboardOwner=NSClassFromString(@"DBDashboardWorkspaceOwner");
    if (dashboardOwner && [owner isKindOfClass:dashboardOwner]) dashboardWorkspace=result;
    return result;
}
static BOOL Matches(id object,NSString *name,const char *result,NSArray *arguments) {
    NSMethodSignature *signature=[object methodSignatureForSelector:NSSelectorFromString(name)];
    if (!signature || signature.numberOfArguments!=arguments.count+2 || strcmp(signature.methodReturnType,result)) return NO;
    for (NSUInteger index=0;index<arguments.count;index++)
        if (strcmp([signature getArgumentTypeAtIndex:index+2],[arguments[index] UTF8String])) return NO;
    return YES;
}
static NSString *BaseBundle(id state) {
    if (!Matches(state,@"baseEntity","@",@[])) return nil;
    id entity=((id (*)(id,SEL))objc_msgSend)(state,NSSelectorFromString(@"baseEntity"));
    NSString *selector=Matches(entity,@"applicationToProxy","@",@[]) ? @"applicationToProxy" : @"application";
    if (!Matches(entity,selector,"@",@[])) return nil;
    id app=((id (*)(id,SEL))objc_msgSend)(entity,NSSelectorFromString(selector));
    return Matches(app,@"bundleIdentifier","@",@[]) ?
        ((id (*)(id,SEL))objc_msgSend)(app,NSSelectorFromString(@"bundleIdentifier")) : nil;
}
static void Record(NSString *text) {
    NSString *line=[NSString stringWithFormat:@"%.3f %@\n",NSProcessInfo.processInfo.systemUptime,text];
    NSString *path=@"/var/mobile/Library/Logs/gmaphud-carplay-bootstrap.log";
    if ([[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] fileSize]>32768)
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    if (![NSFileManager.defaultManager fileExistsAtPath:path])
        [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];
    @try { [file seekToEndOfFile]; [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; }
    @finally { [file closeFile]; }
}
__attribute__((constructor)) static void StartCarPlayBootstrap(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.CarPlayApp"]) return;
    Class workspaceClass=NSClassFromString(@"DBWorkspace");
    Method init=class_getInstanceMethod(workspaceClass,@selector(initWithOwner:));
    if (!init || strcmp(method_getTypeEncoding(init),"@24@0:8@16")) return;
    MSHookMessageEx(workspaceClass,@selector(initWithOwner:),(IMP)Workspace,(IMP *)&originalWorkspace);
    dispatch_async(dispatch_get_main_queue(), ^{
        static int requestToken=-1, leaseToken=-1, sourceToken=-1;
        notify_register_check(GVM_BACKGROUND_LOCATION_SESSION,&leaseToken);
        notify_register_check(GVM_BACKGROUND_LOCATION_SOURCE,&sourceToken);
        notify_register_dispatch(GVM_BACKGROUND_BOOTSTRAP_CARPLAY,&requestToken,dispatch_get_main_queue(),^(__unused int token) {
            uint64_t state=0,lease=0,source=0;
            notify_get_state(requestToken,&state);
            if (leaseToken<0 || sourceToken<0) return;
            notify_get_state(leaseToken,&lease); notify_get_state(sourceToken,&source);
            double now=NSProcessInfo.processInfo.systemUptime,age=now-(double)(state>>3)/1000;
            if ((state&7)!=GVMSourceWaze || GVMSelectedSourceID()!=GVMSourceWaze || source!=GVMSourceWaze ||
                age<0 || age>=6 || !GVMBackgroundPermissionAllowed(now,lease)) return;
            id workspace=dashboardWorkspace;
            Class controller=NSClassFromString(@"DBApplicationController");
            Class requestClass=NSClassFromString(@"DBMutableWorkspaceStateChangeRequest");
            if (!workspace || !Matches(controller,@"sharedInstance","@",@[]) ||
                !Matches(workspace,@"requestStateChange:","v",@[@"@"])) {
                Record(@"native CarPlay workspace unavailable"); return;
            }
            id applications=((id (*)(id,SEL))objc_msgSend)(controller,NSSelectorFromString(@"sharedInstance"));
            id request=[requestClass new];
            id settings=[NSClassFromString(@"DBActivationSettings") new];
            if (!Matches(settings,@"setSuspended:","v",@[@"B"]) ||
                !Matches(applications,@"applicationWithBundleIdentifier:","@",@[@"@"]) ||
                !Matches(request,@"activateApplication:withSettings:","v",@[@"@",@"@"])) {
                Record(@"native suspended CarPlay activation ABI unavailable"); return;
            }
            ((void (*)(id,SEL,BOOL))objc_msgSend)(settings,NSSelectorFromString(@"setSuspended:"),NO);
            id app=((id (*)(id,SEL,id))objc_msgSend)(applications,NSSelectorFromString(@"applicationWithBundleIdentifier:"),@"com.waze.iphone");
            if (!app) return;
            id before=Matches(workspace,@"state","@",@[]) ? ((id (*)(id,SEL))objc_msgSend)(workspace,NSSelectorFromString(@"state")) : nil;
            NSString *previous=BaseBundle(before);
            @try {
                ((void (*)(id,SEL,id,id))objc_msgSend)(request,NSSelectorFromString(@"activateApplication:withSettings:"),app,settings);
                ((void (*)(id,SEL,id))objc_msgSend)(workspace,NSSelectorFromString(@"requestStateChange:"),request);
                Record(@"selected Waze native CarPlay activation requested");
                if ([previous isEqual:@"com.waze.iphone"]) return;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
                    if (GVMSelectedSourceID()!=GVMSourceWaze || dashboardWorkspace!=workspace) return;
                    id current=((id (*)(id,SEL))objc_msgSend)(workspace,NSSelectorFromString(@"state"));
                    NSString *active=BaseBundle(current);
                    if (![active isEqual:@"com.waze.iphone"]) return;
                    id restore=[requestClass new];
                    @try {
                        if (previous.length && ![previous isEqual:@"com.waze.iphone"]) {
                            id prior=((id (*)(id,SEL,id))objc_msgSend)(applications,NSSelectorFromString(@"applicationWithBundleIdentifier:"),previous);
                            if (!prior || !Matches(restore,@"activateApplication:","v",@[@"@"])) return;
                            ((void (*)(id,SEL,id))objc_msgSend)(restore,NSSelectorFromString(@"activateApplication:"),prior);
                        } else {
                            if (!Matches(restore,@"activateHomeScreen","v",@[])) return;
                            ((void (*)(id,SEL))objc_msgSend)(restore,NSSelectorFromString(@"activateHomeScreen"));
                        }
                        ((void (*)(id,SEL,id))objc_msgSend)(workspace,NSSelectorFromString(@"requestStateChange:"),restore);
                        Record(@"previous CarPlay display restored after source initialization");
                    } @catch(NSException *exception) {
                        Record([NSString stringWithFormat:@"CarPlay restore failed %@: %@",exception.name,exception.reason]);
                    }
                });
            } @catch(NSException *exception) {
                Record([NSString stringWithFormat:@"native CarPlay activation failed %@: %@",exception.name,exception.reason]);
            }
        });
        Record(@"native CarPlay bootstrap listener loaded");
    });
}
