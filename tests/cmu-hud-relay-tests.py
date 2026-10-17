"""Tests for the Mazda CMU HUD UDP relay (cmu-hud-relay) and TPMS state integrity."""
import hashlib
import os
from pathlib import Path
import re
import struct
import sys
import unittest

root = Path(__file__).resolve().parents[1]


class CMUHudRelaySourceTests(unittest.TestCase):
    """Validate the cmu-hud-relay.h/.m source contracts offline."""

    def setUp(self):
        self.header = (root / "common/cmu-hud-relay.h").read_text()
        self.impl = (root / "common/cmu-hud-relay.m").read_text()

    def test_header_declares_all_public_functions(self):
        for func in ["GVMCMURelayStart", "GVMCMURelayStop",
                      "GVMCMURelaySetLimit", "GVMCMURelaySetNav",
                      "GVMCMURelayLastDatagram"]:
            self.assertIn(func, self.header, f"{func} missing from header")

    def test_impl_defines_all_public_functions(self):
        for func in ["GVMCMURelayStart", "GVMCMURelayStop",
                      "GVMCMURelaySetLimit", "GVMCMURelaySetNav",
                      "GVMCMURelayLastDatagram"]:
            self.assertIn(f"void {func}(" if func != "GVMCMURelayLastDatagram"
                          else f"NSString *{func}(", self.impl,
                          f"{func} definition missing from impl")

    def test_uses_nonblocking_udp_socket(self):
        self.assertIn("SOCK_DGRAM", self.impl)
        self.assertIn("O_NONBLOCK", self.impl)
        self.assertIn("fcntl", self.impl)

    def test_target_address_defaults(self):
        self.assertIn("192.168.100.1", self.impl)
        self.assertIn("192.168.53.1", self.impl)
        self.assertIn("8888", self.impl)

    def test_protocol_format_limit(self):
        # The format string must produce "LIMIT %lu\n"
        self.assertIn('"LIMIT %lu\\n"', self.impl)

    def test_protocol_format_nav(self):
        self.assertIn('"NAV %lu %lu %s\\n"', self.impl)

    def test_heartbeat_interval(self):
        self.assertIn("2.5", self.impl)

    def test_thread_safety_uses_synchronized(self):
        self.assertGreater(self.impl.count("@synchronized"), 3,
                           "Insufficient synchronization points")

    def test_cleanup_sends_limit_zero(self):
        # GVMCMURelayStop must send LIMIT 0 before closing
        stop_idx = self.impl.index("void GVMCMURelayStop")
        stop_body = self.impl[stop_idx:stop_idx+500]
        self.assertIn("SendLimit(0)", stop_body)
        self.assertIn("close(sSock)", stop_body)

    def test_no_malloc_on_hot_path(self):
        # SendLimit should use stack buffer, no NSString/alloc in its body
        send_limit_idx = self.impl.index("static void SendLimit")
        send_limit_body = self.impl[send_limit_idx:send_limit_idx+300]
        self.assertNotIn("alloc]", send_limit_body)
        self.assertIn("snprintf", send_limit_body)

    def test_road_name_sanitization(self):
        self.assertIn("stringByReplacingOccurrencesOfString:@\"\\n\"", self.impl)
        self.assertIn("substringToIndex:200", self.impl)


class TPMSStateTests(unittest.TestCase):
    """Validate tpms-state.h/.m structural integrity after re-import."""

    def setUp(self):
        self.header = (root / "common/tpms-state.h").read_text()
        self.impl = (root / "common/tpms-state.m").read_text()

    def test_header_declares_types_and_functions(self):
        for name in ["GVMTPMSTire", "GVMTPMSData", "GVMEncodeTPMS", "GVMDecodeTPMS",
                      "GVMTPMSStateName"]:
            self.assertIn(name, self.header)

    def test_impl_defines_encode_decode(self):
        self.assertIn("uint64_t GVMEncodeTPMS", self.impl)
        self.assertIn("GVMTPMSData GVMDecodeTPMS", self.impl)

    def test_marker_nibble_0xA(self):
        # Wire format uses 0x0A as marker in bottom 4 bits
        self.assertIn("0x0A", self.impl)

    def test_staleness_limit_300s(self):
        self.assertIn("300", self.impl)

    def test_rollover_handling(self):
        self.assertIn("65536", self.impl)


class MakefileIntegrationTests(unittest.TestCase):
    """Verify Makefile correctly references all modules."""

    def setUp(self):
        self.makefile = (root / "tweak/Makefile").read_text()

    def test_cmu_relay_in_google_maps_target(self):
        self.assertIn("cmu-hud-relay.m", self.makefile)
        # Should be in GoogleMapsVietMap target
        for line in self.makefile.splitlines():
            if "GoogleMapsVietMap_FILES" in line:
                self.assertIn("cmu-hud-relay.m", line)
                break

    def test_tpms_in_all_required_targets(self):
        targets_needing_tpms = ["VietMapGoogleMapsSource_FILES",
                                 "GoogleMapsVietMap_FILES",
                                 "gvm-test-speed_FILES"]
        for target in targets_needing_tpms:
            for line in self.makefile.splitlines():
                if target in line:
                    self.assertIn("tpms-state.m", line,
                                  f"tpms-state.m missing from {target}")

    def test_all_source_files_exist(self):
        for line in self.makefile.splitlines():
            if "_FILES" not in line or "=" not in line:
                continue
            files_part = line.split("=", 1)[1].strip()
            for f in files_part.split():
                # Files may be in common/, provider/, or tweak/
                found = any((root / d / f).exists()
                            for d in ["common", "provider", "tweak", "tweak/prefs"])
                self.assertTrue(found, f"Source file {f} referenced in Makefile not found")


class GoogleHookIntegrationTests(unittest.TestCase):
    """Verify google-hook.m properly integrates the CMU relay."""

    def setUp(self):
        self.source = (root / "tweak/google-hook.m").read_text()

    def test_imports_cmu_relay_header(self):
        self.assertIn('#import "cmu-hud-relay.h"', self.source)

    def test_calls_relay_start(self):
        self.assertIn("GVMCMURelayStart()", self.source)

    def test_calls_relay_set_limit(self):
        self.assertIn("GVMCMURelaySetLimit(", self.source)

    def test_relay_start_after_hook_install(self):
        # GVMCMURelayStart should come after installed = YES
        installed_idx = self.source.index("installed = YES")
        relay_start_idx = self.source.index("GVMCMURelayStart()")
        self.assertGreater(relay_start_idx, installed_idx,
                           "Relay start should come after install completes")

    def test_relay_set_limit_uses_output_value(self):
        # Should relay 0 when limit is nil
        self.assertIn("limit ? limit.unsignedIntegerValue : 0", self.source)


class TPMSIntegrationFullTests(unittest.TestCase):
    """Verify TPMS end-to-end integration across provider, card rendering, and CLI test tool."""

    def test_provider_hooks_tpms(self):
        source = (root / "provider/vietmap-source.x").read_text()
        self.assertIn("GVMProcessTirePayload", source)
        self.assertIn("GVMTPMSStateName", source)
        self.assertIn("SetEventStreamHandler", source)
        self.assertIn("FlutterEventChannel", source)
        self.assertIn("notify_register_check(GVMTPMSStateName, &tpmsToken)", source)

    def test_speed_card_view_protocol_has_tpms(self):
        header = (root / "tweak/speed-card.h").read_text()
        self.assertIn("GVMTPMSData tpms;", header)

    def test_classic_card_renders_tpms(self):
        classic = (root / "tweak/classic-card.m").read_text()
        self.assertIn("@synthesize speed=_speed, limit=_limit, alerts=_alerts, night=_night, compact=_compact, sourceID=_sourceID, moduleOrder=_moduleOrder, tpms=_tpms;", classic)
        self.assertIn("DrawTire", classic)
        self.assertIn("self.tpms.hasData", classic)
        self.assertIn('DrawTire(@"FL"', classic)

    def test_halo_card_renders_tpms(self):
        halo = (root / "tweak/halo-card.m").read_text()
        self.assertIn("tpms=_tpms", halo)
        self.assertIn("DrawTire", halo)
        self.assertIn("self.tpms.hasData", halo)
        self.assertIn('DrawTire(@"FL"', halo)

    def test_carplay_style_reads_tpms_state(self):
        style = (root / "tweak/carplay-style.m").read_text()
        self.assertIn("GVMTPMSStateName", style)
        self.assertIn("GVMDecodeTPMS", style)
        self.assertIn("card.tpms = tpmsData;", style)
        self.assertIn("card.tpms.hasData", style)

    def test_cli_test_speed_supports_tpms(self):
        cli = (root / "tweak/test-speed.m").read_text()
        self.assertIn('strcmp(argv[1], "tpms") == 0', cli)
        self.assertIn("GVMEncodeTPMS", cli)
        self.assertIn("GVMTPMSStateName", cli)

        hook = (root / "tweak/google-hook.m").read_text()
        self.assertIn("notify_register_dispatch(GVMTPMSStateName", hook)

    def test_tpms_audit_remediations(self):
        vmsource = (root / "provider/vietmap-source.x").read_text()
        self.assertIn("GVMParseTireDict", vmsource)
        self.assertIn("explicitPos", vmsource)
        self.assertIn("@try", vmsource)
        self.assertIn("@catch", vmsource)
        self.assertIn("s_tpmsLock", vmsource)
        self.assertIn("kGVMStreamHookedKey", vmsource)

        classic = (root / "tweak/classic-card.m").read_text()
        self.assertIn("modulesEnd", classic)
        self.assertIn("BOOL active", classic)

        halo = (root / "tweak/halo-card.m").read_text()
        self.assertIn("baseHeight", halo)
        self.assertIn("baseWidth", halo)

        style = (root / "tweak/carplay-style.m").read_text()
        self.assertIn("GVMCardCanvasSize(style, alertCount, compact)", style)


class VietMapNavigationHUDTests(unittest.TestCase):
    """Verify VietMap Live navigation maneuvers and progress are captured and forwarded to CMU HUD."""

    def setUp(self):
        self.vmsource = (root / "provider/vietmap-source.x").read_text()
        self.makefile = (root / "tweak/Makefile").read_text()
        self.hook_header = (root / "tweak/carplay-nav-hook.h").read_text()

    def test_vietmap_source_handles_navigation_methods(self):
        self.assertIn("GVMHandleVietMapManeuver", self.vmsource)
        self.assertIn("GVMHandleVietMapProgress", self.vmsource)
        self.assertIn("GVMHandleVietMapNavEnd", self.vmsource)
        self.assertIn("GVMParseVietMapIcon", self.vmsource)
        self.assertIn("updatemaneuver", self.vmsource.lower())
        self.assertIn("updateultraprogress", self.vmsource.lower())

    def test_vietmap_source_normalizes_vietnamese_road_for_hud(self):
        self.assertIn("GVMNormalizeVietnameseForHUD", self.vmsource)
        self.assertIn("GVMExtractRoadName", self.vmsource)

    def test_makefile_links_nav_hook_in_vietmap_provider(self):
        self.assertIn("VietMapGoogleMapsSource_FILES", self.makefile)
        self.assertIn("carplay-nav-hook.m", self.makefile)
        # Both targets should link carplay-nav-hook.m
        matches = re.findall(r"carplay-nav-hook\.m", self.makefile)
        self.assertGreaterEqual(len(matches), 2)

    def test_hook_header_exports_instruction_mapper(self):
        self.assertIn("GVMMapInstructionTextToMazdaHUD", self.hook_header)


if __name__ == "__main__":
    unittest.main()
