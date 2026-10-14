#import "source-output.h"

// Main-queue owned. Native identities remain private to this adapter.
@interface GVMWazeOutputStore : NSObject
- (void)updateIdentifier:(NSString *)identifier icon:(NSString *)icon type:(NSInteger)type
                subtype:(NSInteger)subtype trait:(NSInteger)trait distance:(NSInteger)distance
                valid:(BOOL)valid passed:(BOOL)passed
               atUptime:(NSTimeInterval)uptime;
- (void)updateSpeed:(double)millimetresPerSecond timestamp:(double)timestamp
               now:(double)now uptime:(double)uptime optionalLimit:(uint64_t)limit;
- (NSDictionary *)outputAtUptime:(NSTimeInterval)uptime;
@end
