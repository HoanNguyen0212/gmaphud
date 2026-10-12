#import <Foundation/Foundation.h>
#include <stdint.h>

extern const char *const GVMSpeedStateName;
extern const char *const GVMLimitStateName;
uint64_t GVMEncodeSample(NSNumber *value, NSTimeInterval receivedAt);
NSNumber *GVMDecodeSample(uint64_t state, NSTimeInterval uptime, BOOL allowZero);

extern const char *const GVMSourceRequestName;
BOOL GVMShouldRequestSource(NSTimeInterval now, NSTimeInterval last, BOOL visible, BOOL test, BOOL missing);
