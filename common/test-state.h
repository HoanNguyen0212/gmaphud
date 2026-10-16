#import <Foundation/Foundation.h>
#include <stdint.h>

extern const char *const GVMTestStateName;
uint64_t GVMEncodeTest(NSInteger speed, NSInteger limit, NSTimeInterval uptime, NSInteger seconds);
NSDictionary *GVMDecodeTest(uint64_t state, NSTimeInterval uptime);

// Test lanes shown with a test sample: up to seven lanes, each {code: VietMap lane bitmask,
// enabled: BOOL}, and a distance in metres or NSNull. They never enter the live source namespace.
extern const char *const GVMTestLaneStateName;
uint64_t GVMEncodeTestLanes(NSArray<NSDictionary *> *items, id distance);
NSDictionary *GVMDecodeTestLanes(uint64_t state);
// Parses "1,1,1,5,4@127": comma-separated lane codes, an x prefix for a lane not to use, then an
// optional @ and distance. nil when malformed.
NSDictionary *GVMParseTestLanes(NSString *text);
