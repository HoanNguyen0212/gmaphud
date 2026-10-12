#import <Foundation/Foundation.h>
#include <stdint.h>

extern const char *const GVMTPMSStateName;

typedef struct {
    float pressure;      // in bar (e.g. 2.3)
    int temperature;     // in Celsius (e.g. 35)
    uint8_t warning;     // 0 = normal, 1 = low pressure, 2 = high pressure, 3 = high temp / leak
    BOOL active;
} GVMTPMSTire;

typedef struct {
    GVMTPMSTire fl;      // Front Left (Trước Trái)
    GVMTPMSTire fr;      // Front Right (Trước Phải)
    GVMTPMSTire rl;      // Rear Left (Sau Trái)
    GVMTPMSTire rr;      // Rear Right (Sau Phải)
    NSTimeInterval receivedAt;
    BOOL hasData;
} GVMTPMSData;

// Encode 4 tires into a single 64-bit uint64_t Darwin notification state
uint64_t GVMEncodeTPMS(const GVMTPMSData *data, NSTimeInterval uptime);

// Decode 64-bit uint64_t Darwin notification state into structured 4-tire data
GVMTPMSData GVMDecodeTPMS(uint64_t state, NSTimeInterval uptime);
