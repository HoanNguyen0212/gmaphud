export THEOS_PACKAGE_SCHEME ?= rootless
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
THEOS_PACKAGE_ARCH = iphoneos-arm64
else
THEOS_PACKAGE_ARCH = iphoneos-arm
endif
TARGET = iphone:clang:16.5:14.0
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = VietMapGoogleMapsSource GoogleMapsVietMap GMapHUDPlacementRelay
VietMapGoogleMapsSource_FILES = diagnostics.m vietmap-source.x nav-source.m nav-payload.m speed-state.m alert-state.m vietmap-alert-assets.m
VietMapGoogleMapsSource_CFLAGS = -fobjc-arc -DVM_GOOGLE_MAPS_RELAY=1
VietMapGoogleMapsSource_FRAMEWORKS = UIKit Foundation
GoogleMapsVietMap_FILES = phone-overlay.m diagnostics.m google-hook.m carplay-style.m speed-presentation.m speed-state.m alert-state.m vietmap-alert-assets.m test-state.m placement-state.m
GoogleMapsVietMap_CFLAGS = -fobjc-arc -Wall -Wextra
GoogleMapsVietMap_FRAMEWORKS = UIKit Foundation
GoogleMapsVietMap_LIBRARIES = substrate
GMapHUDPlacementRelay_FILES = placement-relay.m placement-state.m background-supervisor.m
GMapHUDPlacementRelay_CFLAGS = -fobjc-arc -Wall -Wextra
GMapHUDPlacementRelay_FRAMEWORKS = Foundation CoreLocation
include $(THEOS)/makefiles/tweak.mk

BUNDLE_NAME = GMapHUDPrefs
GMapHUDPrefs_FILES = diagnostics.m prefs/diagnostics-controller.m prefs/preferences-controller.m placement-state.m
GMapHUDPrefs_CFLAGS = -fobjc-arc -Wall -Wextra
GMapHUDPrefs_FRAMEWORKS = Foundation UIKit
GMapHUDPrefs_PRIVATE_FRAMEWORKS = Preferences
GMapHUDPrefs_INSTALL_PATH = /Library/PreferenceBundles
GMapHUDPrefs_RESOURCE_DIRS = prefs/Resources
include $(THEOS)/makefiles/bundle.mk

TOOL_NAME = gvm-test-speed
gvm-test-speed_FILES = placement-state.m test-speed.m test-state.m alert-state.m vietmap-alert-assets.m
gvm-test-speed_CFLAGS = -fobjc-arc -Wall -Wextra
gvm-test-speed_FRAMEWORKS = Foundation
gvm-test-speed_INSTALL_PATH = /usr/bin
include $(THEOS)/makefiles/tool.mk
