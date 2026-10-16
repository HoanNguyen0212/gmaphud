#import <UIKit/UIKit.h>
#import "guidance-state.h"
#include <notify.h>

// Runs in CarPlayTemplateUIHost, which draws CarPlay's navigation guidance for Google Maps. Twice a
// second it reads where the maneuver card and the arrival estimates are and publishes that column,
// so the New UI bubble can put signs in effect and lanes in the free space between them. It only
// reads views; nothing on screen changes. Classes measured on iOS 18.6: CPSManeuversCardView holds
// CPSCardPlatterView cards; CPSNavigationETAView holds the estimates.
static Class cardClass, platterClass, etaClass;
static int token=-1;
static uint64_t lastColumn;

static BOOL Shown(UIView *view) {
    if (!view.window) return NO;
    for (UIView *v=view; v; v=v.superview) if (v.hidden || v.alpha<=0.01) return NO;
    return YES;
}
static void Collect(UIView *view, UIView **card, UIView **eta) {
    if (!*card && [view isKindOfClass:cardClass] && Shown(view)) *card=view;
    if (!*eta && [view isKindOfClass:etaClass] && Shown(view)) *eta=view;
    for (UIView *child in view.subviews) {
        if (*card && *eta) return;
        Collect(child,card,eta);
    }
}
static double CardBottom(UIView *view, UIView *window, double bottom) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:platterClass]) {
            if (Shown(child) && child.bounds.size.height>0)
                bottom=MAX(bottom,CGRectGetMaxY([child convertRect:child.bounds toView:window]));
        } else bottom=CardBottom(child,window,bottom);
    }
    return bottom;
}
static uint64_t Measure(NSTimeInterval now) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || !window.screen) continue;
            UIView *card=nil, *eta=nil;
            Collect(window,&card,&eta);
            if (!card) continue;
            double bottom=CardBottom(card,window,-1);
            if (bottom<0) continue;
            CGRect column=[card convertRect:card.bounds toView:window];
            double etaTop=eta ? CGRectGetMinY([eta convertRect:eta.bounds toView:window]) : CGRectGetMaxY(column);
            // Report in CarPlay screen points, the space the Google Maps window shares.
            CGRect onScreen=[window convertRect:column toCoordinateSpace:window.screen.coordinateSpace];
            double dy=onScreen.origin.y-column.origin.y;
            return GVMEncodeGuidance((GVMGuidanceColumn){onScreen.origin.x,onScreen.size.width,bottom+dy,MAX(bottom,etaTop)+dy},now);
        }
    }
    return 0;
}
static void Tick(void) {
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    uint64_t state=0;
    @try { state=Measure(now); } @catch (__unused NSException *e) { state=0; }
    if (token<0 && notify_register_check(GVMGuidanceStateName,&token)!=NOTIFY_STATUS_OK) return;
    notify_set_state(token,state);
    // Readers lay out again only when the column itself moves, appears or goes.
    uint64_t column=state&((1ULL<<48)-1);
    if (column!=lastColumn) { lastColumn=column; notify_post(GVMGuidanceStateName); }
}
__attribute__((constructor)) static void Start(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.CarPlayTemplateUIHost"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        cardClass=NSClassFromString(@"CPSManeuversCardView");
        platterClass=NSClassFromString(@"CPSCardPlatterView");
        etaClass=NSClassFromString(@"CPSNavigationETAView");
        if (!cardClass || !platterClass || !etaClass) return;
        static dispatch_source_t timer;
        timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
        dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),NSEC_PER_SEC/2,NSEC_PER_SEC/10);
        dispatch_source_set_event_handler(timer,^{ Tick(); });
        dispatch_resume(timer);
    });
}
