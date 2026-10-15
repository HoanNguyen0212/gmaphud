#import "cmu-hud-relay.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <errno.h>

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
static NSTimeInterval sLastNavSend;

static NSString *sLastDatagram;   // Test-only capture

// ── Internal helpers ───────────────────────────────────────────────────────

static NSTimeInterval MonotonicNow(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

static void LogRelay(const char *buf, size_t len, ssize_t sent, int err) {
    static int logCount = 0;
    if (sent < 0 && (++logCount % 10 != 1)) return; // Debounce errors

    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    char timeStr[32];
    strftime(timeStr, sizeof(timeStr), "%H:%M:%S", tm_info);

    char cleanBuf[256];
    size_t copyLen = (len < sizeof(cleanBuf) - 1) ? len : sizeof(cleanBuf) - 1;
    memcpy(cleanBuf, buf, copyLen);
    cleanBuf[copyLen] = '\0';
    if (copyLen > 0 && cleanBuf[copyLen - 1] == '\n') cleanBuf[copyLen - 1] = '\0';

    char logLine[512];
    if (sent >= 0) {
        snprintf(logLine, sizeof(logLine), "[%s] [SENT %zdB] %s -> %s:%d\n",
                 timeStr, sent, cleanBuf, GVM_CMU_HUD_TARGET_IP, GVM_CMU_HUD_TARGET_PORT);
    } else {
        snprintf(logLine, sizeof(logLine), "[%s] [FAIL errno=%d (%s)] %s -> %s:%d\n",
                 timeStr, err, strerror(err), cleanBuf, GVM_CMU_HUD_TARGET_IP, GVM_CMU_HUD_TARGET_PORT);
    }

    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-relay.log"];
    FILE *f = fopen(path.UTF8String, "a");
    if (f) {
        fputs(logLine, f);
        fclose(f);
    }
}

static BOOL SendDatagram(const char *buf, size_t len) {
    if (sSock < 0 || len == 0) return NO;
    ssize_t sent = sendto(sSock, buf, len, 0,
                          (struct sockaddr *)&sTarget, sizeof(sTarget));
    int err = (sent < 0) ? errno : 0;
    LogRelay(buf, len, sent, err);
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
        sLastNavSend = MonotonicNow();
    }
}

static void HeartbeatTick(void) {
    @synchronized(sLock) {
        if (sSock < 0) return;
        NSTimeInterval now = MonotonicNow();
        // Heartbeat: resend current limit every 2.5s if it's active (> 0).
        if (sCurrentLimit > 0) {
            if (now - sLastSend >= kHeartbeatInterval) {
                SendLimit(sCurrentLimit);
            }
        }
        // Heartbeat: resend current navigation maneuver every 2.5s if active.
        if (sNavIcon > 0) {
            if (now - sLastNavSend >= kHeartbeatInterval) {
                SendNav(sNavIcon, sNavDist, sNavRoad);
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
        } else {
            // Immediate clear on navigation end
            SendNav(0, 0, @"");
        }
    }
}

void GVMCMURelayStop(void) {
    @synchronized(sLock) {
        if (sTimer) {
            dispatch_source_cancel(sTimer);
            sTimer = nil;
        }
        if (sSock >= 0) {
            // Send final "LIMIT 0" and "NAV 0 0" to clear the CMU display
            SendLimit(0);
            SendNav(0, 0, @"");
            close(sSock);
            sSock = -1;
        }
        sCurrentLimit = 0;
        sLimitSentOnce = NO;
        sNavIcon = 0;
        sNavDist = 0;
        sNavRoad = nil;
    }
}

NSString *GVMCMURelayLastDatagram(void) {
    @synchronized(sLock) {
        return [sLastDatagram copy];
    }
}
