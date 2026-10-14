#import <Foundation/Foundation.h>

extern const NSUInteger GVMVietMapProviderID;
NSUInteger GVMVietMapKindForImage(NSData *image);
NSUInteger GVMVietMapKindForImageDigest(NSString *hash);
NSUInteger GVMVietMapKindForAssetName(NSString *name);
NSString *GVMVietMapAssetName(NSUInteger kind);
NSArray<NSDictionary *> *GVMVietMapAlertsFromPayload(id payload);
NSDictionary *GVMVietMapAlertObservation(id payload, NSUInteger acceptedCount);

NSDictionary *GVMVietMapOverlayObservation(id payload);
NSArray<NSDictionary *> *GVMVietMapOverlayStickyAlerts(id payload);
