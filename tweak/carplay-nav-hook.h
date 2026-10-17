#import <Foundation/Foundation.h>
#include <stdint.h>

// Installs CarPlay navigation hooks inside Google Maps
void GVMInstallCarPlayNavHook(void);

// Helper for mapping Apple CarPlay maneuverType to Mazda HUD turn icon code (exposed for tests)
uint16_t GVMMapCarPlayManeuverToMazdaHUD(NSUInteger maneuverType);

// Helper for stripping Vietnamese diacritics for Mazda CMU HUD font compatibility (exposed for tests)
NSString *GVMStripVietnameseDiacritics(NSString *str);

// Normalizes Vietnamese characters to renderable 2-byte Latin-Extended equivalents (â, ê, ô, ă, ư, ơ, đ)
NSString *GVMNormalizeVietnameseForHUD(NSString *str);

// Helper for extracting clean road name from turn instruction (exposed for tests)
NSString *GVMExtractRoadName(NSString *str);
