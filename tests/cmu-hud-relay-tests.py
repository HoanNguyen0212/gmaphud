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


if __name__ == "__main__":
    unittest.main()
