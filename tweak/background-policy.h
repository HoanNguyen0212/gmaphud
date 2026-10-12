#pragma once
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#define GVM_BACKGROUND_SIGNAL "com.chou.gmaphud.background.carplay"
static inline bool GVMBackgroundActive(double now, uint64_t heartbeat) {
    double age = now - (double)heartbeat / 1000.0;
    return heartbeat && isfinite(now) && age >= 0 && age < 12;
}
static inline bool GVMBackgroundMayLaunch(double now, double next, unsigned attempts) {
    return isfinite(now) && isfinite(next) && now >= next && attempts < 3;
}
static inline double GVMBackgroundRetryDelay(unsigned attempts) {
    return attempts <= 1 ? 15 : attempts == 2 ? 30 : 60;
}
static inline bool GVMBackgroundNewClient(int previous, int current) {
    return previous > 0 && current > 0 && previous != current;
}

#define GVM_BACKGROUND_PERMISSION "com.chou.gmaphud.background.permission"
static inline uint64_t GVMBackgroundPermissionState(double now, bool allowed) {
    if (!isfinite(now) || now<1 || now>UINT32_MAX) return 0;
    return ((uint64_t)now<<1) | (allowed ? 1 : 0);
}
static inline bool GVMBackgroundPermissionAllowed(double now, uint64_t state) {
    double age=now-(double)(state>>1);
    return (state&1) && isfinite(now) && age>=0 && age<6;
}
