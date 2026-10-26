#import <Foundation/Foundation.h>
#include <stdint.h>

// Mazda CMU HUD relay — non-blocking UDP to cmu_splim_listener on 192.168.100.1:8888.
// Protocol:
//   "LIMIT <kmh>\n"  — speed limit (0 = no limit / cleared)
//   "NAV <icon_id> <dist_m> <road_name>\n" — navigation maneuver
//   "SYNC <epoch_ms> <phone_monotonic_ms>\n" — time anchor for CMU logs
//
// Thread-safe. Sends immediately on value change, heartbeats every 2.5s if
// the limit is still active. Sends "LIMIT 0\n" once when cleared.
// Zero-copy, non-blocking, no allocations on the hot path.

// Call once at startup. Creates the UDP socket and heartbeat timer.
void GVMCMURelayStart(void);

// Call on every speed-limit update from any source (value 0 means cleared).
void GVMCMURelaySetLimit(NSUInteger limitKmh);

// Call on navigation maneuver updates. Pass 0 for iconID / distanceM to clear.
void GVMCMURelaySetNav(NSUInteger iconID, NSUInteger distanceMeters, NSString *roadName);

// Tear down the socket and timer. Safe to call multiple times.
void GVMCMURelayStop(void);

// Test-only: return the last datagram sent (nil if none). Thread-safe.
NSString *GVMCMURelayLastDatagram(void);
