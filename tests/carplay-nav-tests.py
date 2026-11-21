"""Tests for CarPlay Navigation Hook (carplay-nav-hook.[mh]) and Mazda HUD Mapping."""
import os
from pathlib import Path
import re
import unittest

root = Path(__file__).resolve().parents[1]


class CarPlayNavHookSourceTests(unittest.TestCase):
    """Validate carplay-nav-hook.h/.m contract, maneuver mapping, and diacritics handling."""

    def setUp(self):
        self.header = (root / "tweak/carplay-nav-hook.h").read_text()
        self.impl = (root / "tweak/carplay-nav-hook.m").read_text()
        self.google_hook = (root / "tweak/google-hook.m").read_text()
        self.makefile = (root / "tweak/Makefile").read_text()

    def test_header_exports(self):
        self.assertIn("GVMInstallCarPlayNavHook", self.header)
        self.assertIn("GVMMapCarPlayManeuverToMazdaHUD", self.header)
        self.assertIn("GVMStripVietnameseDiacritics", self.header)
        self.assertIn("GVMNormalizeVietnameseForHUD", self.header)
        self.assertIn("GVMExtractRoadName", self.header)

    def test_installed_in_google_hook(self):
        self.assertIn('#import "carplay-nav-hook.h"', self.google_hook)
        self.assertIn("GVMInstallCarPlayNavHook();", self.google_hook)

    def test_added_to_makefile(self):
        self.assertIn("carplay-nav-hook.m", self.makefile)

    def test_handles_dlopen_carplay_framework(self):
        self.assertIn("dlopen", self.impl)
        self.assertIn("CarPlay.framework/CarPlay", self.impl)

    def test_hooks_cp_navigation_session(self):
        self.assertIn("CPNavigationSession", self.impl)
        self.assertIn("updateTravelEstimates:forManeuver:", self.impl)
        self.assertIn("setManeuvers:", self.impl)
        self.assertIn("finishTrip", self.impl)
        self.assertIn("cancelTrip", self.impl)
        self.assertIn("pauseTripForReason:description:", self.impl)

    def test_maneuver_mapping_coverage(self):
        self.assertIn("GVMMapCarPlayManeuverToMazdaHUD", self.impl)
        self.assertIn("case 1:  return 2;", self.impl)
        self.assertIn("case 2:  return 3;", self.impl)
        self.assertIn("case 3:  return 1;", self.impl)
        self.assertIn("case 4:", self.impl)
        self.assertIn("case 26: return 13;", self.impl)
        self.assertIn("case 8:  return 7;", self.impl)
        self.assertIn("case 9:  return 16;", self.impl)
        self.assertIn("case 10:", self.impl)
        self.assertIn("case 27: return 8;", self.impl)
        self.assertIn("type >= 28 && type <= 46", self.impl)

    def test_vietnamese_diacritic_handling(self):
        self.assertIn("CFStringTransform", self.impl)
        self.assertIn("kCFStringTransformStripCombiningMarks", self.impl)
        self.assertIn('@"đ"', self.impl)
        self.assertIn('@"d"', self.impl)
        self.assertIn('@"Đ"', self.impl)
        self.assertIn('@"D"', self.impl)

    def test_relay_call_non_blocking(self):
        self.assertIn("GVMCMURelaySetNav", self.impl)
        self.assertIn("@try", self.impl)
        self.assertIn("@catch", self.impl)

    def test_detects_turns_from_symbol_image_and_variants(self):
        self.assertIn("GVMDetectIconFromImage", self.impl)
        self.assertIn("GVMExtractUIImage", self.impl)
        self.assertIn("symbolSet", self.impl)
        self.assertIn("symbolImage", self.impl)
        self.assertIn("dashboardSymbolImage", self.impl)
        self.assertIn("instructionVariants", self.impl)
        self.assertIn("dashboardInstructionVariants", self.impl)
        self.assertIn("notificationInstructionVariants", self.impl)
        self.assertIn("turn_left", self.impl)
        self.assertIn("turn_right", self.impl)
        self.assertIn("arrow_left", self.impl)
        self.assertIn("arrow_right", self.impl)
        self.assertIn("⬅", self.impl)
        self.assertIn("➡", self.impl)

    def test_actual_carplay_symbol_is_preferred_before_text(self):
        image_marker = self.impl.index('// 0. Prefer the actual CarPlay maneuver symbol')
        text_marker = self.impl.index('// 1. Gather all potential text sources')
        self.assertLess(image_marker, text_marker)


if __name__ == "__main__":
    unittest.main()
