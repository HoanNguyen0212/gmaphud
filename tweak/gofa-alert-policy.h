#ifndef GVM_GOFA_ALERT_POLICY_H
#define GVM_GOFA_ALERT_POLICY_H
#include <stdbool.h>
#include <math.h>

// A point reached in this native candidate membership must not return while receding.
static inline bool GVMGofaPointPassed(bool alreadyPassed, double distance) {
    return alreadyPassed || (isfinite(distance) && distance >= 0 && distance <= 5);
}

// GOFA re-issues its speed board only as its pipeline accepts movement, and none while iOS
// delivers no GPS; its own map keeps the latest board meanwhile. That board stays current
// until GOFA replaces or clears it, or the latest GPS lies beyond this radius from the
// position at which it was observed (NAN when either position was unknown).
#define GVM_GOFA_BOARD_RADIUS 50.0
static inline bool GVMGofaBoardNear(double anchorDistance) {
    return isfinite(anchorDistance) && anchorDistance >= 0 && anchorDistance <= GVM_GOFA_BOARD_RADIUS;
}
#endif
