#import "vietmap-alert-assets.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

const NSUInteger GVMVietMapProviderID = 1;

typedef struct { __unsafe_unretained NSString *name; __unsafe_unretained NSString *hash; } GVMAsset;
// Image digests from the installed VietMap Live 3.4.3 assets_v2 alert catalog.
static const GVMAsset assets[] = {
    {@"camera_ai.png", @"d75fc52734bd3a9e0fd84e999059029afb31d70793085745cc556d89e53c8210"},
    {@"highway_rest_area.png", @"6587bc096221da7a5304fbb9e577dba78922c6d188eef71368ea97682434c5af"},
    {@"khu_dan_cu.png", @"72d5f5b15742c8b535545089b917923891b68f49f203be7dd8f0df8aa430ea67"},
    {@"leftAndRightTurnOnly.png", @"9d591383b87f4e403f8a9ab0ac5a049059340b2f9cdc09a3d3988a6e1f4709af"},
    {@"leftTurnOnly.png", @"89c4a57e1901ae644fda4c2e0eb6601eadadae1afe3bb81364867937b5a17d7c"},
    {@"limit_80.png", @"25f111c8713738ae0dd234c85dc7b6f821b3b8c3e9bfcfa8632306778c36de22"},
    {@"noEntry.png", @"53943d0ffd97967a73221792925c456d2f8e7ce5da8ed74817e0036d9474fa5b"},
    {@"noEntryNoLeftTurn.png", @"4c928a1ab9e4e5307e341f76dc651818be610e608865f664d589b7ee0ee9a8a4"},
    {@"noEntryNoRightTurn.png", @"fdf5c8213e9bf2d1bc214587909c43f4cf200600abe33055d8a92e767630cff6"},
    {@"noLeftTurn.png", @"1cd7236828b7a4a2cc35bbe916059ebc10c7d1e166bccef706d1ec4be072c11b"},
    {@"noLeftTurnNoRightTurn.png", @"777a5308d9e8a7a4864662dc8ece4fe8b002c79db79c4ece4dea7fb3677bd07f"},
    {@"noLeftTurnUTurn.png", @"2e5e9b963042215a63b37c9af7787ba8d128e0a1bd1addd11c79c027eb520ca1"},
    {@"noRightTurn.png", @"7d4044d9cfd55d0894ef9f3ce2ff63a6ec7f49e9ebcb2d39b5cdf90090baecbe"},
    {@"noRightTurnUTurn.png", @"3c628cf7496e5ac42f529ac137d3e3ed4e06710332af313021638dd1e6e54e32"},
    {@"noUTurnLeft.png", @"f149de54d9b681e4dbe34655f3eb03ce4962e5c644d7618e676bf967b2494081"},
    {@"noUTurnRight.png", @"ec4fa5f0007da088bc4d76ff5e3ad15ca82eaeb64870075678cab0547b7b98bd"},
    {@"no_passing_in.png", @"6c3044304a90e64211d88c3db7d4fb07196fe1872c144b653b4f3585037d17a7"},
    {@"no_passing_out.png", @"5717ad12362859329e857002c918ecc21af6a8109ae6dbab0218a12e480b1eaa"},
    {@"penalty_camera.png", @"168c525ec00ad0b1252b36a420626b9a66137d98ca4b1d12e3e1735af8f37c7a"},
    {@"railway.png", @"4762b4a16da439a9ed1e4f829f6ba70d16ffc19ee975e2be431aacf509ec7f39"},
    {@"residential_area_in.png", @"0fec070da08d3d4f669358aa633be973bc4b49cfbc959691ab5168b9335ac1c7"},
    {@"residential_area_out.png", @"2f89834dac89b5af40cdb513fd25674bf546efe647862e8bb91ae3410c7923b6"},
    {@"retrict_unknown.png", @"b48a0429089c09940b75488a6e1b176691a70db66daae8286ead58ba42417ec7"},
    {@"rightTurnOnly.png", @"427deaa09399e1a0fab59b23b58c3b3ead068c0f65d25bcc9455c9a436978706"},
    {@"slow_down.png", @"8609e357b3dfb667956a582aded214a339c55ee52b862ab4e330ca5e6ac54d04"},
    {@"speed_limit_10.png", @"61c371e6a87dadd8e2b86c6e614567a7861162cae62b38e2e3e2103164c6fbfd"},
    {@"speed_limit_100.png", @"c3d048676c4a69816d29df1a12cf37a94e6260ce66bbe237a3a0724e58cce8a7"},
    {@"speed_limit_110.png", @"a374edd38dfe58ecdc9b7ef42fad19240278871824aefdffb62095929f61a700"},
    {@"speed_limit_120.png", @"5be939de4194f845e57eab509627a340f90edc9a4d5fc793a86e05e351106438"},
    {@"speed_limit_20.png", @"04ce75b869c8fdd97e318080b4bf574a69e097c73f6ea22ae58d17106292dfa3"},
    {@"speed_limit_30.png", @"330a1350c081589491586aaa64272e61f6c33e8391d6b403066e4160abaeed0a"},
    {@"speed_limit_40.png", @"6af435a3b863d7b19d62c54f9d8d38084487c5a134c93762edb291d3336d17dd"},
    {@"speed_limit_50.png", @"019d945181fbb0768cf4dc250d6ed2bf4c0c6ee353d407786c1a7b91e36c64ce"},
    {@"speed_limit_60.png", @"f2274ca1457d7bd91ca3af373b160d09edfdde143a313b305856112684a57c36"},
    {@"speed_limit_70.png", @"34168786b95f276620df17446d4d5e40c7bba56069314e1dd68160753149bede"},
    {@"speed_limit_80.png", @"160464ba6f439d24dd14fb624a4f80519c9738e96d16a86ed1732a38cf994e06"},
    {@"speed_limit_90.png", @"584ec29a1fc7815b1d0414d8625619f50fefd7f16d08418b4efecd0e5eefc2de"},
    {@"speed_limit_camera.png", @"119ad482a3848018cb7391209cfa1f3671ae507ccec1b793ebe20f41b03146e3"},
    {@"stop_lane.png", @"b48e433b6ce07ae8df91aeac681bbcd53a7b21d1c35a70be7fdb21efad09141b"},
    {@"straightAheadOnly.png", @"5bdad8407dbbf93f6159369b9f17a832ca6233937b00eac99f55ea61a1f12081"},
    {@"straightAndLeftTurnOnly.png", @"c2efed87f0f6a29f3187e829f339675802d7693dd48acb754363fa821b80f9fa"},
    {@"straightAndRightTurnOnly.png", @"f91ab6df8ad3ab86f0a658232efd01bb4f5f38222b0d1ffcd8d355ba1595268e"},
    {@"toll.png", @"2f5c6f8f03807d604a1a055fb6e5586f0cb9ad0d369da7267043270659bdee3a"},
    {@"toll_etc.png", @"92fc4e04fc906e0f6f98d4b087046f5f8e4e72d2601951eefa8fd12b0100213f"},
    {@"traffic_camera.png", @"4d8213184ad18e2846098454a19f8aa928be279f37a2d2a38a0b2c8c6dc0622d"},
    {@"tunnel.png", @"66ba6d4ded8149a8039fe3c2169dc76390596f1cad28bdee83b7e38bfe321604"},
};

static NSString *ImageDigest(NSData *image) {
    if (!image.length || image.length>131072) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(image.bytes,(CC_LONG)image.length,digest);
    NSMutableString *hash=[NSMutableString stringWithCapacity:64];
    for (NSUInteger i=0;i<sizeof(digest);i++) [hash appendFormat:@"%02x",digest[i]];
    return hash;
}
NSUInteger GVMVietMapKindForImage(NSData *image) {
    return GVMVietMapKindForImageDigest(ImageDigest(image));
}
// Upstream recognition digests stay independent of replaceable display artwork.
NSUInteger GVMVietMapKindForImageDigest(NSString *hash) {
    if (![hash isKindOfClass:NSString.class] || hash.length!=64) return 0;
    for (NSUInteger i=0;i<sizeof(assets)/sizeof(assets[0]);i++)
        if ([hash isEqualToString:assets[i].hash]) return i+1;
    return 0;
}
NSString *GVMVietMapAssetName(NSUInteger kind) {
    return kind>=1 && kind<=sizeof(assets)/sizeof(assets[0]) ? assets[kind-1].name : nil;
}
NSUInteger GVMVietMapKindForAssetName(NSString *name) {
    for (NSUInteger i=0;i<sizeof(assets)/sizeof(assets[0]);i++)
        if ([name isEqualToString:assets[i].name]) return i+1;
    return 0;
}
static NSNumber *Distance(id value) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()) return nil;
    double d=[value doubleValue];
    return isfinite(d) && d>=0 && d<=10000 && floor(d)==d ? value : nil;
}
NSArray<NSDictionary *> *GVMVietMapAlertsFromPayload(id payload) {
    if (![payload isKindOfClass:NSArray.class] || [payload count]>32) return @[];
    NSMutableArray<NSDictionary *> *alerts=[NSMutableArray array];
    for (__strong id item in payload) {
        if ([item isKindOfClass:NSString.class] && [item length]<=262144)
            item=[NSJSONSerialization JSONObjectWithData:[item dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (![item isKindOfClass:NSDictionary.class]) continue;
        id encoded=item[@"image"];
        NSUInteger kind=0;
        if ([encoded isKindOfClass:NSString.class] && [encoded length]) {
            if ([encoded length]>180000) continue;
            NSData *image=[[NSData alloc] initWithBase64EncodedString:encoded options:0];
            kind=GVMVietMapKindForImage(image);
        } else if (!encoded || encoded==NSNull.null ||
                   ([encoded isKindOfClass:NSString.class] && ![encoded length])) {
            id speedLimit=item[@"speedLimit"];
            if ([speedLimit isKindOfClass:NSNumber.class] &&
                CFGetTypeID((__bridge CFTypeRef)speedLimit)!=CFBooleanGetTypeID()) {
                double value=[speedLimit doubleValue];
                if (isfinite(value) && value>=10 && value<=120 && floor(value)==value)
                    kind=GVMVietMapKindForAssetName([NSString stringWithFormat:@"speed_limit_%ld.png",(long)value]);
            }
        }
        if (!kind) continue;
        NSNumber *distance=Distance(item[@"distance"]);
        if (item[@"distance"] && item[@"distance"]!=NSNull.null && !distance) continue;
        [alerts addObject:@{@"provider":@(GVMVietMapProviderID), @"kind":@(kind),
            @"distance":distance ?: NSNull.null}];
    }
    [alerts sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        id da=a[@"distance"], db=b[@"distance"];
        if (da==NSNull.null) return db==NSNull.null ? NSOrderedSame : NSOrderedDescending;
        if (db==NSNull.null) return NSOrderedAscending;
        return [da compare:db];
    }];
    if (alerts.count>2) [alerts removeObjectsInRange:NSMakeRange(2,alerts.count-2)];
    return alerts;
}

NSDictionary *GVMVietMapAlertObservation(id payload, NSUInteger acceptedCount) {
    BOOL array=[payload isKindOfClass:NSArray.class];
    NSMutableArray *items=[NSMutableArray new];
    NSUInteger count=array ? [payload count] : 0;
    for (NSUInteger i=0;i<MIN(count,8);i++) {
        id item=payload[i];
        BOOL json=[item isKindOfClass:NSString.class];
        if (json && [item length]<=262144)
            item=[NSJSONSerialization JSONObjectWithData:[item dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        NSMutableDictionary *entry=[@{@"index":@(i),@"jsonString":@(json),
            @"dictionary":[NSNumber numberWithBool:[item isKindOfClass:NSDictionary.class]]} mutableCopy];
        if ([item isKindOfClass:NSDictionary.class]) {
            id encoded=item[@"image"];
            if ([encoded isKindOfClass:NSString.class] && [encoded length]<=180000) {
                NSData *bytes=[[NSData alloc] initWithBase64EncodedString:encoded options:0];
                NSString *digest=ImageDigest(bytes);
                entry[@"imageCharacters"]=@([encoded length]);
                entry[@"imageBytes"]=@(bytes.length);
                if (digest) entry[@"imageSHA256"]=digest;
                NSString *name=GVMVietMapAssetName(GVMVietMapKindForImageDigest(digest));
                if (name) entry[@"recognizedAsset"]=name;
            } else entry[@"imageUnavailable"]=@YES;
            for (NSString *key in @[@"distance",@"speedLimit"]) {
                id value=item[key];
                NSString *state=!value ? @"missing" : value==NSNull.null ? @"null" : @"invalid";
                NSNumber *number=Distance(value);
                if (number && (![key isEqual:@"speedLimit"] || number.doubleValue<=400)) {
                    entry[key]=number; state=@"number";
                }
                entry[[key stringByAppendingString:@"State"]]=state;
            }
        }
        [items addObject:entry];
    }
    return @{@"array":@(array),@"count":@(count),@"acceptedCount":@(MIN(acceptedCount,2)),
        @"truncated":@(count>items.count),@"items":items};
}

NSDictionary *GVMVietMapOverlayObservation(id payload) {
    // Inspect only known warning field names; never record map coordinates or free text.
    id patch=([payload isKindOfClass:NSArray.class] && [payload count]==2) ? payload[0] : payload;
    if (![patch isKindOfClass:NSDictionary.class]) return @{ @"dictionary":@NO };
    NSMutableDictionary *fields=[NSMutableDictionary new];
    for (NSString *key in @[@"stickyAlerts",@"upcomingAlerts",@"upcommingAlerts",@"alerts",
        @"restrictionEventData",@"parkingInfo",@"noPassingGoingIn",@"trafficSignal"]) {
        id value=patch[key];
        if (!value) continue;
        if ([value isKindOfClass:NSArray.class]) fields[key]=GVMVietMapAlertObservation(value,0);
        else fields[key]=@{@"shape":value==NSNull.null ? @"null" :
            [value isKindOfClass:NSDictionary.class] ? @"dictionary" :
            [value isKindOfClass:NSString.class] ? @"string" : @"other"};
    }
    return @{@"dictionary":@YES,@"fields":fields};
}

NSArray<NSDictionary *> *GVMVietMapOverlayStickyAlerts(id payload) {
    if (![payload isKindOfClass:NSArray.class] || [payload count]!=2 ||
        ![payload[0] isKindOfClass:NSDictionary.class]) return nil;
    id value=payload[0][@"stickyAlerts"];
    // Absent patch fields preserve prior state; an explicit empty/null field clears it.
    if (!value) return nil;
    if (value==NSNull.null) return @[];
    if (![value isKindOfClass:NSArray.class] || [value count]>32) return nil;
    return GVMVietMapAlertsFromPayload(value);
}
