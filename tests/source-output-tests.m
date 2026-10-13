#import "source-output.h"
#import "vietmap-output.h"
#import "vietmap-alert-assets.h"
#import "nav-source.h"
#import "alert-state.h"
#include <math.h>

static void Require(BOOL condition, NSString *name) {
    if (!condition) { fprintf(stderr,"FAIL: %s\n",name.UTF8String); exit(1); }
}
static NSDictionary *Sample(id value,double time) { return @{@"value":value,@"receivedAt":@(time)}; }
static NSDictionary *Alert(NSUInteger type,id value,id distance,double time) {
    return @{@"type":@(type),@"value":value ?: NSNull.null,@"distance":distance ?: NSNull.null,@"receivedAt":@(time)};
}
int main(void) { @autoreleasepool {
    NSDictionary *samples=@{@"speed":Sample(@0,100),@"speedLimit":Sample(@50,102)};
    NSDictionary *output=GVMSourceOutput(1,samples,@[Alert(GVMRoadAlertSpeedLimit,@80,@200,101),Alert(GVMRoadAlertTrafficCamera,nil,@400,102)],103);
    GVMOutputWords words;
    Require(GVMEncodeSourceOutput(output,103,&words),@"common envelope encodes");
    Require([GVMDecodeSourceOutput(1,words,103) isEqual:output],@"all canonical fields round trip");
    NSDictionary *expired=GVMDecodeSourceOutput(1,words,105);
    Require(!expired[@"speed"] && [expired[@"speedLimit"][@"value"] isEqual:@50] && [expired[@"alerts"] count]==2,@"each field retains its own age");
    Require([GVMDecodeSourceOutput(1,words,106)[@"alerts"] count]==1,@"alerts expire independently");
    Require([GVMDecodeSourceOutput(1,words,107)[@"alerts"] count]==0,@"five second expiry");
    Require(!GVMDecodeSourceOutput(1,words,99)[@"speedLimit"],@"future values unavailable");
    Require(!GVMSourceOutput(0,samples,@[],103) && !GVMSourceOutput(8,samples,@[],103),@"source range enforced");
    Require(!GVMSourceOutput(1,(id)@[],@[],103),@"malformed sample container rejected");
    for (id value in @[@YES,@(-1),@401,@1.5,@(NAN),@(INFINITY),@"50",NSNull.null]) {
        Require(!GVMSourceOutput(1,@{@"speed":Sample(value,100)},@[],101)[@"speed"],@"invalid speed omitted");
    }
    Require(!GVMSourceOutput(1,@{@"speedLimit":Sample(@0,100)},@[],100)[@"speedLimit"],@"zero limit means unavailable");
    Require(GVMSourceOutput(1,@{@"speed":Sample(@400,100)},@[],100)[@"speed"],@"maximum speed accepted");
    Require(!GVMSourceOutput(1,nil,@[],NAN),@"invalid clock rejects envelope");
    NSMutableDictionary *bad=[output mutableCopy];
    for (id version in @[@2,@YES,@"1",NSNull.null]) {
        bad[@"schemaVersion"]=version;
        Require(!GVMNormalizeSourceOutput(bad,103),@"unknown/malformed schema rejected");
    }
    bad=[output mutableCopy]; bad[@"sourceID"]=@YES;
    Require(!GVMNormalizeSourceOutput(bad,103),@"boolean source rejected");
    bad=[output mutableCopy]; bad[@"alerts"]=NSNull.null;
    Require(!GVMNormalizeSourceOutput(bad,103),@"alert container required");
    NSMutableArray *large=[NSMutableArray new];
    for (NSUInteger i=0;i<65;i++) [large addObject:Alert(1,nil,@1,100)];
    Require(!GVMSourceOutput(1,nil,large,100),@"bounded input");
    for (id time in @[@YES,@(NAN),@(-1),@101,@95,@"100"]) {
        Require(!GVMSourceOutput(1,@{@"speed":@{@"value":@42,@"receivedAt":time}},@[],100)[@"speed"],@"invalid or expired sample time omitted");
    }
    for (id distance in @[@YES,@(-1),@10001,@1.5,@"200"]) {
        Require([GVMSourceOutput(1,nil,@[Alert(1,nil,distance,100)],100)[@"alerts"] count]==0,@"invalid distance omitted");
    }
    for (id value in @[@0,@401,@YES,@1.5,NSNull.null]) {
        Require([GVMSourceOutput(1,nil,@[Alert(4,value,@200,100)],100)[@"alerts"] count]==0,@"invalid upcoming limit omitted");
    }
    Require([GVMSourceOutput(1,nil,@[Alert(1,@80,@200,100)],100)[@"alerts"] count]==0,@"value only allowed for speed-limit alert");
    for (NSUInteger value=1;value<=400;value++) {
        NSDictionary *arbitrary=GVMSourceOutput(1,nil,@[Alert(4,@(value),nil,100)],100);
        Require(GVMEncodeSourceOutput(arbitrary,100,&words),@"upcoming limit independent of artwork");
        Require([GVMDecodeSourceOutput(1,words,100)[@"alerts"][0][@"value"] isEqual:@(value)],@"all integer upcoming limits survive transport");
    }
    NSDictionary *ordered=GVMSourceOutput(1,nil,@[Alert(1,nil,nil,100),Alert(4,@80,@400,100),Alert(30,nil,@200,100),Alert(30,nil,@200,101)],102);
    NSArray *alerts=ordered[@"alerts"];
    Require(alerts.count==2 && [alerts[0][@"type"] isEqual:@30] && [alerts[0][@"receivedAt"] isEqual:@101] && [alerts[1][@"value"] isEqual:@80],@"nearest two semantic alerts, duplicates prefer latest");
    NSMutableDictionary *raw=[output mutableCopy]; raw[@"coordinates"]=@[@1,@2];
    raw[@"speed"]=@{@"value":@42,@"receivedAt":@100,@"raw":@"private"};
    NSDictionary *clean=GVMNormalizeSourceOutput(raw,103);
    Require(!clean[@"coordinates"] && !clean[@"speed"][@"raw"],@"adapter extras do not leave boundary");

    for (NSUInteger kind=1;kind<=46;kind++) {
        NSDictionary *legacy=@{@"provider":@1,@"kind":@(kind),@"distance":@200};
        NSDictionary *mapped=GVMVietMapOutputAlert(legacy,100);
        Require(mapped && GVMRoadAlertName([mapped[@"type"] unsignedIntegerValue]),@"every VietMap asset maps to a semantic type");
        NSDictionary *canonical=GVMVietMapOutput(nil,@[@{@"sample":legacy,@"receivedAt":@100}],100);
        Require([canonical[@"alerts"] count]==1 && [canonical[@"alerts"][0][@"artworkID"] isEqual:@(kind)],@"VietMap decoration survives adapter");
    }
    NSUInteger camera=GVMVietMapKindForAssetName(@"speed_limit_camera.png"), next=GVMVietMapKindForAssetName(@"speed_limit_80.png");
    Require([GVMVietMapOutputAlert(@{@"provider":@1,@"kind":@(camera)},100)[@"type"] isEqual:@(GVMRoadAlertSpeedCamera)],@"speed camera distinct from speed limit");
    Require([GVMVietMapOutputAlert(@{@"provider":@1,@"kind":@(next)},100)[@"value"] isEqual:@80],@"next limit has semantic numeric value");
    Require(!GVMVietMapOutputAlert(@{@"provider":@2,@"kind":@(next)},100),@"adapter rejects foreign source");
    Require(!GVMVietMapOutputAlert(@{@"provider":@1,@"kind":@YES},100),@"adapter rejects boolean kind");
    Require(!GVMVietMapOutputAlert(@{@"provider":@1,@"kind":@(NAN)},100),@"adapter rejects nonfinite kind");
    Require([GVMVietMapOutput(nil,@[@{@"sample":@{@"provider":@1,@"kind":@(next)},@"receivedAt":@YES}],1)[@"alerts"] count]==0,@"adapter does not coerce boolean timestamp");
    Require([GVMVietMapOutput(nil,(id)@[NSNull.null],100)[@"alerts"] count]==0,@"malformed alert entry ignored");
    VMNavSource *vm=[VMNavSource new];
    [vm applyArguments:@[@{@"speed":@42},@NO] receivedAt:100];
    [vm applyMainSpeedLimit:@50 receivedAt:101];
    NSDictionary *migrated=GVMVietMapOutput([vm freshSamplesAtUptime:102],@[@{@"sample":@{@"provider":@1,@"kind":@(next),@"distance":@212},@"receivedAt":@101}],102);
    Require(GVMEncodeSourceOutput(migrated,102,&words),@"real VietMap source methods migrate through envelope");
    NSDictionary *decoded=GVMDecodeSourceOutput(1,words,102);
    Require([decoded[@"speed"][@"value"] isEqual:@42] && [decoded[@"speedLimit"][@"value"] isEqual:@50] && [decoded[@"alerts"][0][@"value"] isEqual:@80],@"actual source speeds and alerts delivered together");
    [vm applyMainSpeedLimit:@0 receivedAt:103];
    Require(!GVMVietMapOutput([vm freshSamplesAtUptime:103],@[],103)[@"speedLimit"],@"explicit limit invalidation preserved");
    Require([GVMVietMapOutput(nil,@[],103)[@"alerts"] count]==0,@"empty alert list clears");

    words.words[2]=GVMEncodeAlert(@{@"provider":@2,@"kind":@30,@"distance":@200},100); words.words[3]=0; words.words[4]=0;
    Require([GVMDecodeSourceOutput(1,words,100)[@"alerts"] count]==0,@"foreign source alert rejected by codec");
    words.words[2]=GVMEncodeAlert(@{@"provider":@1,@"kind":@4,@"distance":@200},100); words.words[3]=(1ULL<<17)|512|80;
    Require([GVMDecodeSourceOutput(1,words,100)[@"alerts"] count]==0,@"invalid parameter bits rejected");
    Require(GVMOutputFrameReadable(513,513,9,9,9,1),@"committed selected frame accepted");
    Require(!GVMOutputFrameReadable(257,257,9,9,9,1),@"odd write rejected");
    Require(!GVMOutputFrameReadable(513,1025,9,9,9,1),@"interleaved writer rejected");
    Require(!GVMOutputFrameReadable(513,513,9,17,9,1),@"selection changed during read rejected");
    Require(!GVMOutputFrameReadable(513,513,17,17,9,1),@"pre-switch frame rejected");
    Require(!GVMOutputFrameReadable(514,514,9,9,9,1),@"future wire schema rejected");
    Require(!GVMOutputFrameReadable(513,513,10,10,10,1),@"source mismatch rejected");
    Require(!GVMOutputFrameReadable(1,1,9,9,9,1),@"uncommitted frame rejected");
    puts("source-output tests passed");
} return 0; }
