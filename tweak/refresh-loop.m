#import "refresh-loop.h"

__attribute__((constructor)) static void StartRefreshLoop(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.Maps"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Share the original cadence; expiry and reconnect checks still run
        // even when the source has not posted a new notification.
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *timer) {
            GVMRefreshCarPlayViews();
            GVMRefreshPhoneOverlay();
        }];
    });
}
