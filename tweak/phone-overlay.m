#import <UIKit/UIKit.h>
#import "carplay-style.h"
#import "speed-state.h"
#import "alert-state.h"
#import "test-state.h"
#import "tpms-state.h"
#include <notify.h>

static int speedToken = -1, limitToken = -1, firstAlertToken = -1, secondAlertToken = -1, tpmsToken = -1;
static int testToken = -1, testFirstAlertToken = -1, testSecondAlertToken = -1;
static __weak UIView *phoneHost;
static double lastRequest = -1;

static uint64_t NotifyState(int token) {
    uint64_t state = 0;
    if (token >= 0) notify_get_state(token, &state);
    return state;
}

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

static void UpdatePhone(void) {
    UIView *host = ForegroundHost();
    if (phoneHost != host) { GVMRemovePhoneSpeedCard(phoneHost); phoneHost = host; }
    if (!host) return;
    
    double now = NSProcessInfo.processInfo.systemUptime;
    NSNumber *speed = GVMDecodeSample(NotifyState(speedToken), now, YES);
    NSNumber *limit = GVMDecodeSample(NotifyState(limitToken), now, NO);
    
    NSMutableArray *alerts = [NSMutableArray new];
    for (NSNumber *token in @[@(firstAlertToken), @(secondAlertToken)]) {
        NSDictionary *alert = GVMDecodeAlert(NotifyState(token.intValue), now);
        if (alert) [alerts addObject:alert];
    }
    
    // Test mode fallback
    NSDictionary *test = testToken >= 0 ? GVMDecodeTest(NotifyState(testToken), now) : nil;
    if (test) {
        speed = test[@"speed"];
        limit = test[@"limit"];
        NSDictionary *t1 = testFirstAlertToken >= 0 ? GVMDecodeAlert(NotifyState(testFirstAlertToken), now) : nil;
        NSDictionary *t2 = testSecondAlertToken >= 0 ? GVMDecodeAlert(NotifyState(testSecondAlertToken), now) : nil;
        if (t1) [alerts addObject:t1];
        if (t2) [alerts addObject:t2];
    }
    
    GVMTPMSData tpms = GVMDecodeTPMS(NotifyState(tpmsToken), now);
    
    if (GVMShouldRequestSource(now, lastRequest, YES, test != nil, !speed || !limit)) {
        lastRequest = now;
        notify_post(GVMSourceRequestName);
    }
    
    static double lastLog = 0;
    if (now - lastLog > 5.0) {
        lastLog = now;
        NSString *line = [NSString stringWithFormat:@"%f phone host=%@ speed=%@ limit=%@ alerts=%lu tpms=%d\n",
            now, NSStringFromClass(host.class), speed, limit, (unsigned long)alerts.count, tpms.hasData];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:@"/var/mobile/Library/Logs/gmaphud-phone.log"];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        } else {
            [line writeToFile:@"/var/mobile/Library/Logs/gmaphud-phone.log" atomically:NO encoding:NSUTF8StringEncoding error:nil];
        }
    }
    
    GVMUpdatePhoneSpeedCard(host, speed, limit, alerts, &tpms, host.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
}

__attribute__((constructor)) static void StartPhone(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.Maps"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        notify_register_check(GVMSpeedStateName, &speedToken);
        notify_register_check(GVMLimitStateName, &limitToken);
        notify_register_check(GVMFirstAlertStateName, &firstAlertToken);
        notify_register_check(GVMSecondAlertStateName, &secondAlertToken);
        notify_register_check(GVMTPMSStateName, &tpmsToken);
        notify_register_check(GVMTestStateName, &testToken);
        notify_register_check(GVMTestFirstAlertStateName, &testFirstAlertToken);
        notify_register_check(GVMTestSecondAlertStateName, &testSecondAlertToken);
        
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            GVMRemovePhoneSpeedCard(phoneHost);
            phoneHost = nil;
        }];
        
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *timer) {
            UpdatePhone();
        }];
    });
}
