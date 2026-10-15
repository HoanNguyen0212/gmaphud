#pragma once
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#define GVM_BACKGROUND_SIGNAL "com.chou.gmaphud.background.carplay"
#define GVM_BACKGROUND_PHONE_SIGNAL "com.chou.gmaphud.background.phone"
static inline bool GVMBackgroundActive(double now, uint64_t heartbeat) {
    double age = now - (double)heartbeat / 1000.0;
    return heartbeat && isfinite(now) && age >= 0 && age < 12;
}
static inline bool GVMBackgroundMayLaunch(double now, double next, unsigned attempts) {
    return isfinite(now) && isfinite(next) && now >= next && attempts < 3;
}
static inline bool GVMBackgroundAnyHostActive(double now, uint64_t carplay, uint64_t phone) {
    return GVMBackgroundActive(now,carplay) || GVMBackgroundActive(now,phone);
}
static inline double GVMBackgroundRetryDelay(unsigned attempts) {
    return attempts <= 1 ? 15 : attempts == 2 ? 30 : 60;
}
static inline bool GVMBackgroundNewClient(int previous, int current) {
    return previous > 0 && current > 0 && previous != current;
}

#define GVM_BACKGROUND_PERMISSION "com.chou.gmaphud.background.permission"
#define GVM_BACKGROUND_LOCATION_SESSION "com.chou.gmaphud.background.location-session"
static inline bool GVMBackgroundLocationAuthorized(int status) {
    // Core Location: 3 = Always; 4 = When In Use. Unknown/denied fail closed.
    return status==3 || status==4;
}
static inline bool GVMBackgroundNeedsUsageContext(int status, bool active) {
    return active && status==4;
}
static inline uint64_t GVMBackgroundPermissionState(double now, bool allowed) {
    if (!isfinite(now) || now<1 || now>UINT32_MAX) return 0;
    return ((uint64_t)now<<1) | (allowed ? 1 : 0);
}
static inline bool GVMBackgroundPermissionAllowed(double now, uint64_t state) {
    double age=now-(double)(state>>1);
    return (state&1) && isfinite(now) && age>=0 && age<6;
}

// A selected source may continue its own running GPS only while a real host is visible.
static inline bool GVMBackgroundSourceLocationActive(bool selected, int authorization, bool services,
    double now, uint64_t carplay, uint64_t phone) {
    return selected && services && GVMBackgroundLocationAuthorized(authorization) &&
        GVMBackgroundAnyHostActive(now,carplay,phone);
}

#define GVM_BACKGROUND_LOCATION_SOURCE "com.chou.gmaphud.background.location-source"
#define GVM_BACKGROUND_BOOTSTRAP_CARPLAY "com.chou.gmaphud.background.bootstrap-carplay"
static inline bool GVMBackgroundDisconnectDue(double now,double disconnectedAt) {
    return disconnectedAt>0 && isfinite(now) && isfinite(disconnectedAt) && now-disconnectedAt>=20;
}
// Auto-exit after a CarPlay disconnect holds the source closed only while no Google Maps is
// visible on the iPhone; a visible phone map is still in use and may wake the source again.
static inline bool GVMBackgroundExitHolds(bool autoExit, bool connected, bool phoneVisible,
    double disconnectedAt, bool exitCompleted) {
    return autoExit && !connected && !phoneVisible && (disconnectedAt>0 || exitCompleted);
}

// Cold GPS recovery is bounded and ends once a genuinely fresh sample arrives.
static inline bool GVMBackgroundGPSRetryDue(double now, double next, unsigned attempts, bool confirmed) {
    return !confirmed && isfinite(now) && isfinite(next) && next>0 && now>=next && attempts>0 && attempts<3;
}
