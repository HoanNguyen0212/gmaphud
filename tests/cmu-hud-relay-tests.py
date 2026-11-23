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
                      "GVMCMURelaySetLimit", "GVMCMURelaySetUpcomingSpeed",
                      "GVMCMURelaySetNav",
                      "GVMCMURelayLastDatagram"]:
            self.assertIn(func, self.header, f"{func} missing from header")

    def test_impl_defines_all_public_functions(self):
        for func in ["GVMCMURelayStart", "GVMCMURelayStop",
                      "GVMCMURelaySetLimit", "GVMCMURelaySetUpcomingSpeed",
                      "GVMCMURelaySetNav",
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

    def test_upcoming_speed_warning_reuses_supported_nav_protocol(self):
        self.assertIn('GVMCMURelaySetUpcomingSpeed', self.header)
        self.assertIn('void GVMCMURelaySetUpcomingSpeed(', self.impl)
        self.assertIn('Max %lu km/h', self.impl)
        # The Google process owns the UDP socket; the source process publishes
        # the upcoming sign through Darwin notify state only.
        self.assertIn("GVM_RELAY_VIETMAP_SOURCE", self.impl)
        self.assertIn("GVMPublishAheadState", self.impl)
        self.assertIn("return;", self.impl)
        self.assertIn("GVMPublishGoogleNavigation", self.impl)

        self.assertIn('#include <notify.h>', self.impl)
        self.assertIn('com.chou.gmaphud.cmu.google-nav', self.impl)
        self.assertIn('com.chou.gmaphud.cmu.ahead-speed', self.impl)
        self.assertIn('GVMGoogleProcessAlive', self.impl)
        self.assertIn('GVMSharedAheadState', self.impl)

    def test_nav_relay_keeps_renderable_utf8(self):
        send_nav_idx = self.impl.index('static void SendNav')
        send_nav_body = self.impl[send_nav_idx:send_nav_idx+1300]
        self.assertIn('NSUTF8StringEncoding', send_nav_body)
        self.assertNotIn('NSASCIIStringEncoding', send_nav_body)

    def test_phone_time_sync_protocol(self):
        self.assertIn('"SYNC %lld %llu\\n"', self.impl)
        self.assertIn("SendTimeSync", self.impl)
        self.assertIn("sLastSyncSend", self.impl)

    def test_relay_log_has_epoch_milliseconds(self):
        self.assertIn("epoch_ms=%lld", self.impl)

    def test_heartbeat_interval(self):
        self.assertIn("2.5", self.impl)

    def test_thread_safety_uses_synchronized(self):
        self.assertGreater(self.impl.count("@synchronized"), 3,
                           "Insufficient synchronization points")

    def test_cleanup_sends_limit_zero(self):
        # GVMCMURelayStop must send LIMIT 0 before closing
        stop_idx = self.impl.index("void GVMCMURelayStop")
        stop_body = self.impl[stop_idx:]
        self.assertIn("SendLimit(0)", stop_body)
        self.assertIn("close(sSock);", stop_body)

    def test_no_malloc_on_hot_path(self):
        # SendLimit should use stack buffer, no NSString/alloc in its body
        send_limit_idx = self.impl.index("static void SendLimit")
        send_limit_body = self.impl[send_limit_idx:send_limit_idx+300]
        self.assertNotIn("alloc]", send_limit_body)
        self.assertIn("snprintf", send_limit_body)

    def test_road_name_sanitization(self):
        self.assertIn("stringByReplacingOccurrencesOfString:@\"\\n\"", self.impl)
        self.assertIn("substringToIndex:128", self.impl)

    def test_ipv6_socket_rebinds_when_carplay_interface_appears(self):
        # Google Maps can initialize before Lightning CarPlay creates en3. The
        # existing socket must be rebound dynamically; setup-time binding alone
        # leaves cmu.local UDP sends at EHOSTUNREACH after en3 appears.
        send_idx = self.impl.index("static BOOL SendDatagram")
        send_body = self.impl[send_idx:send_idx + 5200]
        self.assertIn("sTarget6BoundIf", self.impl)
        self.assertIn("setsockopt(sSock6, IPPROTO_IPV6, IPV6_BOUND_IF", send_body)

    def test_idle_navigation_packets_are_dropped_but_active_end_clears_once(self):
        start = self.impl.index("void GVMCMURelaySetNav")
        end = self.impl.index("void GVMCMURelayStop", start)
        body = self.impl[start:end]
        self.assertIn("if (iconID == 0)", body)
        self.assertIn("SendEffectiveNav();", body)


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
                # Files may be in common/, provider/, tweak/, or diagnostics/
                found = any((root / d / f).exists()
                            for d in ["common", "provider", "tweak", "tweak/prefs", "diagnostics"])
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
    """Verify VietMap Live navigation maneuvers are captured without replacing Google's CMU maneuver."""

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

    def test_vietmap_idle_progress_never_overwrites_google_maps_nav(self):
        start = self.vmsource.index("static void GVMHandleVietMapProgress(id args, NSTimeInterval received) {")
        end = self.vmsource.index("#endif", start)
        body = self.vmsource[start:end]
        self.assertNotIn("GVMCMURelaySetNav(", body)
        self.assertIn("Google Maps is the single CMU maneuver owner", body)

    def test_makefile_links_nav_hook_in_vietmap_provider(self):
        self.assertIn("VietMapGoogleMapsSource_FILES", self.makefile)
        self.assertIn("carplay-nav-hook.m", self.makefile)
        # Both targets should link carplay-nav-hook.m
        matches = re.findall(r"carplay-nav-hook\.m", self.makefile)
        self.assertGreaterEqual(len(matches), 2)

    def test_hook_header_exports_instruction_mapper(self):
        self.assertIn("GVMMapInstructionTextToMazdaHUD", self.hook_header)

    def test_tpms_safeguards_against_sensor_ids_and_stale_cache(self):
        # Must guard Publish() from scanning NSUserDefaults when live data is already active
        self.assertIn("if (!g_liveTPMS.hasData) GVMScanUserDefaultsForTPMS();", self.vmsource)
        # GVMScanUserDefaultsForTPMS must return early if g_liveTPMS.hasData
        self.assertIn("if (g_liveTPMS.hasData) return;", self.vmsource)
        # Must specifically look for _storedTPMSDeviceCache rather than wildcards
        self.assertIn("_storedTPMSDeviceCache", self.vmsource)
        # GVMParseTireDict must reject strings with non-numeric characters (hex sensor IDs)
        self.assertIn("nonNum", self.vmsource)
        # Skip Flutter GPS location stream dicts in TPMS raw handler
        self.assertIn("probeDict[@\"latitude\"]", self.vmsource)

    def test_relay_recovers_defunct_sockets_after_suspend(self):
        relay = (root / "common/cmu-hud-relay.m").read_text()
        self.assertIn("IsDefunctSocketError", relay)
        self.assertIn("CloseSocketFD", relay)
        self.assertIn("CloseSocketFD(&sSock6)", relay)
        self.assertIn("CloseSocketFD(&sSockUSB)", relay)
        self.assertIn("CloseSocketFD(&sSock)", relay)

    def test_relay_runs_off_main_thread_and_debounces_limit_zero(self):
        relay = (root / "common/cmu-hud-relay.m").read_text()
        self.assertIn("GVMRelayQueue", relay)
        self.assertIn("QOS_CLASS_UTILITY", relay)
        self.assertNotIn("dispatch_get_main_queue()", relay)
        self.assertIn("HasMazdaWiFiInterface()", relay)
        self.assertIn("sTarget6LastResolve = now; // Always back off on failure too", relay)
        self.assertIn("kLimitZeroGraceSeconds", relay)
        self.assertIn("sLimitZeroSince", relay)


if __name__ == "__main__":
    unittest.main()
