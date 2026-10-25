#!/bin/sh
# Persistent iPhone SE session logger for GMapHUD + Mazda CMU evidence.
# Runs once per launchd tick; the plist schedules it every 60 seconds.
set -u

ROOT="${GVM_AUTO_ROOT:-/var/mobile/Documents/GMapHUD/auto-sessions}"
PHONE_LOG_ROOT="${GVM_PHONE_LOG_ROOT:-/var/mobile/Library/Logs}"
CONTAINERS="${GVM_CONTAINERS:-/var/mobile/Containers/Data/Application}"
CMU_IPS="${GVM_CMU_IPS:-192.168.53.1 192.168.100.1}"
CMU_INTERVAL="${GVM_CMU_INTERVAL:-300}"

NOW=$(date +%s)
DAY=$(date +%Y-%m-%d)
CLOCK=$(date +%H%M%S)
DAY_DIR="$ROOT/$DAY"
STATE_DIR="$DAY_DIR/.state"
mkdir -p "$DAY_DIR/iphone" "$DAY_DIR/cmu" "$DAY_DIR/meta" "$STATE_DIR" 2>/dev/null || exit 0

# Prevent overlapping ticks if a large /diag/all response is still downloading.
LOCK="$ROOT/.logger.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

write_metadata_once() {
    META="$DAY_DIR/meta/device.txt"
    [ -f "$META" ] && return 0
    {
        echo "day=$DAY"
        echo "created_at=$(date)"
        echo "device=$(uname -a 2>/dev/null || true)"
        echo "ios=$(sw_vers 2>/dev/null || true)"
        echo "network=$(scutil --nwi 2>/dev/null || true)"
        echo "package=$(dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' com.chou.googlemaps.vietmap 2>/dev/null || true)"
        for f in /var/jb/usr/lib/TweakInject/GoogleMapsVietMap.dylib \
                 /var/jb/usr/lib/TweakInject/VietMapGoogleMapsSource.dylib; do
            [ -f "$f" ] && md5sum "$f" 2>/dev/null || true
        done
    } > "$META" 2>/dev/null || true
}

append_delta() {
    SRC="$1"
    NAME="$2"
    [ -f "$SRC" ] || return 0
    OFFSET_FILE="$STATE_DIR/$NAME.offset"
    DEST="$DAY_DIR/iphone/$NAME"
    SIZE=$(wc -c < "$SRC" 2>/dev/null | tr -d ' ')
    OLD=0
    [ -f "$OFFSET_FILE" ] && OLD=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)
    case "$OLD" in *[!0-9]*|'') OLD=0;; esac
    [ "$OLD" -le "$SIZE" ] || { OLD=0; : > "$DEST"; }
    if [ "$SIZE" -gt "$OLD" ]; then
        # tail -c +N avoids copying the same growing log on every tick.
        tail -c +$((OLD + 1)) "$SRC" >> "$DEST" 2>/dev/null || true
        printf '%s\n' "$SIZE" > "$OFFSET_FILE"
    fi
}

write_metadata_once

# Fixed iPhone logs.
append_delta "$PHONE_LOG_ROOT/gmaphud-background.log" gmaphud-background.log
append_delta "/var/tmp/gmaphud-wifi.log" gmaphud-wifi.log
append_delta "$PHONE_LOG_ROOT/gmaphud-carplay-bootstrap.log" gmaphud-carplay-bootstrap.log

# App-container logs. Include the container UUID in the filename to avoid
# silently merging two apps that use the same basename.
if [ -d "$CONTAINERS" ]; then
    for dir in "$CONTAINERS"/*; do
        [ -d "$dir/tmp" ] || continue
        uuid=$(basename "$dir")
        for name in gmaphud-relay.log gmaphud-background-client.log gmaphud-location-session.log \
                    googlemaps-vietmap-source.log; do
            append_delta "$dir/tmp/$name" "${uuid}_${name}"
        done
    done
fi

# Pull one full CMU evidence snapshot every CMU_INTERVAL seconds when either
# vehicle transport is reachable. /diag/all is preferred; /diag remains a
# compatibility fallback for old listener binaries.
LAST_FILE="$STATE_DIR/cmu-last-poll"
LAST=0
[ -f "$LAST_FILE" ] && LAST=$(cat "$LAST_FILE" 2>/dev/null || echo 0)
case "$LAST" in *[!0-9]*|'') LAST=0;; esac
if [ $((NOW - LAST)) -ge "$CMU_INTERVAL" ]; then
    for ip in $CMU_IPS; do
        OUT="$DAY_DIR/cmu/diag-all-${ip}-${CLOCK}.log"
        if curl -fsS -m 4 "http://${ip}:8889/diag/all" > "$OUT.tmp" 2>/dev/null && [ -s "$OUT.tmp" ]; then
            mv -f "$OUT.tmp" "$OUT"
            printf '%s cmu_ip=%s endpoint=diag/all file=%s\n' "$(date)" "$ip" "$(basename "$OUT")" >> "$DAY_DIR/meta/events.log"
            printf '%s\n' "$NOW" > "$LAST_FILE"
            break
        fi
        rm -f "$OUT.tmp"
        if curl -fsS -m 3 "http://${ip}:8889/diag" > "$OUT.tmp" 2>/dev/null && [ -s "$OUT.tmp" ]; then
            mv -f "$OUT.tmp" "$OUT"
            printf '%s cmu_ip=%s endpoint=diag file=%s\n' "$(date)" "$ip" "$(basename "$OUT")" >> "$DAY_DIR/meta/events.log"
            printf '%s\n' "$NOW" > "$LAST_FILE"
            break
        fi
        rm -f "$OUT.tmp"
    done
    [ -f "$LAST_FILE" ] || printf '%s\n' "$NOW" > "$LAST_FILE"
fi

printf '%s files=%s\n' "$(date)" "$(find "$DAY_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')" > "$DAY_DIR/meta/last-run.txt"
