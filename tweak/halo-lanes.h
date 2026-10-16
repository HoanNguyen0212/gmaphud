#import <UIKit/UIKit.h>

// The New UI lane strip, drawn as a QCVN lane sign: one white arrow per lane, left to right, on a
// blue panel with dashed white lane lines. The lanes are in effect where they show, so there is no
// distance tag. Drawn at size L and
// scaled by `scale`, so its frame is GVMLaneStripMetricsFor(count) times `scale`.
@interface GVMHaloLaneStrip : UIView
// The source output's lanes sample: {distance, items:[{code, enabled}], receivedAt}.
@property(nonatomic,copy) NSDictionary *lanes;
@property(nonatomic) double scale;
@end
