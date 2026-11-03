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
    postinst = (PACKAGE / "DEBIAN/postinst").read_text()
    prerm = (PACKAGE / "DEBIAN/prerm").read_text()
    assert "bootstrap system" in postinst
    assert "bootout system" in prerm


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
    tests = [test_source_contract, test_package_build_contract]
    for test in tests:
        test()
        print(f"{test.__name__}: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
