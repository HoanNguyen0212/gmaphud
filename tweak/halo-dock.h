#import <UIKit/UIKit.h>

// Signs in effect shown under CarPlay's maneuver card during navigation, left to right, `diameter`
// points each with a 6-point gap. The view reaches `GVMHaloSignDockBleed` of a diameter beyond the
// signs on every side so the stickers' shadows are not cut.
extern const CGFloat GVMHaloSignDockBleed;
@interface GVMHaloSignDock : UIView
@property(nonatomic,copy) NSArray<NSDictionary *> *signs;
@property(nonatomic) CGFloat diameter;
@end
