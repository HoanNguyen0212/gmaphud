#import "cmu-hud-relay.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <math.h>

// ── Configuration ──────────────────────────────────────────────────────────
#ifndef GVM_CMU_HUD_TARGET_IP
#define GVM_CMU_HUD_TARGET_IP "192.168.100.1"
#endif
#ifndef GVM_CMU_HUD_TARGET_PORT
#define GVM_CMU_HUD_TARGET_PORT 8888
#endif
static const NSTimeInterval kHeartbeatInterval = 2.5;

// ── State (guarded by @synchronized on sLock) ──────────────────────────────
static id sLock;
static int sSock = -1;
static struct sockaddr_in sTarget;
static dispatch_source_t sTimer;

static NSUInteger sCurrentLimit;
static BOOL sLimitSentOnce;       // YES after the first send (including LIMIT 0)
static NSTimeInterval sLastSend;  // mach_absolute_time based

static NSUInteger sNavIcon;
static NSUInteger sNavDist;
static NSString *sNavRoad;

static NSString *sLastDatagram;   // Test-only capture

// ── Internal helpers ───────────────────────────────────────────────────────

static NSTimeInterval MonotonicNow(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

static BOOL SendDatagram(const char *buf, size_t len) {
    if (sSock < 0 || len == 0) return NO;
    ssize_t sent = sendto(sSock, buf, len, 0,
                          (struct sockaddr *)&sTarget, sizeof(sTarget));
    if (sent >= 0) {
        @synchronized(sLock) {
            sLastDatagram = [[NSString alloc] initWithBytes:buf length:len
                                                  encoding:NSUTF8StringEncoding];
        }
    }
    return sent >= 0;
}

// Format and send "LIMIT <kmh>\n".
static void SendLimit(NSUInteger limitKmh) {
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "LIMIT %lu\n", (unsigned long)limitKmh);
    if (n > 0 && (size_t)n < sizeof(buf)) {
        SendDatagram(buf, (size_t)n);
        sLastSend = MonotonicNow();
    }
}

// Format and send "NAV <icon_id> <dist_m> <road_name>\n".
static void SendNav(NSUInteger iconID, NSUInteger distM, NSString *road) {
    if (!road) road = @"";
    // Sanitize road name: truncate to 200 bytes, strip newlines.
    NSString *safe = [road stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (safe.length > 200) safe = [safe substringToIndex:200];
    char buf[300];
    int n = snprintf(buf, sizeof(buf), "NAV %lu %lu %s\n",
                     (unsigned long)iconID, (unsigned long)distM,
                     safe.UTF8String ?: "");
    if (n > 0 && (size_t)n < sizeof(buf)) {
        SendDatagram(buf, (size_t)n);
    }
}

static void HeartbeatTick(void) {
    @synchronized(sLock) {
        if (sSock < 0) return;
        // Heartbeat: resend current limit every 2.5s if it's active (> 0).
        if (sCurrentLimit > 0) {
            NSTimeInterval now = MonotonicNow();
            if (now - sLastSend >= kHeartbeatInterval) {
                SendLimit(sCurrentLimit);
            }
        }
    }
}

// ── Public API ─────────────────────────────────────────────────────────────

void GVMCMURelayStart(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sLock = [NSObject new]; });

    @synchronized(sLock) {
        if (sSock >= 0) return; // Already started

        // Create non-blocking UDP socket
        sSock = socket(AF_INET, SOCK_DGRAM, 0);
        if (sSock < 0) return;
        int flags = fcntl(sSock, F_GETFL, 0);
        if (flags >= 0) fcntl(sSock, F_SETFL, flags | O_NONBLOCK);

        // Target address
        memset(&sTarget, 0, sizeof(sTarget));
        sTarget.sin_family = AF_INET;
        sTarget.sin_port = htons(GVM_CMU_HUD_TARGET_PORT);
        inet_pton(AF_INET, GVM_CMU_HUD_TARGET_IP, &sTarget.sin_addr);

        sCurrentLimit = 0;
        sLimitSentOnce = NO;
        sLastSend = 0;
        sNavIcon = 0;
        sNavDist = 0;
        sNavRoad = nil;

        // Heartbeat timer on main queue, fires every 1s (checks internally
        // whether 2.5s have elapsed since last send).
        sTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                        dispatch_get_main_queue());
        dispatch_source_set_timer(sTimer,
                                  dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                                  (uint64_t)(1 * NSEC_PER_SEC),
                                  (uint64_t)(0.25 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(sTimer, ^{ HeartbeatTick(); });
        dispatch_resume(sTimer);
    }
}

void GVMCMURelaySetLimit(NSUInteger limitKmh) {
    @synchronized(sLock) {
        if (sSock < 0) return;

        BOOL changed = (sCurrentLimit != limitKmh);
        sCurrentLimit = limitKmh;

        if (changed || !sLimitSentOnce) {
            SendLimit(limitKmh);
            sLimitSentOnce = YES;
        }
    }
}

void GVMCMURelaySetNav(NSUInteger iconID, NSUInteger distanceMeters, NSString *roadName) {
    @synchronized(sLock) {
        if (sSock < 0) return;

        BOOL changed = (sNavIcon != iconID) || (sNavDist != distanceMeters) ||
                        ![sNavRoad isEqualToString:roadName ?: @""];
        if (!changed) return;

        sNavIcon = iconID;
        sNavDist = distanceMeters;
        sNavRoad = [roadName copy];

        if (iconID > 0) {
            SendNav(iconID, distanceMeters, sNavRoad);
        }
        // iconID == 0 means navigation ended; cmu_splim_listener handles
        // expiry via the 10-second timestamp mechanism.
    }
}

void GVMCMURelayStop(void) {
    @synchronized(sLock) {
        if (sTimer) {
            dispatch_source_cancel(sTimer);
            sTimer = nil;
        }
        if (sSock >= 0) {
            // Send final "LIMIT 0" to clear the CMU display
            SendLimit(0);
            close(sSock);
            sSock = -1;
        }
        sCurrentLimit = 0;
        sLimitSentOnce = NO;
    }
}

NSString *GVMCMURelayLastDatagram(void) {
    @synchronized(sLock) {
        return [sLastDatagram copy];
    }
}
