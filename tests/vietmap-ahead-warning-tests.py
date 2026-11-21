"""Contract tests for the 500 m VietMap speed-reduction warning path."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class VietMapAheadWarningTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / "provider/vietmap-source.x").read_text()
        self.relay_h = (ROOT / "common/cmu-hud-relay.h").read_text()
        self.relay_m = (ROOT / "common/cmu-hud-relay.m").read_text()

    def test_warning_is_bounded_to_500_metres(self):
        self.assertIn("GVM_AHEAD_WARNING_DISTANCE_METERS 500", self.source)
        self.assertIn("GVM_AHEAD_WARNING_DISTANCE_METERS", self.source)

    def test_source_converts_raw_alert_to_speed_limit_value(self):
        self.assertIn("GVMVietMapOutputAlert", self.source)
        self.assertIn("GVMRoadAlertSpeedLimit", self.source)
        self.assertIn("GVMCMURelaySetUpcomingSpeed", self.source)

    def test_only_a_lower_upcoming_limit_is_published(self):
        self.assertIn("nextLimit < currentLimit", self.source)
        self.assertIn("candidateDistance > GVM_AHEAD_WARNING_DISTANCE_METERS", self.source)
        self.assertIn("Max %lu km/h", self.relay_m)

    def test_warning_has_a_clear_path(self):
        self.assertIn("GVMCMURelaySetUpcomingSpeed(0, 0)", self.source)
        self.assertIn("GVMPublishAheadState(0, 0)", self.relay_m)

    def test_vietmap_never_overwrites_google_maneuver(self):
        self.assertNotIn("GVMCMURelaySetNav(", self.source)
        self.assertIn("Google Maps is the single CMU maneuver owner", self.source)


if __name__ == "__main__":
    unittest.main()
