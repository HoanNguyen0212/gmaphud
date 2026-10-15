#import <UIKit/UIKit.h>
@interface GVMOverspeedFrame : UIView
@property(nonatomic) BOOL wholeScreen;
- (void)setWarningLevel:(NSUInteger)level;
- (void)setWarningActive:(BOOL)active;
@end
