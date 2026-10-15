#ifndef GVM_CMU_WIFI_AUTOCONNECT_H
#define GVM_CMU_WIFI_AUTOCONNECT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Checks whether the iPhone interface en0 currently has an IP address
 * in the Mazda CMU subnet (192.168.100.0/24).
 * Thread-safe, non-blocking BSD socket query.
 */
BOOL GVMCMUIsMazdaWiFiConnected(void);

/**
 * Notifies the auto-connect supervisor of a CarPlay session state change.
 * MUST be invoked on the main queue / thread.
 * 
 * @param connected YES if CarPlay session is actively connected (cable or wireless).
 *                  NO if CarPlay is disconnected or phone is unplugged.
 * 
 * Safety: If connected == NO (e.g. charging at home), the auto-connect
 * logic is 100% inert and NEVER interferes with home/work Wi-Fi.
 */
void GVMCMUOnCarPlayConnectionChanged(BOOL connected);

/**
 * Periodic tick called by the supervisor loop on the main queue.
 * Only performs work if CarPlay is actively connected AND Mazda Wi-Fi is not yet up.
 */
void GVMCMUWiFiAutoConnectTick(void);

/**
 * Starts / stops the auto-connector subsystem.
 */
void GVMCMUWiFiAutoConnectStart(void);
void GVMCMUWiFiAutoConnectStop(void);

/**
 * Returns YES if CarPlay is currently marked active by the supervisor.
 */
BOOL GVMCMUIsCarPlayActive(void);

/**
 * Returns the currently associated SSID (or nil if none/disabled).
 */
NSString * _Nullable GVMCMUWiFiCurrentSSID(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

#endif // GVM_CMU_WIFI_AUTOCONNECT_H
