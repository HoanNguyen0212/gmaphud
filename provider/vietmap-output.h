#import <Foundation/Foundation.h>
NSDictionary *GVMVietMapOutputAlert(NSDictionary *alert, NSTimeInterval receivedAt);
// Entries marked active are signs VietMap shows as in effect (its sticky alerts). They carry no
// distance, so upcoming signs take the two alert places first, and a sign that is also upcoming is
// shown once, with its distance.
NSDictionary *GVMVietMapOutput(NSDictionary *samples, NSArray<NSDictionary *> *alertEntries, NSTimeInterval now);
// The lane sample for the source output: the lanes VietMap Live shows (its overlay's laneInfo), which
// are in effect on the stretch being driven. Like a sign in effect they have no distance and no advance
// notice, and VietMap changes or clears them itself; an overlay patch without laneInfo leaves them as
// they are. They carry the publication time `now`, so they stay fresh only while VietMap Live keeps
// publishing. nil when there are none.
NSDictionary *GVMVietMapLaneSample(NSArray<NSNumber *> *codes, NSTimeInterval now);
