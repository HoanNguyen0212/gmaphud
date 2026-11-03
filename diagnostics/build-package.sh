#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
OUT=${1:-"$ROOT/gmaphud-diagnostics.deb"}
mkdir -p "$(dirname "$OUT")"
mkdir -p "$ROOT/work"
rm -rf "$ROOT/work/pkg"
mkdir -p "$ROOT/work/pkg/DEBIAN"
cp -R "$ROOT/DEBIAN/." "$ROOT/work/pkg/DEBIAN/"
cp -R "$ROOT/layout/." "$ROOT/work/pkg/"
chmod 0755 "$ROOT/work/pkg/DEBIAN"
chmod 0755 "$ROOT/work/pkg/DEBIAN/postinst" "$ROOT/work/pkg/DEBIAN/prerm"
chmod 0755 "$ROOT/work/pkg/var/jb" "$ROOT/work/pkg/var/jb/Library" "$ROOT/work/pkg/var/jb/Library/LaunchDaemons" "$ROOT/work/pkg/var/jb/usr" "$ROOT/work/pkg/var/jb/usr/local" "$ROOT/work/pkg/var/jb/usr/local/bin"
chmod 0755 "$ROOT/work/pkg/var/mobile" "$ROOT/work/pkg/var/mobile/Documents" "$ROOT/work/pkg/var/mobile/Documents/GMapHUD"
chmod 0755 "$ROOT/work/pkg/var/jb/usr/local/bin/gmaphud-auto-session-logger.sh"
chmod 0644 "$ROOT/work/pkg/var/jb/Library/LaunchDaemons/com.hoan.gmaphud.autosessionlogger.plist"
chmod 0644 "$ROOT/work/pkg/var/mobile/Documents/GMapHUD/auto-session.conf"
dpkg-deb --build --root-owner-group "$ROOT/work/pkg" "$OUT" >/dev/null
printf '%s\n' "$OUT"
