#import <Foundation/Foundation.h>

extern const NSUInteger GVMVietMapProviderID;
NSUInteger GVMVietMapKindForImage(NSData *image);
NSUInteger GVMVietMapKindForImageDigest(NSString *hash);
NSUInteger GVMVietMapKindForAssetName(NSString *name);
NSString *GVMVietMapAssetName(NSUInteger kind);
NSArray<NSDictionary *> *GVMVietMapAlertsFromPayload(id payload);
NSDictionary *GVMVietMapAlertObservation(id payload, NSUInteger acceptedCount);

NSDictionary *GVMVietMapOverlayObservation(id payload);
// Shape of one value (such as a JSON string): field names and short codes only, never free text.
NSDictionary *GVMVietMapValueObservation(id payload);
// Bytes carried by a channel value (NSData or Flutter typed data), else nil.
NSData *GVMVietMapDataValue(id item);
// The overlay patch (first argument of updateMapOverlayData), else nil.
NSDictionary *GVMVietMapOverlayPatch(id payload);
// Whether an overlay patch carries image bytes (VietMap's lane icons travel this way).
BOOL GVMVietMapOverlayCarriesImages(id payload);
NSArray<NSDictionary *> *GVMVietMapOverlayStickyAlerts(id payload);
// The overlay's laneInfo: the lanes VietMap Live shows, in effect on the stretch being driven, one
// bitmask string per lane, left to right. nil when a partial patch has no laneInfo (they stay as they
// are); empty when there are none or they cannot be read.
NSArray<NSNumber *> *GVMVietMapOverlayLaneCodes(id payload);
