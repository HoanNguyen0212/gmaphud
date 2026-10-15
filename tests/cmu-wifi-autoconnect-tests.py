"""Tests for the Mazda CMU Wi-Fi Auto-Connect supervisor module (cmu-wifi-autoconnect)."""
from pathlib import Path
import re
import unittest

root = Path(__file__).resolve().parents[1]


class CMUWiFiAutoConnectSourceTests(unittest.TestCase):
    """Validate the cmu-wifi-autoconnect.h/.m source contracts and integration offline."""

    def setUp(self):
        self.header = (root / "common/cmu-wifi-autoconnect.h").read_text()
        self.impl = (root / "common/cmu-wifi-autoconnect.m").read_text()
        self.supervisor = (root / "tweak/background-supervisor.m").read_text()
        self.makefile = (root / "tweak/Makefile").read_text()
        self.build_sh = (root / "build-tweak.sh").read_text()

    def test_header_declares_all_public_functions(self):
        expected_functions = [
            "GVMCMUIsMazdaWiFiConnected",
            "GVMCMUOnCarPlayConnectionChanged",
            "GVMCMUWiFiAutoConnectTick",
            "GVMCMUWiFiAutoConnectStart",
            "GVMCMUWiFiAutoConnectStop",
            "GVMCMUIsCarPlayActive",
            "GVMCMUWiFiCurrentSSID",
        ]
        for func in expected_functions:
            self.assertIn(func, self.header, f"{func} missing from header")

    def test_impl_defines_all_public_functions(self):
        expected_functions = [
            "GVMCMUIsMazdaWiFiConnected",
            "GVMCMUOnCarPlayConnectionChanged",
            "GVMCMUWiFiAutoConnectTick",
            "GVMCMUWiFiAutoConnectStart",
            "GVMCMUWiFiAutoConnectStop",
            "GVMCMUIsCarPlayActive",
            "GVMCMUWiFiCurrentSSID",
        ]
        for func in expected_functions:
            pattern = rf"\b{func}\s*\("
            self.assertRegex(self.impl, pattern, f"{func} definition missing from impl")

    def test_home_charging_safety_guard(self):
        """Must bail out immediately if CarPlay is not actively connected."""
        self.assertIn("if (!sCarPlayConnected) return;", self.impl,
                      "Critical safety guard missing: tick must return if not in CarPlay")

    def test_bsd_subnet_verification(self):
        """Verifies interface en0 and 192.168.100. subnet via getifaddrs."""
        self.assertIn("getifaddrs", self.impl)
        self.assertIn('"en0"', self.impl)
        self.assertIn('"192.168.100."', self.impl)
        self.assertIn("freeifaddrs", self.impl)

    def test_rate_limiting_and_retry_caps(self):
        """Verifies attempt cooldown and session retry limits to protect battery/chip."""
        self.assertIn("kAttemptCooldown", self.impl)
        self.assertIn("kMaxAttemptsPerSession", self.impl)
        self.assertIn("sAttemptCount >= kMaxAttemptsPerSession", self.impl)

    def test_dynamic_mobilewifi_loading_and_cfrelease(self):
        """Verifies dlopen of MobileWiFi.framework and proper CoreFoundation memory cleanup."""
        self.assertIn("MobileWiFi.framework", self.impl)
        self.assertIn("dlopen", self.impl)
        self.assertIn("dlclose", self.impl)
        self.assertIn("CFRelease(devices)", self.impl)
        self.assertIn("CFRelease(networks)", self.impl)
        self.assertIn("CFRelease(manager)", self.impl)

    def test_case_insensitive_mazda_ssid_match(self):
        """Must match 'mazda' case-insensitively."""
        self.assertIn('@"mazda"', self.impl)
        self.assertIn("NSCaseInsensitiveSearch", self.impl)

    def test_background_supervisor_integration(self):
        """Validates that background-supervisor imports and drives the Wi-Fi auto-connect lifecycle."""
        self.assertIn('#import "cmu-wifi-autoconnect.h"', self.supervisor)
        self.assertIn("GVMCMUOnCarPlayConnectionChanged(connected)", self.supervisor)
        self.assertIn("GVMCMUWiFiAutoConnectTick()", self.supervisor)
        self.assertIn("GVMCMUWiFiAutoConnectStart()", self.supervisor)

    def test_build_system_packaging(self):
        """Ensures the auto-connect files are included in the tweak build and makefile."""
        self.assertIn("cmu-wifi-autoconnect.[mh]", self.build_sh)
        self.assertIn("cmu-wifi-autoconnect.m", self.makefile)


if __name__ == "__main__":
    unittest.main()
