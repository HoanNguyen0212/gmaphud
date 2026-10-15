#import <Foundation/Foundation.h>
#import "placement-state.h"
#import "source-transport.h"
#include <notify.h>

static int placementToken = -1, sizeChangeToken=-1;
__attribute__((constructor)) static void GVMRestorePlacement(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        notify_register_dispatch(GVMSizeChangedName,&sizeChangeToken,dispatch_get_main_queue(),^(__unused int token) {
            GVMPublishSavedSizes();
        });
        GVMPublishSavedSizes();
        GVMRestoreOutputSelection();
        CFStringRef domain=CFSTR("com.chou.gmaphud");
        CFPreferencesAppSynchronize(domain);
        NSString *full=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("fullPosition"),domain));
        NSString *dashboard=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("dashboardPosition"),domain));
        if (notify_register_check(GVMPlacementStateName,&placementToken)==NOTIFY_STATUS_OK) {
            notify_set_state(placementToken,GVMEncodePlacement(full,dashboard));
            notify_post(GVMPlacementStateName);
        }
    });
}
