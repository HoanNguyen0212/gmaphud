#import <Foundation/Foundation.h>
#import "waze-output.h"
#include <math.h>
static void Require(BOOL ok,NSString *message) { if (!ok) { NSLog(@"FAIL %@",message); exit(1); } }
static void Camera(GVMWazeOutputStore *s,NSString *key,NSInteger meters,BOOL valid,BOOL passed,double time) {
    [s updateIdentifier:key icon:@"icon_alerter_cam_red_light" type:10 subtype:1 trait:0
        distance:meters valid:valid passed:passed atUptime:time];
}
int main(void) { @autoreleasepool {
    GVMWazeOutputStore *store=[GVMWazeOutputStore new];
    Camera(store,@"A",500,YES,NO,100); Camera(store,@"B",300,YES,NO,101);
    NSDictionary *output=[store outputAtUptime:101];
    Require([output[@"sourceID"] isEqual:@2],@"Waze owns its envelope");
    Require([output[@"alerts"] count]==2 && [output[@"alerts"][0][@"distance"] isEqual:@300],@"nearest two cameras");
    Require([output[@"alerts"][0][@"type"] isEqual:@(GVMRoadAlertRedLightCamera)],@"red light is not AI camera");
    Camera(store,@"B",0,NO,YES,102);
    Require([[store outputAtUptime:102][@"alerts"] count]==1,@"pass clears only its identity");
    Camera(store,@"A",200,YES,NO,99);
    Require([[store outputAtUptime:104][@"alerts"][0][@"distance"] isEqual:@500],@"late callback cannot replace newer sample");
    Require([[store outputAtUptime:105][@"alerts"] count]==0,@"polling does not renew TTL");
    Camera(store,@"A",601,YES,NO,106);
    Require([[store outputAtUptime:106][@"alerts"] count]==1,@"valid native descriptor is available before UI trigger distance");
    Camera(store,@"A",-1,NO,YES,106);
    [store updateIdentifier:@"U" icon:@"icon_alerter_cam_speed" type:10 subtype:1 trait:0 distance:10 valid:YES passed:NO atUptime:106];
    [store updateIdentifier:@"V" icon:@"icon_alerter_cam_red_light" type:10 subtype:2 trait:0 distance:10 valid:YES passed:NO atUptime:106];
        Require([[store outputAtUptime:106][@"alerts"] count]==1 &&
        [[store outputAtUptime:106][@"alerts"][0][@"type"] isEqual:@(GVMRoadAlertSpeedCamera)],@"exact speed camera artwork maps in internal trial; unmeasured red-light tuple rejected");
    [store updateIdentifier:@"U" icon:@"icon_alerter_cam_speed" type:10 subtype:1 trait:0 distance:0 valid:NO passed:YES atUptime:107];
    [store updateIdentifier:@"X" icon:@"unknown_camera_speed" type:10 subtype:1 trait:0 distance:100 valid:YES passed:NO atUptime:107];
    Require([[store outputAtUptime:107][@"alerts"] count]==0,@"unknown icon does not guess camera semantics");
    GVMWazeOutputStore *trial=[GVMWazeOutputStore new];
    [trial updateIdentifier:@"phone" icon:@"icon_alerter_cam_phone" type:10 subtype:5 trait:0 distance:350 valid:YES passed:NO atUptime:100];
    [trial updateIdentifier:@"pothole" icon:@"icon_report_hazard_pothole" type:1 subtype:2 trait:0 distance:50 valid:YES passed:NO atUptime:100];
    NSDictionary *trialOutput=[trial outputAtUptime:100];
    Require([trialOutput[@"alerts"] count]==2 && [GVMRoadAlertName([trialOutput[@"alerts"][0][@"type"] unsignedIntegerValue]) isEqual:@"hazard-pothole"],@"exact hazard artwork keeps semantic and distance");
    Require([[trial outputAtUptime:105][@"alerts"] count]==0,@"experimental icons cannot keep stale warnings alive");
    [trial updateIdentifier:@"hidden" icon:@"icon_alerter_cam_phone_hidden" type:10 subtype:5 trait:0 distance:50 valid:YES passed:NO atUptime:106];
    Require([[trial outputAtUptime:106][@"alerts"] count]==0,@"hidden variant is not assumed to be an active warning");
    [store updateSpeed:10000 timestamp:1000 now:1001 uptime:200 optionalLimit:((uint64_t)1<<32)|60];
    output=[store outputAtUptime:200];
    Require([output[@"speed"][@"value"] isEqual:@36] && [output[@"speedLimit"][@"value"] isEqual:@60],@"native units and optional limit");
    [store updateSpeed:20000 timestamp:1000 now:1003 uptime:202 optionalLimit:0];
    Require([[store outputAtUptime:202][@"speed"][@"value"] isEqual:@36],@"duplicate GPS does not refresh");
    Camera(store,@"C",100,YES,NO,203);
    output=[store outputAtUptime:204];
    Require(!output[@"speed"] && !output[@"speedLimit"] && [output[@"alerts"] count]==1,@"fields expire independently");
    [store updateSpeed:0 timestamp:1005 now:1005 uptime:204 optionalLimit:0];
    output=[store outputAtUptime:204];
    Require([output[@"speed"][@"value"] isEqual:@0] && !output[@"speedLimit"],@"zero speed and absent limit are distinct");
    [store updateSpeed:999 timestamp:1010 now:1006 uptime:205 optionalLimit:0];
    Require([[store outputAtUptime:205][@"speed"][@"value"] isEqual:@0],@"future GPS rejected");
    GVMOutputWords words;
    Require(GVMEncodeSourceOutput(output,204,&words),@"Waze encodes into shared wire");
    NSDictionary *decoded=GVMDecodeSourceOutput(2,words,204);
    Require([decoded[@"alerts"][0][@"type"] isEqual:@34],@"red light survives wire round trip");
    Require([GVMSourceDisplayName(2) isEqual:@"Waze"],@"source identity");
    puts("waze-output tests passed");
} return 0; }
