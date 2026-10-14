#import "alert-state.h"
#import "vietmap-alert-assets.h"
#include <assert.h>
#include <math.h>
int main(int argc, const char **argv) { @autoreleasepool {
    NSDictionary *sample=@{@"provider":@1,@"kind":@2,@"distance":@200};
    uint64_t state=GVMEncodeAlert(sample,100);
    assert([GVMDecodeAlert(state,104.999) isEqual:sample]);
    assert(!GVMDecodeAlert(state,105)); assert(!GVMDecodeAlert(state,99));
    assert(GVMDecodeAlertWithin(state,105,300));
    assert(!GVMDecodeAlertWithin(state,400,300));
    assert(!GVMEncodeAlert(@{@"provider":@0,@"kind":@2},100));
    assert(!GVMEncodeAlert(@{@"provider":@1,@"kind":@2,@"distance":@10001},100));
    assert(!GVMDecodeAlert(0,100)); assert(!GVMDecodeAlert(state,NAN));
    assert(GVMVietMapAlertsFromPayload(@[]).count==0);
    NSData *unknown=[@"unknown-sign" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *raw=@{@"image":[unknown base64EncodedStringWithOptions:0],@"distance":NSNull.null,
        @"speedLimit":@60,@"latitude":@12.34,@"account":@"private-value"};
    NSDictionary *observation=GVMVietMapAlertObservation(@[raw],0);
    NSDictionary *observed=observation[@"items"][0];
    assert([observed[@"imageSHA256"] length]==64 && !observed[@"recognizedAsset"]);
    assert([observed[@"distanceState"] isEqual:@"null"] && !observed[@"distance"]);
    assert([observed[@"speedLimit"] isEqual:@60]);
    NSString *safe=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:observation options:0 error:nil] encoding:NSUTF8StringEncoding];
    assert(![safe containsString:@"private-value"] && ![safe containsString:@"latitude"] && ![safe containsString:@"image\""]);
    NSMutableArray *many=[NSMutableArray new];
    for (NSUInteger i=0;i<32;i++) [many addObject:raw];
    NSDictionary *bounded=GVMVietMapAlertObservation(many,2);
    assert([bounded[@"count"] unsignedIntegerValue]==32 && [bounded[@"items"] count]==8 && [bounded[@"truncated"] boolValue]);
    NSData *encoded=[NSJSONSerialization dataWithJSONObject:raw options:0 error:nil];
    NSString *json=[[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    assert([GVMVietMapAlertObservation(@[json],0)[@"items"][0][@"jsonString"] boolValue]);
    assert(![GVMVietMapAlertObservation(@"private-value",0)[@"array"] boolValue]);
    NSDictionary *overlay=GVMVietMapOverlayObservation(@[@{@"stickyAlerts":@[raw],@"latitude":@12.34,
        @"parkingInfo":@{@"account":@"private-value"}},@NO]);
    assert([overlay[@"fields"] count]==2);
    assert([overlay[@"fields"][@"stickyAlerts"][@"count"] isEqual:@1]);
    NSString *overlayJSON=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:overlay options:0 error:nil] encoding:NSUTF8StringEncoding];
    assert(![overlayJSON containsString:@"latitude"] && ![overlayJSON containsString:@"private-value"]);
    NSArray *nextLimit=GVMVietMapAlertsFromPayload(@[@{@"image":@"",@"speedLimit":@80,@"distance":@200}]);
    assert(nextLimit.count==1);
    assert(GVMVietMapOverlayStickyAlerts(@[@{},@NO])==nil);
    assert(GVMVietMapOverlayStickyAlerts(@[@{@"stickyAlerts":@[]},@NO]).count==0);
    assert(GVMVietMapOverlayStickyAlerts(@[@{@"stickyAlerts":NSNull.null},@NO]).count==0);
    assert(GVMVietMapOverlayStickyAlerts(@[@{@"stickyAlerts":@"invalid"},@NO])==nil);
    NSArray *overlaySigns=GVMVietMapOverlayStickyAlerts(@[@{@"stickyAlerts":@[@{@"speedLimit":@60,@"distance":NSNull.null}]},@NO]);
    assert(overlaySigns.count==1 && overlaySigns[0][@"distance"]==NSNull.null);
    NSArray *noDistance=GVMVietMapAlertsFromPayload(@[@{@"speedLimit":@60,@"distance":NSNull.null}]);
    assert(noDistance.count==1 && noDistance[0][@"distance"]==NSNull.null);
    assert(GVMVietMapAlertsFromPayload(@[@{@"speedLimit":@60,@"distance":@"invalid"}]).count==0);
    assert([nextLimit[0][@"kind"] isEqual:@(GVMVietMapKindForAssetName(@"speed_limit_80.png"))]);
    assert([nextLimit[0][@"distance"] isEqual:@200]);
    assert(GVMVietMapAlertsFromPayload(@[@{@"image":@"",@"speedLimit":@81,@"distance":@200}]).count==0);
    assert(GVMVietMapAlertsFromPayload(@[@{@"image":@"invalid",@"speedLimit":@80,@"distance":@200}]).count==0);
    if (argc>3) {
        NSData *camera=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSData *speed=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
        assert(camera && speed);
        NSUInteger cameraKind=GVMVietMapKindForAssetName(@"traffic_camera.png");
        NSUInteger speedKind=GVMVietMapKindForAssetName(@"speed_limit_60.png");
        assert(cameraKind && speedKind && cameraKind!=speedKind);
        assert(GVMVietMapKindForImageDigest(@"4d8213184ad18e2846098454a19f8aa928be279f37a2d2a38a0b2c8c6dc0622d")==cameraKind);
        assert(GVMVietMapKindForImageDigest(@"f2274ca1457d7bd91ca3af373b160d09edfdde143a313b305856112684a57c36")==speedKind);
        assert(!GVMVietMapKindForImageDigest(@"invalid"));
        assert([GVMVietMapAssetName(cameraKind) isEqual:@"traffic_camera.png"]);
        assert([GVMVietMapAssetName(speedKind) isEqual:@"speed_limit_60.png"]);
        NSArray *alerts=GVMVietMapAlertsFromPayload(@[
            @{@"image":@"",@"speedLimit":@80,@"distance":@400},
            @{@"image":@"",@"speedLimit":@60,@"distance":@200}
        ]);
        assert(alerts.count==2);
        assert([alerts[0][@"kind"] isEqual:@(speedKind)]);
        assert([alerts[0][@"distance"] isEqual:@200]);
        assert([alerts[1][@"distance"] isEqual:@400]);
        assert(!GVMVietMapKindForImage([@"unrecognized" dataUsingEncoding:NSUTF8StringEncoding]));
        NSString *assetDirectory=[NSString stringWithUTF8String:argv[3]];
        NSArray<NSString *> *names=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:assetDirectory error:nil];
        assert(names.count>=40);
        NSUInteger vietMapCount=0;
        for (NSString *name in names) {
            if (![name.pathExtension isEqualToString:@"png"]) continue;
            NSData *bytes=[NSData dataWithContentsOfFile:[assetDirectory stringByAppendingPathComponent:name]];
            assert(bytes.length>8);
            const unsigned char *png=bytes.bytes;
            assert(png[0]==0x89 && png[1]=='P' && png[2]=='N' && png[3]=='G');
            if (GVMVietMapKindForAssetName(name)>0) vietMapCount++;
            // Redesigned PNGs are display-only; they must not replace source digests.
            assert(GVMVietMapKindForImage(bytes)==0);
        }
        assert(vietMapCount==46);
    }
    puts("alert state and VietMap assets passed");
} return 0; }
