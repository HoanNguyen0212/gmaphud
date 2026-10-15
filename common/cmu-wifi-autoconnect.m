#import "cmu-wifi-autoconnect.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <dlfcn.h>
#include <time.h>

// ── MobileWiFi private function pointers ───────────────────────────────────
typedef void *WiFiManagerClientRef;
typedef void *WiFiDeviceClientRef;
typedef void *WiFiNetworkRef;

typedef WiFiManagerClientRef (*WiFiManagerClientCreateFunc)(CFAllocatorRef allocator, int flags);
typedef CFArrayRef (*WiFiManagerClientCopyDevicesFunc)(WiFiManagerClientRef manager);
typedef CFArrayRef (*WiFiDeviceClientCopyNetworksFunc)(WiFiDeviceClientRef device);
typedef CFStringRef (*WiFiNetworkGetSSIDFunc)(WiFiNetworkRef network);
typedef int (*WiFiDeviceClientAssociateAsyncFunc)(WiFiDeviceClientRef device, WiFiNetworkRef network, void *callback, void *context);

// ── Internal State ─────────────────────────────────────────────────────────
static BOOL sCarPlayConnected = NO;
static NSTimeInterval sLastAttemptTime = 0;
static NSUInteger sAttemptCount = 0;
static const NSTimeInterval kAttemptCooldown = 10.0; // 10 seconds between attempts
static const NSUInteger kMaxAttemptsPerSession = 5;  // Do not thrash Wi-Fi chip

// ── Logging Helper ─────────────────────────────────────────────────────────
static void LogWiFi(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    char timeStr[32];
    strftime(timeStr, sizeof(timeStr), "%H:%M:%S", tm_info);

    NSString *logLine = [NSString stringWithFormat:@"[%s] [WIFI-AUTO] %@\n", timeStr, msg];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-wifi.log"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    if ([attrs fileSize] > 32768) {
        [fm removeItemAtPath:path error:nil];
    }
    FILE *f = fopen(path.UTF8String, "a");
    if (f) {
        fputs(logLine.UTF8String, f);
        fclose(f);
    }
}

// ── BSD Network Query ──────────────────────────────────────────────────────
BOOL GVMCMUIsMazdaWiFiConnected(void) {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return NO;
    BOOL connected = NO;
    for (struct ifaddrs *ifa = interfaces; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
        if (strcmp(ifa->ifa_name, "en0") != 0) continue;

        struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
        char ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &(sa->sin_addr), ip, INET_ADDRSTRLEN);

        // Mazda CMU Access Point assigns IPs in 192.168.100.x subnet
        if (strncmp(ip, "192.168.100.", 12) == 0) {
            connected = YES;
            break;
        }
    }
    freeifaddrs(interfaces);
    return connected;
}

// ── SpringBoard SBWiFiManager Bridge ────────────────────────────────────────
static id GetSBWiFiManager(void) {
    Class cls = NSClassFromString(@"SBWiFiManager");
    if (!cls) return nil;
    SEL selShared = NSSelectorFromString(@"sharedInstance");
    if (![cls respondsToSelector:selShared]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, selShared);
}

NSString * _Nullable GVMCMUWiFiCurrentSSID(void) {
    id mgr = GetSBWiFiManager();
    if (!mgr) return nil;
    SEL selCurrent = NSSelectorFromString(@"currentNetworkName");
    if ([mgr respondsToSelector:selCurrent]) {
        id name = ((id (*)(id, SEL))objc_msgSend)(mgr, selCurrent);
        if ([name isKindOfClass:[NSString class]]) return (NSString *)name;
    }
    return nil;
}

static BOOL EnsureWiFiPowerOn(void) {
    id mgr = GetSBWiFiManager();
    if (!mgr) return NO;
    SEL selEnabled = NSSelectorFromString(@"isWiFiEnabled");
    SEL selSetEnabled = NSSelectorFromString(@"setWiFiEnabled:");
    if ([mgr respondsToSelector:selEnabled] && [mgr respondsToSelector:selSetEnabled]) {
        BOOL isEnabled = ((BOOL (*)(id, SEL))objc_msgSend)(mgr, selEnabled);
        if (!isEnabled) {
            LogWiFi(@"Wi-Fi was disabled, powering ON for CarPlay session...");
            ((void (*)(id, SEL, BOOL))objc_msgSend)(mgr, selSetEnabled, YES);
            return YES;
        }
    }
    return NO;
}

// ── MobileWiFi Scanning & Association ──────────────────────────────────────
static BOOL AssociateWithMazdaAP(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_NOW);
    if (!handle) {
        LogWiFi(@"Failed to open MobileWiFi.framework");
        return NO;
    }

    WiFiManagerClientCreateFunc fnCreate = (WiFiManagerClientCreateFunc)dlsym(handle, "WiFiManagerClientCreate");
    WiFiManagerClientCopyDevicesFunc fnCopyDevices = (WiFiManagerClientCopyDevicesFunc)dlsym(handle, "WiFiManagerClientCopyDevices");
    WiFiDeviceClientCopyNetworksFunc fnCopyNetworks = (WiFiDeviceClientCopyNetworksFunc)dlsym(handle, "WiFiDeviceClientCopyNetworks");
    WiFiNetworkGetSSIDFunc fnGetSSID = (WiFiNetworkGetSSIDFunc)dlsym(handle, "WiFiNetworkGetSSID");
    WiFiDeviceClientAssociateAsyncFunc fnAssociate = (WiFiDeviceClientAssociateAsyncFunc)dlsym(handle, "WiFiDeviceClientAssociateAsync");

    if (!fnCreate || !fnCopyDevices || !fnCopyNetworks || !fnGetSSID || !fnAssociate) {
        LogWiFi(@"Missing MobileWiFi symbols");
        dlclose(handle);
        return NO;
    }

    WiFiManagerClientRef manager = fnCreate(kCFAllocatorDefault, 0);
    if (!manager) {
        dlclose(handle);
        return NO;
    }

    BOOL associated = NO;
    CFArrayRef devices = fnCopyDevices(manager);
    if (devices) {
        CFIndex devCount = CFArrayGetCount(devices);
        for (CFIndex i = 0; i < devCount; i++) {
            WiFiDeviceClientRef device = (WiFiDeviceClientRef)CFArrayGetValueAtIndex(devices, i);
            CFArrayRef networks = fnCopyNetworks(device);
            if (networks) {
                CFIndex netCount = CFArrayGetCount(networks);
                for (CFIndex j = 0; j < netCount; j++) {
                    WiFiNetworkRef net = (WiFiNetworkRef)CFArrayGetValueAtIndex(networks, j);
                    CFStringRef ssid = fnGetSSID(net);
                    if (ssid) {
                        NSString *s = (__bridge NSString *)ssid;
                        // Match any Mazda Wi-Fi Access Point (e.g. Mazda_Connect_..., mazda, etc.)
                        if ([s rangeOfString:@"mazda" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                            LogWiFi(@"Found Mazda Wi-Fi AP '%@', triggering associate...", s);
                            int ret = fnAssociate(device, net, NULL, NULL);
                            LogWiFi(@"Associate request returned code: %d", ret);
                            associated = YES;
                            break;
                        }
                    }
                }
                CFRelease(networks);
            }
            if (associated) break;
        }
        CFRelease(devices);
    }
    CFRelease(manager);
    dlclose(handle);
    return associated;
}

// ── Public API ─────────────────────────────────────────────────────────────

BOOL GVMCMUIsCarPlayActive(void) {
    return sCarPlayConnected;
}

void GVMCMUOnCarPlayConnectionChanged(BOOL connected) {
    if (sCarPlayConnected == connected) return;
    sCarPlayConnected = connected;

    if (connected) {
        LogWiFi(@"CarPlay connected (vehicle detected). Starting auto-connect pipeline.");
        sAttemptCount = 0;
        sLastAttemptTime = 0;
        // Immediate check & trigger
        GVMCMUWiFiAutoConnectTick();
    } else {
        LogWiFi(@"CarPlay disconnected (vehicle detached). Returning to default state.");
        // SAFETY: When Sếp unplugs and goes home, Wi-Fi stays normal (no force-disconnect).
        sAttemptCount = 0;
        sLastAttemptTime = 0;
    }
}

void GVMCMUWiFiAutoConnectTick(void) {
    // CRITICAL SAFETY CHECK:
    // If CarPlay is NOT connected (e.g. charging at home, on PC, wall charger),
    // do ABSOLUTELY NOTHING. Zero interference with home Wi-Fi!
    if (!sCarPlayConnected) return;

    // If Mazda subnet 192.168.100.x is already reachable, we are good!
    if (GVMCMUIsMazdaWiFiConnected()) return;

    // Check currently connected SSID
    NSString *currentSSID = GVMCMUWiFiCurrentSSID();
    if (currentSSID && [currentSSID rangeOfString:@"mazda" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        // Already associated, awaiting DHCP lease
        return;
    }

    // Rate limiting: cooldown between attempts & max retry clamp
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - sLastAttemptTime < kAttemptCooldown) return;
    if (sAttemptCount >= kMaxAttemptsPerSession) return;

    sLastAttemptTime = now;
    sAttemptCount++;

    LogWiFi(@"Auto-connect attempt #%lu/%lu (Current SSID: %@)",
            (unsigned long)sAttemptCount, (unsigned long)kMaxAttemptsPerSession, currentSSID ?: @"None");

    // 1. Ensure Wi-Fi chip is powered on
    EnsureWiFiPowerOn();

    // 2. Scan and associate with Mazda Access Point
    AssociateWithMazdaAP();
}

void GVMCMUWiFiAutoConnectStart(void) {
    sCarPlayConnected = NO;
    sAttemptCount = 0;
    sLastAttemptTime = 0;
    LogWiFi(@"GVMCMUWiFiAutoConnect initialized.");
}

void GVMCMUWiFiAutoConnectStop(void) {
    sCarPlayConnected = NO;
    sAttemptCount = 0;
    sLastAttemptTime = 0;
    LogWiFi(@"GVMCMUWiFiAutoConnect stopped.");
}
