#import "cmu-hud-relay.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <errno.h>

#ifndef IP_BOUND_IF
#define IP_BOUND_IF 25
#endif
#ifndef IPV6_BOUND_IF
#define IPV6_BOUND_IF 125
#endif

// ── Configuration ──────────────────────────────────────────────────────────
#ifndef GVM_CMU_HUD_TARGET_IP
#define GVM_CMU_HUD_TARGET_IP "192.168.100.1"
#endif
#ifndef GVM_CMU_HUD_TARGET_IP_USB
#define GVM_CMU_HUD_TARGET_IP_USB "192.168.53.1"
#endif
#ifndef GVM_CMU_HUD_TARGET_PORT
#define GVM_CMU_HUD_TARGET_PORT 8888
#endif
static const NSTimeInterval kHeartbeatInterval = 2.5;

// ── State (guarded by @synchronized on sLock) ──────────────────────────────
static id sLock;
static int sSock = -1;
static int sSockUSB = -1; // Socket bound strictly to Lightning USB-NCM (en3)
static struct sockaddr_in sTarget;
static int sSock6 = -1;
static struct sockaddr_in6 sTarget6;
static BOOL sTarget6Resolved = NO;
static time_t sTarget6LastResolve = 0;
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

static void LogRelay(const char *targetIP, int targetPort, const char *buf, size_t len, ssize_t sent, int err) {
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
    const char *dstIP = targetIP ?: "unknown";
    if (sent >= 0) {
        snprintf(logLine, sizeof(logLine), "[%s] [SENT %zdB] %s -> %s:%d\n",
                 timeStr, sent, cleanBuf, dstIP, targetPort);
    } else {
        snprintf(logLine, sizeof(logLine), "[%s] [FAIL errno=%d (%s)] %s -> %s:%d\n",
                 timeStr, err, strerror(err), cleanBuf, dstIP, targetPort);
    }

    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-relay.log"];
    FILE *f = fopen(path.UTF8String, "a");
    if (f) {
        fputs(logLine, f);
        fclose(f);
    }
}

static unsigned int GetUSBInterfaceIndex(char *outName, size_t maxLen) {
    unsigned int idx = if_nametoindex("en3");
    if (idx > 0) {
        if (outName && maxLen > 3) strncpy(outName, "en3", maxLen);
        return idx;
    }
    // Dynamic scan fallback for any other USB-Ethernet interface on iOS
    struct ifaddrs *ifas = NULL;
    if (getifaddrs(&ifas) == 0 && ifas != NULL) {
        for (struct ifaddrs *ifa = ifas; ifa; ifa = ifa->ifa_next) {
            if (!ifa->ifa_name || !ifa->ifa_addr) continue;
            if (strncmp(ifa->ifa_name, "en", 2) == 0 && strcmp(ifa->ifa_name, "en0") != 0) {
                idx = if_nametoindex(ifa->ifa_name);
                if (idx > 0) {
                    if (outName && maxLen > 0) strncpy(outName, ifa->ifa_name, maxLen);
                    freeifaddrs(ifas);
                    return idx;
                }
            }
        }
        freeifaddrs(ifas);
    }
    return 0;
}

static void EnsureSocketOpen(void) {
    char usbIfName[IFNAMSIZ] = {0};
    unsigned int usbIdx = GetUSBInterfaceIndex(usbIfName, sizeof(usbIfName));

    if (sSock < 0) {
        sSock = socket(AF_INET, SOCK_DGRAM, 0);
        if (sSock >= 0) {
            int flags = fcntl(sSock, F_GETFL, 0);
            if (flags >= 0) fcntl(sSock, F_SETFL, flags | O_NONBLOCK);
            int opt = 1;
            setsockopt(sSock, SOL_SOCKET, SO_NOSIGPIPE, &opt, sizeof(opt));
            setsockopt(sSock, SOL_SOCKET, SO_BROADCAST, &opt, sizeof(opt));
        }
    }
    if (usbIdx > 0 && sSockUSB < 0) {
        sSockUSB = socket(AF_INET, SOCK_DGRAM, 0);
        if (sSockUSB >= 0) {
            int flags = fcntl(sSockUSB, F_GETFL, 0);
            if (flags >= 0) fcntl(sSockUSB, F_SETFL, flags | O_NONBLOCK);
            int opt = 1;
            setsockopt(sSockUSB, SOL_SOCKET, SO_NOSIGPIPE, &opt, sizeof(opt));
            setsockopt(sSockUSB, SOL_SOCKET, SO_BROADCAST, &opt, sizeof(opt));
            setsockopt(sSockUSB, IPPROTO_IP, IP_BOUND_IF, &usbIdx, sizeof(usbIdx));
        }
    }
    if (sSock6 < 0) {
        sSock6 = socket(AF_INET6, SOCK_DGRAM, 0);
        if (sSock6 >= 0) {
            int flags = fcntl(sSock6, F_GETFL, 0);
            if (flags >= 0) fcntl(sSock6, F_SETFL, flags | O_NONBLOCK);
            int opt = 1;
            setsockopt(sSock6, SOL_SOCKET, SO_NOSIGPIPE, &opt, sizeof(opt));
            if (usbIdx > 0) {
                setsockopt(sSock6, IPPROTO_IPV6, IPV6_BOUND_IF, &usbIdx, sizeof(usbIdx));
            }
        }
    }
}

static BOOL SendDatagram(const char *buf, size_t len) {
    EnsureSocketOpen();
    if ((sSock < 0 && sSockUSB < 0 && sSock6 < 0) || len == 0) return NO;

    BOOL anySent = NO;
    char usbIfName[IFNAMSIZ] = {0};
    unsigned int usbIdx = GetUSBInterfaceIndex(usbIfName, sizeof(usbIfName));

    // 1. IPv6 mDNS to cmu.local (native to wired Lightning CarPlay USB-NCM)
    if (sSock6 >= 0) {
        time_t now = time(NULL);
        if (!sTarget6Resolved || (now - sTarget6LastResolve > 30)) {
            struct addrinfo hints, *res = NULL;
            memset(&hints, 0, sizeof(hints));
            hints.ai_family = AF_INET6;
            hints.ai_socktype = SOCK_DGRAM;
            if (getaddrinfo("cmu.local", "8888", &hints, &res) == 0 && res != NULL) {
                memcpy(&sTarget6, res->ai_addr, sizeof(sTarget6));
                sTarget6Resolved = YES;
                sTarget6LastResolve = now;
                freeaddrinfo(res);
            }
        }
        if (sTarget6Resolved) {
            // Mandate for Darwin IPv6 Link-Local: scope_id MUST point to USB interface!
            if (usbIdx > 0 && IN6_IS_ADDR_LINKLOCAL(&sTarget6.sin6_addr)) {
                sTarget6.sin6_scope_id = usbIdx;
            }
            ssize_t sent = sendto(sSock6, buf, len, 0, (struct sockaddr *)&sTarget6, sizeof(sTarget6));
            int err = (sent < 0) ? errno : 0;
            LogRelay("cmu.local", GVM_CMU_HUD_TARGET_PORT, buf, len, sent, err);
            if (sent >= 0) {
                anySent = YES;
            }
        }
    }

    // 2. IPv4 USB-NCM link-local subnet broadcast via dedicated bound socket
    if (sSockUSB >= 0) {
        struct sockaddr_in dstUSB;
        memset(&dstUSB, 0, sizeof(dstUSB));
        dstUSB.sin_family = AF_INET;
        dstUSB.sin_port = htons(GVM_CMU_HUD_TARGET_PORT);
        inet_pton(AF_INET, "169.254.255.255", &dstUSB.sin_addr);

        ssize_t sent = sendto(sSockUSB, buf, len, 0, (struct sockaddr *)&dstUSB, sizeof(dstUSB));
        int err = (sent < 0) ? errno : 0;
        LogRelay("169.254.255.255", GVM_CMU_HUD_TARGET_PORT, buf, len, sent, err);
        if (sent >= 0) {
            anySent = YES;
        }
    }

    // 3. IPv4 targets (Wi-Fi AP, USB fallback, Global broadcast)
    if (sSock >= 0) {
        static const char * const kTargets[] = {
            GVM_CMU_HUD_TARGET_IP_USB, // "192.168.53.1" - Wired USB Lightning CarPlay
            GVM_CMU_HUD_TARGET_IP,     // "192.168.100.1" - Wireless CMU AP / Hotspot
            "255.255.255.255"          // Subnet broadcast fallback
        };

        for (size_t i = 0; i < sizeof(kTargets)/sizeof(kTargets[0]); i++) {
            struct sockaddr_in dst;
            memset(&dst, 0, sizeof(dst));
            dst.sin_family = AF_INET;
            dst.sin_port = htons(GVM_CMU_HUD_TARGET_PORT);
            inet_pton(AF_INET, kTargets[i], &dst.sin_addr);

            ssize_t sent = sendto(sSock, buf, len, 0, (struct sockaddr *)&dst, sizeof(dst));
            int err = (sent < 0) ? errno : 0;
            LogRelay(kTargets[i], GVM_CMU_HUD_TARGET_PORT, buf, len, sent, err);
            if (sent >= 0) {
                anySent = YES;
            }
        }
    }

    if (anySent) {
        @synchronized(sLock) {
            sLastDatagram = [[NSString alloc] initWithBytes:buf length:len
                                                  encoding:NSUTF8StringEncoding];
        }
    }
    return anySent;
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
    // Convert to 7-bit ASCII to guarantee 100% clean HUD display (no corrupted UTF-8)
    NSData *asciiData = [road dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    NSString *safe = [[NSString alloc] initWithData:asciiData encoding:NSASCIIStringEncoding] ?: road;
    safe = [safe stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    safe = [safe stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
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
        EnsureSocketOpen();

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
        EnsureSocketOpen();

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
        if (sSock >= 0 || sSockUSB >= 0 || sSock6 >= 0) {
            // Send final "LIMIT 0" and "NAV 0 0" to clear the CMU display
            SendLimit(0);
            SendNav(0, 0, @"");
            if (sSock >= 0) {
                close(sSock);
                sSock = -1;
            }
            if (sSockUSB >= 0) {
                close(sSockUSB);
                sSockUSB = -1;
            }
            if (sSock6 >= 0) {
                close(sSock6);
                sSock6 = -1;
            }
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
