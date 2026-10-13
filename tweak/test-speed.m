#import <Foundation/Foundation.h>
#import "test-state.h"
#import "speed-state.h"
#import "placement-state.h"
#import "alert-state.h"
#import "tpms-state.h"
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
        if (argc >= 6 && strcmp(argv[1], "tpms") == 0) {
            float fl = (float)atof(argv[2]);
            float fr = (float)atof(argv[3]);
            float rl = (float)atof(argv[4]);
            float rr = (float)atof(argv[5]);
            GVMTPMSData tpmsData = {0};
            tpmsData.fl.pressure = fl; tpmsData.fl.active = fl > 0;
            tpmsData.fr.pressure = fr; tpmsData.fr.active = fr > 0;
            tpmsData.rl.pressure = rl; tpmsData.rl.active = rl > 0;
            tpmsData.rr.pressure = rr; tpmsData.rr.active = rr > 0;
            if (fl < 1.8f && fl > 0.1f) tpmsData.fl.warning = 1; else if (fl > 2.8f) tpmsData.fl.warning = 2;
            if (fr < 1.8f && fr > 0.1f) tpmsData.fr.warning = 1; else if (fr > 2.8f) tpmsData.fr.warning = 2;
            if (rl < 1.8f && rl > 0.1f) tpmsData.rl.warning = 1; else if (rl > 2.8f) tpmsData.rl.warning = 2;
            if (rr < 1.8f && rr > 0.1f) tpmsData.rr.warning = 1; else if (rr > 2.8f) tpmsData.rr.warning = 2;
            tpmsData.hasData = (tpmsData.fl.active || tpmsData.fr.active || tpmsData.rl.active || tpmsData.rr.active);
            
            NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
            uint64_t encoded = GVMEncodeTPMS(&tpmsData, now);
            int tpmsTok = -1;
            if (notify_register_check(GVMTPMSStateName, &tpmsTok) == NOTIFY_STATUS_OK) {
                notify_set_state(tpmsTok, encoded);
                notify_post(GVMTPMSStateName);
                notify_cancel(tpmsTok);
                printf("TPMS test published: FL=%.1f FR=%.1f RL=%.1f RR=%.1f\n", fl, fr, rl, rr);
                return 0;
            }
            return 3;
        }
        BOOL includeTpms = argc > 1 && strcmp(argv[argc-1], "--tpms") == 0;
        if (includeTpms) argc--;
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
        
        if (includeTpms || !state) {
            int tpmsTok = -1;
            if (notify_register_check(GVMTPMSStateName, &tpmsTok) == NOTIFY_STATUS_OK) {
                if (state) {
                    GVMTPMSData tpmsData = {0};
                    tpmsData.fl.pressure = 2.3f; tpmsData.fl.active = YES;
                    tpmsData.fr.pressure = 2.3f; tpmsData.fr.active = YES;
                    tpmsData.rl.pressure = 2.2f; tpmsData.rl.active = YES;
                    tpmsData.rr.pressure = 2.2f; tpmsData.rr.active = YES;
                    tpmsData.hasData = YES;
                    uint64_t encoded = GVMEncodeTPMS(&tpmsData, NSProcessInfo.processInfo.systemUptime);
                    notify_set_state(tpmsTok, encoded);
                } else {
                    notify_set_state(tpmsTok, 0);
                }
                notify_post(GVMTPMSStateName);
                notify_cancel(tpmsTok);
            }
        }
        
        if (result != NOTIFY_STATUS_OK) { fprintf(stderr, "Test publication refused\n"); return 3; }
        printf(state ? "TEST active on Google Maps (Phone & CarPlay); expires in %ld seconds\n" : "TEST off; live VietMap restored\n", (long)duration);
        return 0;
    }
}
