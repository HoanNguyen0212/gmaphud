#ifndef GVM_GOFA_ALERT_POLICY_H
#define GVM_GOFA_ALERT_POLICY_H
#include <stdbool.h>
#include <math.h>

// A point reached in this native candidate membership must not return while receding.
static inline bool GVMGofaPointPassed(bool alreadyPassed, double distance) {
    return alreadyPassed || (isfinite(distance) && distance >= 0 && distance <= 5);
}
#endif
