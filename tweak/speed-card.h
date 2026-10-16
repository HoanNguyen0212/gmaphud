#import <UIKit/UIKit.h>

// What the CarPlay and iPhone hosts set on either bubble. Classic lays the three parts out in
// the stored order; Halo only uses whether the alerts lead.
@protocol GVMSpeedCardView <NSObject>
@property(nonatomic,copy) NSNumber *speed,*limit;
@property(nonatomic,copy) NSArray<NSDictionary *> *alerts;
@property(nonatomic) BOOL night, compact;
@property(nonatomic) NSUInteger sourceID;
@property(nonatomic,copy) NSArray<NSString *> *moduleOrder;
@end
