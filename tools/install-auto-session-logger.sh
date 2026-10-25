#!/bin/sh
# Install/remove the rootless Dopamine launchd auto-session logger on iPhone SE.
set -eu

JB="${JB:-/var/jb}"
LABEL="com.hoan.gmaphud.autosessionlogger"
BIN="$JB/usr/local/bin/gmaphud-auto-session-logger.sh"
PLIST="$JB/Library/LaunchDaemons/$LABEL.plist"
SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

install_logger() {
    mkdir -p "$JB/usr/local/bin" "$JB/Library/LaunchDaemons" /var/mobile/Documents/GMapHUD/auto-sessions
    if [ -f "$BIN" ] && [ ! -f "$BIN.before-auto-session" ]; then cp -p "$BIN" "$BIN.before-auto-session"; fi
    if [ -f "$PLIST" ] && [ ! -f "$PLIST.before-auto-session" ]; then cp -p "$PLIST" "$PLIST.before-auto-session"; fi
    cp -f "$SOURCE_DIR/gmaphud-auto-session-logger.sh" "$BIN"
    cp -f "$SOURCE_DIR/com.hoan.gmaphud.autosessionlogger.plist" "$PLIST"
    chmod 0755 "$BIN"
    chmod 0644 "$PLIST"
    chown mobile:mobile /var/mobile/Documents/GMapHUD/auto-sessions 2>/dev/null || true
    launchctl bootout system/$LABEL 2>/dev/null || true
    launchctl bootstrap system "$PLIST"
    launchctl enable system/$LABEL 2>/dev/null || true
    launchctl kickstart -k system/$LABEL 2>/dev/null || true
    echo "[OK] Installed $LABEL"
    echo "[OK] Logs: /var/mobile/Documents/GMapHUD/auto-sessions/YYYY-MM-DD/"
}

remove_logger() {
    launchctl bootout system/$LABEL 2>/dev/null || true
    rm -f "$PLIST" "$BIN"
    echo "[OK] Removed $LABEL (logs preserved)"
}

case "${1:-install}" in
    install) install_logger ;;
    remove|uninstall) remove_logger ;;
    *) echo "Usage: $0 install|remove" >&2; exit 2 ;;
esac
