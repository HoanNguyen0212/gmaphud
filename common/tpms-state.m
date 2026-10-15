#import "tpms-state.h"
#include <math.h>

const char *const GVMTPMSStateName = "com.chou.googlemaps.vietmap.tpms";

static uint32_t EncodeTire(const GVMTPMSTire *tire) {
    if (!tire || !tire->active) return 0;
    // Pressure 0.0 - 5.0 bar -> 0 to 250 (8 bits)
    float p = tire->pressure;
    if (p < 0.0f) p = 0.0f;
    if (p > 5.0f) p = 5.0f;
    uint32_t pInt = (uint32_t)roundf(p * 50.0f) & 0xFF;
    uint32_t warn = tire->warning & 0x03;
    uint32_t active = 1;
    // 11 bits: [active: 1 bit][warn: 2 bits][pressure: 8 bits]
    return (active << 10) | (warn << 8) | pInt;
}

static GVMTPMSTire DecodeTire(uint32_t val) {
    GVMTPMSTire tire;
    memset(&tire, 0, sizeof(tire));
    if (!(val & (1 << 10))) return tire; // inactive
    tire.active = YES;
    tire.warning = (val >> 8) & 0x03;
    uint32_t pInt = val & 0xFF;
    tire.pressure = (float)pInt / 50.0f;
    return tire;
}

uint64_t GVMEncodeTPMS(const GVMTPMSData *data, NSTimeInterval uptime) {
    if (!data || !data->hasData || !isfinite(uptime) || uptime < 0) return 0;
    uint64_t fl = EncodeTire(&data->fl);
    uint64_t fr = EncodeTire(&data->fr);
    uint64_t rl = EncodeTire(&data->rl);
    uint64_t rr = EncodeTire(&data->rr);
    
    // 16 bits timestamp (seconds modulo 65536)
    uint64_t timeSec = ((uint64_t)floor(uptime)) & 0xFFFF;
    
    // Layout: [time: 16b][FL: 11b][FR: 11b][RL: 11b][RR: 11b][marker: 4b = 0xA]
    // 16 + 11*4 + 4 = 64 bits
    return (timeSec << 48) | (fl << 37) | (fr << 26) | (rl << 15) | (rr << 4) | 0x0A;
}

GVMTPMSData GVMDecodeTPMS(uint64_t state, NSTimeInterval uptime) {
    GVMTPMSData result;
    memset(&result, 0, sizeof(result));
    if ((state & 0x0F) != 0x0A || !isfinite(uptime) || uptime < 0) return result;
    
    uint64_t timeSec = (state >> 48) & 0xFFFF;
    uint64_t currentSec = ((uint64_t)floor(uptime)) & 0xFFFF;
    int64_t age = (int64_t)currentSec - (int64_t)timeSec;
    if (age < -30000) age += 65536; // rollover handle
    if (age < 0 || age > 300) return result; // Stale after 300 seconds (5 minutes)
    
    uint32_t flVal = (state >> 37) & 0x7FF;
    uint32_t frVal = (state >> 26) & 0x7FF;
    uint32_t rlVal = (state >> 15) & 0x7FF;
    uint32_t rrVal = (state >> 4) & 0x7FF;
    
    result.fl = DecodeTire(flVal);
    result.fr = DecodeTire(frVal);
    result.rl = DecodeTire(rlVal);
    result.rr = DecodeTire(rrVal);
    result.receivedAt = uptime - (double)age;
    result.hasData = (result.fl.active || result.fr.active || result.rl.active || result.rr.active);
    return result;
}
