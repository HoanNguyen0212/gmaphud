#import <UIKit/UIKit.h>
#import "carplay-style.h"
#import "speed-state.h"
#import "alert-state.h"
#import "refresh-loop.h"
#import "background-policy.h"
#import "source-transport.h"
#include <notify.h>

static int backgroundToken=-1;
static __weak UIView *phoneHost;
static double lastRequest=-1;
static double lastHeartbeat=-1;
static UIView *ForegroundHost(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (app.applicationState != UIApplicationStateActive) return nil;
    
    // Primary lookup: UIWindowScene active foreground
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.screen == UIScreen.mainScreen && window.isKeyWindow && !window.hidden &&
                window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal && window.rootViewController) {
                return window;
            }
        }
    }
    
    // Fallback 1: Any visible root window in scenes (iOS 15.8 Dopamine on iPhone SE compatibility)
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.screen == UIScreen.mainScreen && !window.hidden &&
                window.alpha > 0.01 && window.rootViewController) {
                return window;
            }
        }
    }
    
    // Fallback 2: Classic UIApplication window lookup for legacy Google Maps on iOS 15
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *key = [app keyWindow];
    if (key && !key.hidden && key.alpha > 0.01 && key.rootViewController) return key;
#pragma clang diagnostic pop
    if (app.windows.count > 0) {
        for (UIWindow *w in app.windows) {
            if (w.screen == UIScreen.mainScreen && !w.hidden && w.alpha > 0.01 && w.rootViewController) {
                return w;
            }
        }
    }
    
    return nil;
}
void GVMRefreshPhoneOverlay(void) {
    UIView *host=ForegroundHost();
    if (phoneHost!=host) { GVMRemovePhoneSpeedCard(phoneHost); phoneHost=host; }
    if (!host) {
        // Let the heartbeat expire instead of clearing it, so a brief banner, Control Center
        // or app switch does not end the source session while the phone map is in use.
        lastHeartbeat=-1;
        return;
    }
    double now=NSProcessInfo.processInfo.systemUptime;
    if (backgroundToken>=0 && (lastHeartbeat<0 || now-lastHeartbeat>=3)) {
        notify_set_state(backgroundToken,(uint64_t)(now*1000)); lastHeartbeat=now;
    }
    NSDictionary *output=GVMReadSourceOutput(now);
    NSNumber *speed=output[@"speed"][@"value"], *limit=output[@"speedLimit"][@"value"];
    if (GVMShouldRequestSource(now,lastRequest,YES,NO,!speed || !limit)) {
        lastRequest=now; GVMRequestSelectedSource();
    }
    GVMUpdatePhoneSpeedCard(host,output,host.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark);
}

__attribute__((constructor)) static void StartPhone(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.Maps"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        notify_register_check(GVM_BACKGROUND_PHONE_SIGNAL,&backgroundToken);
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            GVMRemovePhoneSpeedCard(phoneHost); phoneHost=nil;
            lastHeartbeat=-1;
        }];
    });
}
