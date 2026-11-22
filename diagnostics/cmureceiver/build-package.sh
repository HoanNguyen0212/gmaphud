#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
VERSION=$(sed -n 's/^Version: *//p' "$ROOT/DEBIAN/control")
OUT=${1:-"$ROOT/com.hoan.gmaphud.cmureceiver_${VERSION}_iphoneos-arm64.deb"}

mkdir -p "$(dirname "$OUT")"
mkdir -p "$ROOT/work"
rm -rf "$ROOT/work/pkg"
mkdir -p "$ROOT/work/pkg/DEBIAN"
cp -R "$ROOT/DEBIAN/." "$ROOT/work/pkg/DEBIAN/"
cp -R "$ROOT/layout/." "$ROOT/work/pkg/"
mkdir -p "$ROOT/work/pkg/var/jb/usr/local/bin"

BIN="$ROOT/work/pkg/var/jb/usr/local/bin/gmaphud-cmu-log-receiver"
SRC="$ROOT/gmaphud-cmu-log-receiver.c"

if [ -n "${GVM_CMU_RECEIVER_BIN:-}" ] && [ -f "$GVM_CMU_RECEIVER_BIN" ]; then
    cp "$GVM_CMU_RECEIVER_BIN" "$BIN"
elif [ "$(uname -s)" = "Darwin" ] && [ -x "/var/jb/usr/bin/clang" ] && [ -d "/var/jb/usr/share/SDKs/iPhoneOS.sdk" ]; then
    # Native compilation on jailbroken iOS (Dopamine rootless)
    /var/jb/usr/bin/clang -arch arm64 -mios-version-min=14.0 \
        -isysroot /var/jb/usr/share/SDKs/iPhoneOS.sdk \
        -O2 -Wall -Wextra -Werror "$SRC" -o "$BIN"
    if command -v ldid >/dev/null 2>&1; then
        ldid -S "$BIN"
    fi
elif [ "$(uname -s)" = "Darwin" ] && command -v xcrun >/dev/null 2>&1; then
    # Cross-compilation on macOS (Xcode iPhoneOS SDK)
    SDK=$(xcrun --sdk iphoneos --show-sdk-path)
    xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=14.0 \
        -isysroot "$SDK" -O2 -Wall -Wextra -Werror "$SRC" -o "$BIN"
    if command -v ldid >/dev/null 2>&1; then
        ldid -S "$BIN"
    fi
else
    echo "error: iOS arm64 compiler/SDK not found (set GVM_CMU_RECEIVER_BIN or build on macOS/iOS)" >&2
    exit 1
fi

chmod 0755 "$ROOT/work/pkg/DEBIAN"
chmod 0755 "$ROOT/work/pkg/DEBIAN/postinst" "$ROOT/work/pkg/DEBIAN/prerm"
chmod 0755 "$ROOT/work/pkg/var/jb" "$ROOT/work/pkg/var/jb/Library" \
    "$ROOT/work/pkg/var/jb/Library/LaunchDaemons" "$ROOT/work/pkg/var/jb/usr" \
    "$ROOT/work/pkg/var/jb/usr/local" "$ROOT/work/pkg/var/jb/usr/local/bin"
chmod 0755 "$BIN"
chmod 0644 "$ROOT/work/pkg/var/jb/Library/LaunchDaemons/com.hoan.gmaphud.cmureceiver.plist"

if dpkg-deb --help 2>&1 | grep -q -- '--root-owner-group'; then
    dpkg-deb --build --root-owner-group "$ROOT/work/pkg" "$OUT" >/dev/null
else
    dpkg-deb --build "$ROOT/work/pkg" "$OUT" >/dev/null
fi
printf '%s\n' "$OUT"
