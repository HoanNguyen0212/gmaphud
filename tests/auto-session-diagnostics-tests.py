#!/usr/bin/env python3
"""Offline contract tests for the rootless automatic diagnostics package."""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "diagnostics"


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=ROOT, text=True, capture_output=True, check=False)


def test_source_contract() -> None:
    logger = (PACKAGE / "layout/var/jb/usr/local/bin/gmaphud-auto-session-logger.sh").read_text()
    plist = (PACKAGE / "layout/var/jb/Library/LaunchDaemons/com.hoan.gmaphud.autosessionlogger.plist").read_text()
    config = (PACKAGE / "layout/var/mobile/Documents/GMapHUD/auto-session.conf").read_text()

    assert "StartInterval" in plist and "<integer>60</integer>" in plist
    assert "/var/jb/usr/bin/sh" in plist
    assert "<string>mobile</string>" in plist
    assert "append_delta" in logger
    assert "/diag/all" in logger and "/diag" in logger
    assert "CMU_IPS" in logger
    assert "RETENTION_DAYS" in logger
    assert "GVM_AUTO_RETENTION_DAYS=7" in config
    assert "rm -rf \"$old_day\"" in logger
    assert "meta/last-run.txt" in logger
    assert "cmu-snapshots.ndjson" in logger
    assert "umask 077" in logger
    assert "MAZDA CMU TELEMETRY LISTENER STATUS" in logger
    assert "%25" in logger
    assert "seen[addr] = 1" in logger
    postinst = (PACKAGE / "DEBIAN/postinst").read_text()
    prerm = (PACKAGE / "DEBIAN/prerm").read_text()
    assert "bootstrap system" in postinst
    assert "bootout system" in prerm
    assert "probe_is_usable" in logger
    assert logger.index("gmaphud-cmu-usb-probe") < logger.index("gmaphud-cmu-http-probe")


def test_probe_selection_skips_broken_python_wrapper() -> None:
    logger = (PACKAGE / "layout/var/jb/usr/local/bin/gmaphud-auto-session-logger.sh").read_text()
    start = logger.index("probe_is_usable() {")
    end = logger.index("capture_ncm_state() {")
    snippet = logger[start:end]
    with tempfile.TemporaryDirectory(prefix="gmaphud-probe-sel-") as tmp:
        bindir = Path(tmp) / "bin"
        bindir.mkdir()
        py_wrapper = bindir / "gmaphud-cmu-http-probe"
        py_wrapper.write_text("#!/usr/bin/env python3\nprint('bad')\n")
        py_wrapper.chmod(0o755)
        native = bindir / "gmaphud-cmu-usb-probe"
        native.write_bytes(b"\xcf\xfa\xed\xfe\x00\x00\x00\x00native-bin")
        native.chmod(0o755)
        script = f'PATH="{bindir}:/bin:/usr/bin"\n{snippet}\nprintf "%s" "$PROBE_BIN"\n'
        res = subprocess.run(["/bin/sh", "-c", script], text=True, capture_output=True, check=False)
        assert res.returncode == 0, res.stderr
        assert res.stdout == str(native), f"expected {native}, got {res.stdout!r}"

        # Even when native probe is absent, broken python wrapper must be rejected if python3 is missing.
        native.unlink()
        for tool in ("head", "tr", "sed"):
            target = Path("/usr/bin") / tool
            if not target.exists():
                target = Path("/bin") / tool
            (bindir / tool).symlink_to(target)
        script_no_py = f'PATH="{bindir}"\n{snippet}\nprintf "%s" "$PROBE_BIN"\n'
        res2 = subprocess.run(["/bin/sh", "-c", script_no_py], text=True, capture_output=True, check=False)
        assert res2.returncode == 0, res2.stderr
        assert res2.stdout == "", f"expected empty PROBE_BIN without python3, got {res2.stdout!r}"


def test_package_build_contract() -> None:
    with tempfile.TemporaryDirectory(prefix="gmaphud-diagnostics-test-") as tmp:
        out = Path(tmp) / "gmaphud-diagnostics.deb"
        result = run("sh", "diagnostics/build-package.sh", str(out))
        assert result.returncode == 0, result.stdout + result.stderr
        fields = run("dpkg-deb", "-f", str(out), "Package", "Version", "Architecture")
        assert fields.returncode == 0, fields.stdout + fields.stderr
        assert "Package: com.hoan.gmaphud.diagnostics" in fields.stdout
        assert "Architecture: iphoneos-arm64" in fields.stdout
        contents = run("dpkg-deb", "-c", str(out))
        assert contents.returncode == 0, contents.stdout + contents.stderr
        for path in (
            "./var/jb/usr/local/bin/gmaphud-auto-session-logger.sh",
            "./var/jb/Library/LaunchDaemons/com.hoan.gmaphud.autosessionlogger.plist",
            "./var/mobile/Documents/GMapHUD/auto-session.conf",
        ):
            assert path in contents.stdout, path


def main() -> int:
    tests = [test_source_contract, test_probe_selection_skips_broken_python_wrapper, test_package_build_contract]
    for test in tests:
        test()
        print(f"{test.__name__}: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
