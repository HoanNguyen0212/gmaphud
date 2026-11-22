#import "cmu-hud-relay.h"
#include <sys/socket.h>
#include <sys/time.h>
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
#include <notify.h>

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
#ifndef GVM_CMU_HUD_TARGET_IP_NCM
#define GVM_CMU_HUD_TARGET_IP_NCM "169.254.53.1"
#endif
#ifndef GVM_CMU_HUD_TARGET_PORT
#define GVM_CMU_HUD_TARGET_PORT 8888
#endif
static const NSTimeInterval kHeartbeatInterval = 2.5;
#ifndef GVM_AHEAD_WARNING_DISTANCE_METERS
#define GVM_AHEAD_WARNING_DISTANCE_METERS 500
#endif
static const NSUInteger kAheadWarningIcon = 12; // Mazda HUD flag glyph

// ── State (guarded by @synchronized on sLock) ──────────────────────────────
static id sLock;
static int sSock = -1;
static int sSockUSB = -1; // Socket bound strictly to Lightning USB-NCM (en3)
static struct sockaddr_in sTarget;
static int sSock6 = -1;
static struct sockaddr_in6 sTarget6;
static BOOL sTarget6Resolved = NO;
static time_t sTarget6LastResolve = 0;
static unsigned int sTarget6BoundIf = 0;
static dispatch_source_t sTimer;

static NSUInteger sCurrentLimit;
static BOOL sLimitSentOnce;       // YES after the first send (including LIMIT 0)
static NSTimeInterval sLastSend;  // mach_absolute_time based
static NSTimeInterval sLastSyncSend;

static NSUInteger sNavIcon;
static NSUInteger sNavDist;
static NSString *sNavRoad;
static NSTimeInterval sLastNavSend;

static NSUInteger sAheadLimit;
static NSUInteger sAheadDist;

// The source and Google Maps tweaks are injected into different processes.
// Darwin notify state is the small, process-safe bridge: VietMap publishes the
// upcoming sign, while Google Maps remains the sole normal UDP HUD writer.
static const char *kGoogleNavNotify = "com.chou.gmaphud.cmu.google-nav";
static const char *kGoogleHeartbeatNotify = "com.chou.gmaphud.cmu.google-heartbeat";
static const char *kAheadSpeedNotify = "com.chou.gmaphud.cmu.ahead-speed";
static int sGoogleNavToken = -1;
static int sGoogleHeartbeatToken = -1;
static int sAheadSpeedToken = -1;
static const NSTimeInterval kSharedStateTTL = 5.0;

typedef struct {
    NSUInteger limit;
    NSUInteger distance;
    NSTimeInterval updatedAt;
} GVMSharedAheadState;

static void GVMEnsureNotifyTokens(void) __attribute__((unused));
static void GVMPublishGoogleHeartbeat(BOOL active) __attribute__((unused));
static void GVMPublishGoogleNavigation(BOOL active) __attribute__((unused));
static BOOL GVMGoogleProcessAlive(void) __attribute__((unused));
static void GVMPublishAheadState(NSUInteger limit, NSUInteger distance) __attribute__((unused));
static GVMSharedAheadState GVMReadSharedAheadState(void) __attribute__((unused));
static BOOL GVMRefreshSharedAheadState(void) __attribute__((unused));

static NSString *sLastDatagram;   // Test-only capture

// ── Internal helpers ───────────────────────────────────────────────────────

static NSTimeInterval MonotonicNow(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

static uint64_t GVMNowMilliseconds(void) {
    return (uint64_t)(MonotonicNow() * 1000.0);
}

static void GVMEnsureNotifyTokens(void) {
    if (sGoogleNavToken < 0) notify_register_check(kGoogleNavNotify, &sGoogleNavToken);
    if (sGoogleHeartbeatToken < 0) notify_register_check(kGoogleHeartbeatNotify, &sGoogleHeartbeatToken);
    if (sAheadSpeedToken < 0) notify_register_check(kAheadSpeedNotify, &sAheadSpeedToken);
}

static void GVMPublishGoogleHeartbeat(BOOL active) {
#ifdef GVM_RELAY_GOOGLE_PROCESS
    GVMEnsureNotifyTokens();
    if (sGoogleHeartbeatToken >= 0) {
        notify_set_state(sGoogleHeartbeatToken, active ? GVMNowMilliseconds() : 0);
        notify_post(kGoogleHeartbeatNotify);
    }
#else
    (void)active;
#endif
}

static void GVMPublishGoogleNavigation(BOOL active) {
#ifdef GVM_RELAY_GOOGLE_PROCESS
    GVMEnsureNotifyTokens();
    if (sGoogleNavToken >= 0) {
        notify_set_state(sGoogleNavToken, active ? 1 : 0);
        notify_post(kGoogleNavNotify);
    }
#else
    (void)active;
#endif
}

static BOOL GVMGoogleProcessAlive(void) {
    GVMEnsureNotifyTokens();
    uint64_t heartbeat = 0;
    if (sGoogleHeartbeatToken < 0 ||
        notify_get_state(sGoogleHeartbeatToken, &heartbeat) != NOTIFY_STATUS_OK ||
        heartbeat == 0) return NO;
    uint64_t now = GVMNowMilliseconds();
    uint64_t ttl = (uint64_t)(kSharedStateTTL * 1000.0);
    return heartbeat <= now + 1000 && now >= heartbeat && now - heartbeat <= ttl;
}

static void GVMPublishAheadState(NSUInteger limit, NSUInteger distance) {
    GVMEnsureNotifyTokens();
    if (sAheadSpeedToken < 0) return;
    uint64_t now = GVMNowMilliseconds() & 0xFFFFFFFFFFULL;
    uint64_t packed = (now << 24) | ((uint64_t)(limit & 0xFF) << 16) | (uint64_t)(distance & 0xFFFF);
    notify_set_state(sAheadSpeedToken, packed);
    notify_post(kAheadSpeedNotify);
}

static GVMSharedAheadState GVMReadSharedAheadState(void) {
    GVMSharedAheadState result = {0, 0, 0};
    GVMEnsureNotifyTokens();
    uint64_t packed = 0;
    if (sAheadSpeedToken < 0 ||
        notify_get_state(sAheadSpeedToken, &packed) != NOTIFY_STATUS_OK ||
        packed == 0) return result;
    uint64_t stamp = (packed >> 24) & 0xFFFFFFFFFFULL;
    result.limit = (NSUInteger)((packed >> 16) & 0xFF);
    result.distance = (NSUInteger)(packed & 0xFFFF);
    result.updatedAt = (NSTimeInterval)stamp / 1000.0;
    NSTimeInterval age = MonotonicNow() - result.updatedAt;
    if (age < 0 || age > kSharedStateTTL || result.limit > 140 || result.distance > GVM_AHEAD_WARNING_DISTANCE_METERS) {
        result.limit = 0;
        result.distance = 0;
    }
    return result;
}

static void LogRelay(const char *targetIP, int targetPort, const char *buf, size_t len, ssize_t sent, int err) {
    static int logCount = 0;
    if (sent < 0 && (++logCount % 10 != 1)) return; // Debounce errors

    struct timeval tv;
    gettimeofday(&tv, NULL);
    time_t now = tv.tv_sec;
    struct tm tm_info;
    localtime_r(&now, &tm_info);
    char timeStr[40];
    strftime(timeStr, sizeof(timeStr), "%Y-%m-%dT%H:%M:%S%z", &tm_info);
    long long epochMs = (long long)now * 1000LL + (long long)(tv.tv_usec / 1000);

    char cleanBuf[256];
    size_t copyLen = (len < sizeof(cleanBuf) - 1) ? len : sizeof(cleanBuf) - 1;
    memcpy(cleanBuf, buf, copyLen);
    cleanBuf[copyLen] = '\0';
    if (copyLen > 0 && cleanBuf[copyLen - 1] == '\n') cleanBuf[copyLen - 1] = '\0';

    char logLine[512];
    const char *dstIP = targetIP ?: "unknown";
    if (sent >= 0) {
        snprintf(logLine, sizeof(logLine), "[%s][epoch_ms=%lld] [SENT %zdB] %s -> %s:%d\n",
                 timeStr, epochMs, sent, cleanBuf, dstIP, targetPort);
    } else {
        snprintf(logLine, sizeof(logLine), "[%s][epoch_ms=%lld] [FAIL errno=%d (%s)] %s -> %s:%d\n",
                 timeStr, epochMs, err, strerror(err), cleanBuf, dstIP, targetPort);
    }

    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-relay.log"];
    FILE *f = fopen(path.UTF8String, "a");
    if (f) {
        fputs(logLine, f);
        fclose(f);
    }
}

static BOOL IsCandidateUSBInterface(struct ifaddrs *ifa) {
    if (!ifa || !ifa->ifa_name) return NO;
    if (strncmp(ifa->ifa_name, "en", 2) != 0) return NO;
    if (strcmp(ifa->ifa_name, "en0") == 0) return NO; // Skip main Wi-Fi (en0)

    unsigned int flags = ifa->ifa_flags;
    if ((flags & IFF_LOOPBACK) != 0) return NO;
    if ((flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING)) return NO;

    return YES;
}

static unsigned int GetUSBInterfaceIndex(char *outName, size_t maxLen) {
    struct ifaddrs *ifas = NULL;
    if (getifaddrs(&ifas) != 0 || ifas == NULL) {
        return 0;
    }

    char bestName[IFNAMSIZ] = {0};
    int bestScore = 0;

    for (struct ifaddrs *ifa = ifas; ifa != NULL; ifa = ifa->ifa_next) {
        if (!IsCandidateUSBInterface(ifa)) continue;

        int score = 1; // en* (not en0) and IFF_UP | IFF_RUNNING
        if (ifa->ifa_addr) {
            sa_family_t family = ifa->ifa_addr->sa_family;
            if (family == AF_INET) {
                struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
                uint32_t ip = ntohl(sin->sin_addr.s_addr);
                if ((ip & 0xFFFFFF00) == 0xC0A83500) {
                    // IPv4 192.168.53.0/24 -> Definitely Mazda CMU USB link
                    score = 4;
                } else if ((ip & 0xFFFF0000) == 0xA9FE0000) {
                    // APIPA 169.254.0.0/16 -> Standard CarPlay USB-NCM
                    score = 3;
                } else {
                    score = 2;
                }
            } else if (family == AF_INET6 && score < 2) {
                score = 2; // Active IPv6 Link-Local (fe80::)
            }
        }

        if (score > bestScore) {
            bestScore = score;
            strncpy(bestName, ifa->ifa_name, sizeof(bestName) - 1);
            bestName[sizeof(bestName) - 1] = '\0';
        }
    }

    freeifaddrs(ifas);

    if (bestScore > 0 && bestName[0] != '\0') {
        unsigned int idx = if_nametoindex(bestName);
        if (idx > 0) {
            if (outName && maxLen > 0) {
                strncpy(outName, bestName, maxLen - 1);
                outName[maxLen - 1] = '\0';
            }
            return idx;
        }
    }
    return 0;
}

static size_t GetAllActiveUSBInterfaces(unsigned int *outIndices, char outNames[][IFNAMSIZ], size_t maxCount) {
    struct ifaddrs *ifas = NULL;
    if (getifaddrs(&ifas) != 0 || ifas == NULL || maxCount == 0) return 0;

    size_t count = 0;
    for (struct ifaddrs *ifa = ifas; ifa != NULL && count < maxCount; ifa = ifa->ifa_next) {
        if (!IsCandidateUSBInterface(ifa)) continue;

        unsigned int idx = if_nametoindex(ifa->ifa_name);
        if (idx == 0) continue;

        BOOL exists = NO;
        for (size_t i = 0; i < count; i++) {
            if (outIndices[i] == idx) {
                exists = YES;
                break;
            }
        }
        if (!exists) {
            outIndices[count] = idx;
            if (outNames) {
                strncpy(outNames[count], ifa->ifa_name, IFNAMSIZ - 1);
                outNames[count][IFNAMSIZ - 1] = '\0';
            }
            count++;
        }
    }

    freeifaddrs(ifas);
    return count;
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
    if (sSockUSB < 0) {
        sSockUSB = socket(AF_INET, SOCK_DGRAM, 0);
        if (sSockUSB >= 0) {
            int flags = fcntl(sSockUSB, F_GETFL, 0);
            if (flags >= 0) fcntl(sSockUSB, F_SETFL, flags | O_NONBLOCK);
            int opt = 1;
            setsockopt(sSockUSB, SOL_SOCKET, SO_NOSIGPIPE, &opt, sizeof(opt));
            setsockopt(sSockUSB, SOL_SOCKET, SO_BROADCAST, &opt, sizeof(opt));
            if (usbIdx > 0) {
                setsockopt(sSockUSB, IPPROTO_IP, IP_BOUND_IF, &usbIdx, sizeof(usbIdx));
            }
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
    if ((sSock < 0 && sSockUSB < 0 && sSock6 < 0) || !buf || len == 0) return NO;

    BOOL anySent = NO;
    char usbIfName[IFNAMSIZ] = {0};
    unsigned int usbIdx = GetUSBInterfaceIndex(usbIfName, sizeof(usbIfName));

    // Full target list for Mazda CMU
    static const char * const kAllTargets[] = {
        GVM_CMU_HUD_TARGET_IP_USB, // "192.168.53.1" (CMU USB gateway)
        "192.168.53.255",          // (USB subnet broadcast)
        GVM_CMU_HUD_TARGET_IP,     // "192.168.100.1" (CMU Wi-Fi gateway)
        "192.168.100.255",          // (Wi-Fi subnet broadcast)
        GVM_CMU_HUD_TARGET_IP_NCM,  // "169.254.53.1" (OEM-assigned NCM alias)
        "169.254.255.255",         // (USB-NCM APIPA link-local broadcast)
        "255.255.255.255"          // (Global broadcast)
    };
    const size_t kNumTargets = sizeof(kAllTargets) / sizeof(kAllTargets[0]);

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
            if (usbIdx > 0 && IN6_IS_ADDR_LINKLOCAL(&sTarget6.sin6_addr)) {
                sTarget6.sin6_scope_id = usbIdx;
            }
            // en3 is created after the injected process can start. Rebind the
            // already-open IPv6 socket when its interface index becomes live.
            // Without this, scoped cmu.local UDP sends can return EHOSTUNREACH
            // while the same peer still accepts TCP diagnostics.
            if (usbIdx > 0 && sTarget6BoundIf != usbIdx) {
                if (setsockopt(sSock6, IPPROTO_IPV6, IPV6_BOUND_IF,
                               &usbIdx, sizeof(usbIdx)) == 0) {
                    sTarget6BoundIf = usbIdx;
                }
            }
            ssize_t sent = sendto(sSock6, buf, len, 0, (struct sockaddr *)&sTarget6, sizeof(sTarget6));
            int err = (sent < 0) ? errno : 0;
            LogRelay("cmu.local", GVM_CMU_HUD_TARGET_PORT, buf, len, sent, err);
            if (sent >= 0) {
                anySent = YES;
            }
        }
    }

    // 2. Direct send via sSockUSB (Bound directly to active USB-NCM interfaces)
    if (sSockUSB >= 0) {
        int one = 1;
        setsockopt(sSockUSB, SOL_SOCKET, SO_BROADCAST, &one, sizeof(one));
        setsockopt(sSockUSB, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));

        unsigned int activeUSBIndices[8] = {0};
        char activeUSBNames[8][IFNAMSIZ] = {{0}};
        size_t usbCount = GetAllActiveUSBInterfaces(activeUSBIndices, activeUSBNames, 8);
        if (usbCount == 0 && usbIdx > 0) {
            activeUSBIndices[0] = usbIdx;
            strncpy(activeUSBNames[0], usbIfName, IFNAMSIZ - 1);
            usbCount = 1;
        }

        size_t loopCount = (usbCount > 0) ? usbCount : 1;
        for (size_t u = 0; u < loopCount; u++) {
            if (usbCount > 0) {
                unsigned int bindIdx = activeUSBIndices[u];
                // Dynamic re-bind to handle cable disconnect/reconnect cleanly
                setsockopt(sSockUSB, IPPROTO_IP, IP_BOUND_IF, &bindIdx, sizeof(bindIdx));
            }

            for (size_t i = 0; i < kNumTargets; i++) {
                struct sockaddr_in dstUSB;
                memset(&dstUSB, 0, sizeof(dstUSB));
                dstUSB.sin_family = AF_INET;
                dstUSB.sin_port = htons(GVM_CMU_HUD_TARGET_PORT);
                if (inet_pton(AF_INET, kAllTargets[i], &dstUSB.sin_addr) != 1) continue;

                ssize_t sent = sendto(sSockUSB, buf, len, 0, (struct sockaddr *)&dstUSB, sizeof(dstUSB));
                int err = (sent < 0) ? errno : 0;

                // Off-subnet bypass on XNU: force packet down USB link with MSG_DONTROUTE
                if (sent < 0 && (err == ENETUNREACH || err == EHOSTUNREACH || err == EADDRNOTAVAIL)) {
                    sent = sendto(sSockUSB, buf, len, MSG_DONTROUTE, (struct sockaddr *)&dstUSB, sizeof(dstUSB));
                    err = (sent < 0) ? errno : 0;
                }

                LogRelay(kAllTargets[i], GVM_CMU_HUD_TARGET_PORT, buf, len, sent, err);
                if (sent >= 0) {
                    anySent = YES;
                }
            }
        }
    }

    // 3. Send via sSock (Unbound / Wi-Fi fallback)
    if (sSock >= 0) {
        int one = 1;
        setsockopt(sSock, SOL_SOCKET, SO_BROADCAST, &one, sizeof(one));
        setsockopt(sSock, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));

        for (size_t i = 0; i < kNumTargets; i++) {
            struct sockaddr_in dst;
            memset(&dst, 0, sizeof(dst));
            dst.sin_family = AF_INET;
            dst.sin_port = htons(GVM_CMU_HUD_TARGET_PORT);
            if (inet_pton(AF_INET, kAllTargets[i], &dst.sin_addr) != 1) continue;

            ssize_t sent = sendto(sSock, buf, len, 0, (struct sockaddr *)&dst, sizeof(dst));
            int err = (sent < 0) ? errno : 0;
            if (sent < 0 && (err == ENETUNREACH || err == EHOSTUNREACH)) {
                sent = sendto(sSock, buf, len, MSG_DONTROUTE, (struct sockaddr *)&dst, sizeof(dst));
                err = (sent < 0) ? errno : 0;
            }

            LogRelay(kAllTargets[i], GVM_CMU_HUD_TARGET_PORT, buf, len, sent, err);
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
static void SendTimeSync(void);
static void SendLimit(NSUInteger limitKmh) {
    if (sLastSyncSend == 0) SendTimeSync();
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "LIMIT %lu\n", (unsigned long)limitKmh);
    if (n > 0 && (size_t)n < sizeof(buf)) {
        SendDatagram(buf, (size_t)n);
        sLastSend = MonotonicNow();
    }
}

static void SendTimeSync(void) {
    NSTimeInterval nowMono = MonotonicNow();
    long long epochMs = (long long)([NSDate date].timeIntervalSince1970 * 1000.0);
    unsigned long long monoMs = (unsigned long long)(nowMono * 1000.0);
    char buf[96];
    int n = snprintf(buf, sizeof(buf), "SYNC %lld %llu\n", epochMs, monoMs);
    if (n > 0 && (size_t)n < sizeof(buf)) {
        sLastSyncSend = nowMono;
        (void)SendDatagram(buf, (size_t)n);
    }
}

// Format and send "NAV <icon_id> <dist_m> <road_name>\n".
static void SendNav(NSUInteger iconID, NSUInteger distM, NSString *road) {
    if (!road) road = @"";
    // Keep UTF-8: the CMU-side HUD sender normalizes only glyphs absent from
    // the Mazda font, so renderable Vietnamese marks must survive this hop.
    NSString *safe = [road stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    safe = [safe stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    if (safe.length > 128) safe = [safe substringToIndex:128];
    if (![safe dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO]) return;
    char buf[512];
    int n = snprintf(buf, sizeof(buf), "NAV %lu %lu %s\n",
                     (unsigned long)iconID, (unsigned long)distM,
                     safe.UTF8String ?: "");
    if (n > 0 && (size_t)n < sizeof(buf)) {
        SendDatagram(buf, (size_t)n);
        sLastNavSend = MonotonicNow();
    }
}

static BOOL AheadActive(void) {
    GVMRefreshSharedAheadState();
    return sAheadLimit >= 5 && sAheadLimit <= 140 &&
           sAheadDist > 0 && sAheadDist <= GVM_AHEAD_WARNING_DISTANCE_METERS &&
           sCurrentLimit >= 5 && sAheadLimit < sCurrentLimit;
}

static BOOL GVMRefreshSharedAheadState(void) {
#ifdef GVM_RELAY_GOOGLE_PROCESS
    GVMSharedAheadState shared = GVMReadSharedAheadState();
    BOOL changed = (sAheadLimit != shared.limit || sAheadDist != shared.distance);
    sAheadLimit = shared.limit;
    sAheadDist = shared.distance;
    return changed;
#else
    return NO;
#endif
}

// Merge the optional VietMap warning with the actual Google maneuver. When
// Google is not navigating, use a flag + the requested Vietnamese warning text;
// when Google is navigating, keep its icon/distance and decorate only the road
// strip so the turn instruction remains authoritative.
static void SendEffectiveNav(void) {
    // Google Maps owns the maneuver channel. VietMap may publish the compact
    // warning only while Google is idle; it never forwards its own arrow.
#if defined(GVM_RELAY_VIETMAP_SOURCE)
    if (GVMGoogleProcessAlive()) return;
#endif
    if (sNavIcon > 0) {
        NSString *road = sNavRoad ?: @"";
        if (AheadActive()) {
            road = [NSString stringWithFormat:@"[%lu/%lum] %@",
                    (unsigned long)sAheadLimit, (unsigned long)sAheadDist, road];
        }
        SendNav(sNavIcon, sNavDist, road);
    } else if (AheadActive()) {
        NSString *warning = [NSString stringWithFormat:@"Max %lu km/h",
                             (unsigned long)sAheadLimit];
        SendNav(kAheadWarningIcon, sAheadDist, warning);
    } else {
        SendNav(0, 0, @"");
    }
}

static void HeartbeatTick(void) {
    @synchronized(sLock) {
        BOOL sharedAheadChanged = NO;
#if defined(GVM_RELAY_GOOGLE_PROCESS)
        GVMPublishGoogleHeartbeat(YES);
        sharedAheadChanged = GVMRefreshSharedAheadState();
#endif
        if (sSock < 0) return;
        NSTimeInterval now = MonotonicNow();
        if (sLastSyncSend == 0 || now - sLastSyncSend >= 60.0) {
            SendTimeSync();
        }
        // Heartbeat: resend current limit every 2.5s if it's active (> 0).
        if (sCurrentLimit > 0) {
            if (now - sLastSend >= kHeartbeatInterval) {
                SendLimit(sCurrentLimit);
            }
        }
        // Heartbeat: resend the active Google maneuver or the 500 m warning.
        if (sharedAheadChanged || sNavIcon > 0 || AheadActive()) {
            if (sharedAheadChanged || now - sLastNavSend >= kHeartbeatInterval) {
                SendEffectiveNav();
            }
        }
    }
}

// ── Public API ─────────────────────────────────────────────────────────────

void GVMCMURelayStart(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sLock = [NSObject new]; });

    @synchronized(sLock) {
        GVMEnsureNotifyTokens();
#if defined(GVM_RELAY_VIETMAP_SOURCE)
        sAheadLimit = 0;
        sAheadDist = 0;
        GVMPublishAheadState(0, 0);
        return;
#else
        if (sSock >= 0) {
            GVMPublishGoogleHeartbeat(YES);
            return; // Already started
        }
#endif

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
        sLastSyncSend = 0;
        sNavIcon = 0;
        sNavDist = 0;
        sNavRoad = nil;
        sAheadLimit = 0;
        sAheadDist = 0;
#if defined(GVM_RELAY_GOOGLE_PROCESS)
        GVMRefreshSharedAheadState();
        GVMPublishGoogleHeartbeat(YES);
        GVMPublishGoogleNavigation(NO);
#endif

        // Heartbeat timer on main queue, fires every 1s (checks internally
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
#if defined(GVM_RELAY_VIETMAP_SOURCE)
        sCurrentLimit = limitKmh;
        return;
#else
        EnsureSocketOpen();

        BOOL changed = (sCurrentLimit != limitKmh);
        sCurrentLimit = limitKmh;

        if (changed || !sLimitSentOnce) {
            SendLimit(limitKmh);
            sLimitSentOnce = YES;
        }
        // A changed current limit can make the upcoming reduction eligible or
        // ineligible; repaint the road strip/warning without touching the turn.
        if (changed && (sNavIcon > 0 || sAheadLimit > 0 || AheadActive())) {
            SendEffectiveNav();
        }
#endif
    }
}

void GVMCMURelaySetUpcomingSpeed(NSUInteger limitKmh, NSUInteger distanceMeters) {
    @synchronized(sLock) {
        if (limitKmh < 5 || limitKmh > 140 || distanceMeters == 0 ||
            distanceMeters > GVM_AHEAD_WARNING_DISTANCE_METERS) {
            limitKmh = 0;
            distanceMeters = 0;
        }
#if defined(GVM_RELAY_VIETMAP_SOURCE)
        sAheadLimit = limitKmh;
        sAheadDist = distanceMeters;
        GVMPublishAheadState(limitKmh, distanceMeters);
        // The source process publishes shared state only. Google Maps is the
        // single writer of LIMIT/NAV datagrams to the CMU.
        return;
#else
        BOOL changed = (sAheadLimit != limitKmh) || (sAheadDist != distanceMeters);
        BOOL hadAhead = (sAheadLimit > 0 || sAheadDist > 0);
        sAheadLimit = limitKmh;
        sAheadDist = distanceMeters;
        GVMRefreshSharedAheadState();
        if (!changed) return;
        if (sNavIcon > 0 || hadAhead || AheadActive()) {
            SendEffectiveNav();
        }
#endif
    }
}

void GVMCMURelaySetNav(NSUInteger iconID, NSUInteger distanceMeters, NSString *roadName) {
    @synchronized(sLock) {
#if defined(GVM_RELAY_VIETMAP_SOURCE)
        (void)iconID;
        (void)distanceMeters;
        (void)roadName;
        return;
#else
        EnsureSocketOpen();
        if (sLastSyncSend == 0) SendTimeSync();

        NSString *safeRoad = roadName ?: @"";

        // A zero icon ends Google navigation. Restore the independent VietMap
        // warning immediately if it is still inside the 500 m window.
        if (iconID == 0) {
            GVMPublishGoogleNavigation(NO);
            BOOL hadDisplayedNav = (sNavIcon > 0);
            sNavIcon = 0;
            sNavDist = 0;
            sNavRoad = @"";
            if (hadDisplayedNav) {
                SendEffectiveNav();
            }
            return;
        }

        BOOL changed = (sNavIcon != iconID) ||
                       (sNavDist != distanceMeters) ||
                       ![sNavRoad isEqualToString:safeRoad];
        if (!changed) {
            return;
        }

        sNavIcon = iconID;
        sNavDist = distanceMeters;
        sNavRoad = [safeRoad copy];
        GVMPublishGoogleNavigation(YES);
        SendEffectiveNav();
#endif
    }
}

void GVMCMURelayStop(void) {
    @synchronized(sLock) {
#if defined(GVM_RELAY_VIETMAP_SOURCE)
        GVMPublishAheadState(0, 0);
        sAheadLimit = 0;
        sAheadDist = 0;
        return;
#else
        GVMPublishGoogleHeartbeat(NO);
        GVMPublishGoogleNavigation(NO);
#endif
        if (sTimer) {
            dispatch_source_cancel(sTimer);
            sTimer = nil;
        }
        if (sSock >= 0 || sSockUSB >= 0 || sSock6 >= 0) {
            // Send final "LIMIT 0" and clear both navigation and ahead warning.
            SendLimit(0);
            sCurrentLimit = 0;
            sAheadLimit = 0;
            sAheadDist = 0;
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
                sTarget6Resolved = NO;
                sTarget6BoundIf = 0;
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
