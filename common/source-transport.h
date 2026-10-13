#import "source-output.h"

// All access is serialized internally. One adapter process owns each source namespace.
BOOL GVMPublishSourceOutput(NSDictionary *output, NSTimeInterval now, BOOL force);
NSDictionary *GVMReadSourceOutput(NSTimeInterval now);
NSUInteger GVMSelectedSourceID(void);
BOOL GVMSelectOutputSource(NSUInteger sourceID);
void GVMRestoreOutputSelection(void);
NSString *GVMOutputRequestName(NSUInteger sourceID);
BOOL GVMRequestSelectedSource(void);
