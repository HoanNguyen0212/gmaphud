#import <UIKit/UIKit.h>
#import "carplay-style.h"
#import "speed-state.h"
#import "alert-state.h"
#include <notify.h>

static int speedToken=-1,limitToken=-1,firstAlertToken=-1,secondAlertToken=-1;
static __weak UIView *phoneHost;
static double lastRequest=-1;
static uint64_t NotifyState(int token) {
    uint64_t state=0;
    if (token>=0) notify_get_state(token,&state);
    return state;
}
static UIView *ForegroundHost(void) {
    UIApplication *app=UIApplication.sharedApplication;
    if (app.applicationState!=UIApplicationStateActive) return nil;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.screen==UIScreen.mainScreen && window.isKeyWindow && !window.hidden &&
                window.alpha>0.01 && window.windowLevel==UIWindowLevelNormal && window.rootViewController) {
                // Use the entire app window; navigation controllers can inset their root view.
                return window;
            }
        }
    }
    return nil;
}
static void UpdatePhone(void) {
    UIView *host=ForegroundHost();
    if (phoneHost!=host) { GVMRemovePhoneSpeedCard(phoneHost); phoneHost=host; }
    if (!host) return;
    double now=NSProcessInfo.processInfo.systemUptime;
    NSNumber *speed=GVMDecodeSample(NotifyState(speedToken),now,YES);
    NSNumber *limit=GVMDecodeSample(NotifyState(limitToken),now,NO);
    NSMutableArray *alerts=[NSMutableArray new];
    for (NSNumber *token in @[@(firstAlertToken),@(secondAlertToken)]) {
        NSDictionary *alert=GVMDecodeAlert(NotifyState(token.intValue),now);
        if (alert) [alerts addObject:alert];
    }
    if (GVMShouldRequestSource(now,lastRequest,YES,NO,!speed || !limit)) {
        lastRequest=now; notify_post(GVMSourceRequestName);
    }
    GVMUpdatePhoneSpeedCard(host,speed,limit,alerts,host.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark);
}
__attribute__((constructor)) static void StartPhone(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.Maps"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        notify_register_check(GVMSpeedStateName,&speedToken);
        notify_register_check(GVMLimitStateName,&limitToken);
        notify_register_check(GVMFirstAlertStateName,&firstAlertToken);
        notify_register_check(GVMSecondAlertStateName,&secondAlertToken);
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            GVMRemovePhoneSpeedCard(phoneHost); phoneHost=nil;
        }];
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *timer) { UpdatePhone(); }];
    });
}
