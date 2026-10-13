#import <Foundation/Foundation.h>
#import "test-state.h"
#import "speed-state.h"
#import "placement-state.h"
#import "alert-state.h"
#import "vietmap-alert-assets.h"
#include <notify.h>
#include <errno.h>
#include <stdlib.h>

static BOOL Number(const char *text, NSInteger *value) {
    char *end; errno = 0;
    long parsed = strtol(text, &end, 10);
    if (errno || end == text || *end) return NO;
    *value = parsed; return YES;
}
static NSDictionary *DisplayAlert(const char *text) {
    NSString *input=[NSString stringWithUTF8String:text];
    NSArray<NSString *> *parts=[input componentsSeparatedByString:@":"];
    NSString *name=@"traffic_camera.png", *distanceText=input;
    if (parts.count==2) {
        name=[parts[0] stringByAppendingString:@".png"];
        distanceText=parts[1];
    } else if (parts.count!=1) return nil;
    NSInteger distance;
    NSUInteger kind=GVMVietMapKindForAssetName(name);
    if (!kind || !Number(distanceText.UTF8String,&distance) || distance<0 || distance>10000) return nil;
    return @{@"provider":@(GVMVietMapProviderID),@"kind":@(kind),@"distance":@(distance)};
}
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc==4 && strcmp(argv[1],"position")==0) {
            NSString *full=[NSString stringWithUTF8String:argv[2]], *dashboard=[NSString stringWithUTF8String:argv[3]];
            if (![@[@"top-left",@"top-right",@"bottom-left",@"bottom-right"] containsObject:full] ||
                ![@[@"left",@"right"] containsObject:dashboard]) return 2;
            int token=-1;
            if (notify_register_check(GVMPlacementStateName,&token)!=NOTIFY_STATUS_OK) return 3;
            uint32_t result=notify_set_state(token,GVMEncodePlacement(full,dashboard));
            if (result==NOTIFY_STATUS_OK) notify_post(GVMPlacementStateName);
            notify_cancel(token);
            return result==NOTIFY_STATUS_OK ? 0 : 3;
        }
        BOOL photo=argc>1 && strcmp(argv[argc-1],"--photo")==0;
        if (photo) argc--;
        uint64_t state = 0;
        uint64_t firstAlert = 0, secondAlert = 0;
        NSInteger speed = 0, limit = 0, duration = 0;
        if (!(argc == 2 && strcmp(argv[1], "off") == 0)) {
            if ((argc != 4 && argc != 6) || !Number(argv[1], &speed) || !Number(argv[2], &limit) || !Number(argv[3], &duration) ||
                !(state = GVMEncodeTest(speed, limit, NSProcessInfo.processInfo.systemUptime, duration))) {
                fprintf(stderr, "Usage: gvm-test-speed SPEED_KMH LIMIT_KMH SECONDS [SIGN1:METERS SIGN2:METERS], [--photo], or off; position FULL DASHBOARD\n"); return 2;
            }
            if (argc == 6) {
                NSDictionary *first=DisplayAlert(argv[4]), *second=DisplayAlert(argv[5]);
                NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
                if (!first || !second || !(firstAlert=GVMEncodeAlert(first,now)) ||
                    !(secondAlert=GVMEncodeAlert(second,now))) {
                    fprintf(stderr, "Use VietMap sign asset names and distances 0..10000 m; bare numbers mean traffic_camera\n"); return 2;
                }
            }
        }
        int photoToken=-1;
        if (notify_register_check("com.chou.googlemaps.vietmap.test.photo",&photoToken)!=NOTIFY_STATUS_OK) return 3;
        uint32_t photoResult=notify_set_state(photoToken,photo ? state : 0);
        notify_cancel(photoToken);
        if (photoResult!=NOTIFY_STATUS_OK) return 3;
        int token, firstToken, secondToken;
        if (notify_register_check(GVMTestStateName, &token) != NOTIFY_STATUS_OK) return 3;
        if (notify_register_check(GVMTestFirstAlertStateName, &firstToken) != NOTIFY_STATUS_OK) {
            notify_cancel(token); return 3;
        }
        if (notify_register_check(GVMTestSecondAlertStateName, &secondToken) != NOTIFY_STATUS_OK) {
            notify_cancel(firstToken); notify_cancel(token); return 3;
        }
        uint32_t result = notify_set_state(firstToken,firstAlert);
        if (result == NOTIFY_STATUS_OK) result = notify_set_state(secondToken,secondAlert);
        if (result == NOTIFY_STATUS_OK) result = notify_set_state(token,state);
        if (result == NOTIFY_STATUS_OK) {
            notify_post(GVMTestFirstAlertStateName);
            notify_post(GVMTestSecondAlertStateName);
            notify_post(GVMTestStateName);
        }
        notify_cancel(secondToken); notify_cancel(firstToken); notify_cancel(token);
        
        // Also broadcast directly to phone live speed channels
        int speedTok = -1, limitTok = -1;
        if (notify_register_check(GVMSpeedStateName, &speedTok) == NOTIFY_STATUS_OK) {
            notify_set_state(speedTok, state ? GVMEncodeSample(@(speed), NSProcessInfo.processInfo.systemUptime) : 0);
            notify_post(GVMSpeedStateName);
            notify_cancel(speedTok);
        }
        if (notify_register_check(GVMLimitStateName, &limitTok) == NOTIFY_STATUS_OK) {
            notify_set_state(limitTok, state ? GVMEncodeSample(@(limit), NSProcessInfo.processInfo.systemUptime) : 0);
            notify_post(GVMLimitStateName);
            notify_cancel(limitTok);
        }
        
        if (result != NOTIFY_STATUS_OK) { fprintf(stderr, "Test publication refused\n"); return 3; }
        printf(state ? "TEST active on Google Maps (Phone & CarPlay); expires in %ld seconds\n" : "TEST off; live VietMap restored\n", (long)duration);
        return 0;
    }
}
