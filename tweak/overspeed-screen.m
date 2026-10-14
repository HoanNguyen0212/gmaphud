#include <math.h>
#import <UIKit/UIKit.h>
#import "placement-state.h"
#import "overspeed-frame.h"
#include <notify.h>
static NSMapTable<UIWindow *,GVMOverspeedFrame *> *frames;
static NSTimer *expiryTimer;
static int leaseToken=-1,modeToken=-1;
static void UpdateScreen(void) {
    uint64_t state=0; if (leaseToken>=0) notify_get_state(leaseToken,&state);
    BOOL active=GVMOverspeedMode()==2 && GVMOverspeedLeaseActive(state,NSProcessInfo.processInfo.systemUptime);
    for (UIWindow *window in frames.keyEnumerator) [frames objectForKey:window].hidden=YES;
    if (active) for (UIWindow *window in UIApplication.sharedApplication.windows) {
        CGRect screen=window.screen.bounds;
        if (window.hidden || window.alpha<=0.01 || window.windowScene.activationState!=UISceneActivationStateForegroundActive ||
            fabs(window.bounds.size.width-screen.size.width)>1 || fabs(window.bounds.size.height-screen.size.height)>1) continue;
        GVMOverspeedFrame *frame=[frames objectForKey:window];
        if (!frame) { frame=[[GVMOverspeedFrame alloc] initWithFrame:window.bounds]; [window.layer addSublayer:frame.layer]; [frames setObject:frame forKey:window]; }
        frame.wholeScreen=YES; frame.frame=window.bounds; [frame setWarningLevel:(NSUInteger)(state&3)]; [frame setNeedsLayout]; [frame layoutIfNeeded]; frame.layer.zPosition=10000;
    }
    for (GVMOverspeedFrame *frame in frames.objectEnumerator) if (frame.hidden) [frame setWarningActive:NO];
    if (active && !expiryTimer) {
        expiryTimer=[NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(__unused NSTimer *timer) { UpdateScreen(); }];
        [NSRunLoop.mainRunLoop addTimer:expiryTimer forMode:NSRunLoopCommonModes];
    }
    if (!active) { [expiryTimer invalidate]; expiryTimer=nil; }
}
__attribute__((constructor)) static void StartScreenBorder(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        frames=[NSMapTable weakToStrongObjectsMapTable];
        notify_register_dispatch(GVMOverspeedLeaseName,&leaseToken,dispatch_get_main_queue(),^(__unused int token) { UpdateScreen(); });
        notify_register_dispatch(GVMOverspeedModeName,&modeToken,dispatch_get_main_queue(),^(__unused int token) { UpdateScreen(); });
        UpdateScreen();
    });
}
