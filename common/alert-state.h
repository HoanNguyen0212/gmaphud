#import <Foundation/Foundation.h>
#include <stdint.h>

extern const char *const GVMFirstAlertStateName;
extern const char *const GVMSecondAlertStateName;
extern const char *const GVMTestFirstAlertStateName;
extern const char *const GVMTestSecondAlertStateName;
uint64_t GVMEncodeAlert(NSDictionary *alert, NSTimeInterval receivedAt);
NSDictionary *GVMDecodeAlert(uint64_t state, NSTimeInterval uptime);
NSDictionary *GVMDecodeAlertWithin(uint64_t state, NSTimeInterval uptime, NSTimeInterval maxAge);
