#!/bin/sh
# Persistent iPhone SE + Mazda CMU evidence collector.
# Run by rootless launchd every 60 seconds; never requires live.sh or diag.sh.
set -u
umask 077

PATH="/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

CONFIG="${GVM_AUTO_CONFIG:-/var/mobile/Documents/GMapHUD/auto-session.conf}"
if [ -r "$CONFIG" ]; then
    # This file is installed locally by the diagnostics package and contains
    # only operator-selected paths, retention and vehicle IP settings.
    . "$CONFIG"
fi

ROOT="${GVM_AUTO_ROOT:-/var/mobile/Documents/GMapHUD/auto-sessions}"
case "$ROOT" in
    /var/mobile/Documents/GMapHUD/auto-sessions) ;;
    *) ROOT=/var/mobile/Documents/GMapHUD/auto-sessions ;;
esac
PHONE_LOG_ROOT="${GVM_PHONE_LOG_ROOT:-/var/mobile/Library/Logs}"
CONTAINERS="${GVM_CONTAINERS:-/var/mobile/Containers/Data/Application}"
CMU_IPS="${GVM_CMU_IPS:-192.168.53.1 192.168.100.1}"
CMU_INTERVAL="${GVM_CMU_INTERVAL:-300}"
RETENTION_DAYS="${GVM_AUTO_RETENTION_DAYS:-7}"
COLLECTOR_VERSION="${GVM_COLLECTOR_VERSION:-1}"

case "$RETENTION_DAYS" in
    *[!0-9]*|'') RETENTION_DAYS=7 ;;
esac
case "$CMU_INTERVAL" in
    *[!0-9]*|'') CMU_INTERVAL=300 ;;
esac
[ "$CMU_INTERVAL" -gt 0 ] 2>/dev/null || CMU_INTERVAL=300

NOW=$(date +%s)
DAY=$(date +%Y-%m-%d)
CLOCK=$(date +%H%M%S)
DAY_DIR="$ROOT/$DAY"
STATE_DIR="$DAY_DIR/.state"
LOCK="$ROOT/.logger.lock"

mkdir -p "$DAY_DIR/iphone" "$DAY_DIR/cmu" "$DAY_DIR/meta" "$STATE_DIR" 2>/dev/null || exit 0
if ! mkdir "$LOCK" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

EVENTS="$DAY_DIR/meta/events.log"
record_event() {
    printf '%s %s\n' "$(date)" "$*" >> "$EVENTS" 2>/dev/null || true
}

prune_old_days() {
    [ "$RETENTION_DAYS" -gt 0 ] || return 0
    # RETENTION_DAYS=7 keeps the current day plus the previous six full days.
    find "$ROOT" -mindepth 1 -maxdepth 1 -type d -name '20??-??-??' \
        -mtime +$((RETENTION_DAYS - 1)) -print 2>/dev/null |
    while IFS= read -r old_day; do
        [ "$old_day" = "$DAY_DIR" ] && continue
        printf '%s removed=%s retention_days=%s\n' "$(date)" \
            "$(basename "$old_day")" "$RETENTION_DAYS" \
            >> "$DAY_DIR/meta/retention.log" 2>/dev/null || true
        rm -rf "$old_day"
    done
}

prune_old_days

hash_file() {
    FILE="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$FILE" 2>/dev/null | awk '{print $1}'
    elif command -v md5sum >/dev/null 2>&1; then
        md5sum "$FILE" 2>/dev/null | awk '{print $1}'
    else
        cksum "$FILE" 2>/dev/null | awk '{print $1":"$2}'
    fi
}

write_metadata_once() {
    META="$DAY_DIR/meta/device.txt"
    [ -f "$META" ] && return 0
    {
        echo "collector_version=$COLLECTOR_VERSION"
        echo "day=$DAY"
        echo "created_at=$(date)"
        echo "retention_days=$RETENTION_DAYS"
        echo "cmu_interval_seconds=$CMU_INTERVAL"
        echo "cmu_ips=$CMU_IPS"
        echo "device=$(uname -a 2>/dev/null || true)"
        echo "ios=$(sw_vers 2>/dev/null || true)"
        echo "network=$(scutil --nwi 2>/dev/null || true)"
        echo "package=$(dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' com.chou.googlemaps.vietmap 2>/dev/null || true)"
        for f in /var/jb/usr/lib/TweakInject/GoogleMapsVietMap.dylib \
                 /var/jb/usr/lib/TweakInject/VietMapGoogleMapsSource.dylib \
                 /var/jb/Library/MobileSubstrate/DynamicLibraries/GMapHUDGuidanceRelay.dylib; do
            [ -f "$f" ] || continue
            echo "file=$f"
            hash_file "$f"
        done
    } > "$META" 2>/dev/null || true
}

record_cmu_snapshot() {
    FILE="$1"
    IP="$2"
    ENDPOINT="$3"
    SIZE=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
    HASH=$(hash_file "$FILE")
    printf '{"captured_at_epoch_ms":%s,"captured_day":"%s","captured_clock":"%s","cmu_ip":"%s","endpoint":"%s","file":"%s","bytes":%s,"hash":"%s"}\n' \
        "$((NOW * 1000))" "$DAY" "$CLOCK" "$IP" "$ENDPOINT" \
        "$(basename "$FILE")" "$SIZE" "$HASH" \
        >> "$DAY_DIR/meta/cmu-snapshots.ndjson" 2>/dev/null || true
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
    if [ "$OLD" -gt "$SIZE" ]; then
        OLD=0
        : > "$DEST"
        record_event "source_rotated=$SRC"
    fi
    if [ "$SIZE" -gt "$OLD" ]; then
        tail -c +$((OLD + 1)) "$SRC" >> "$DEST" 2>/dev/null || true
        printf '%s\n' "$SIZE" > "$OFFSET_FILE"
    fi
}

write_metadata_once

# Fixed phone logs.
append_delta "$PHONE_LOG_ROOT/gmaphud-background.log" gmaphud-background.log
append_delta "/var/tmp/gmaphud-wifi.log" gmaphud-wifi.log
append_delta "$PHONE_LOG_ROOT/gmaphud-carplay-bootstrap.log" gmaphud-carplay-bootstrap.log

# Known app-container logs only; no broad application dump.
if [ -d "$CONTAINERS" ]; then
    find "$CONTAINERS" -type f \( \
        -name gmaphud-relay.log -o \
        -name gmaphud-background-client.log -o \
        -name gmaphud-location-session.log -o \
        -name googlemaps-vietmap-source.log \
    \) 2>/dev/null | while IFS= read -r SRC; do
        UUID=$(basename "$(dirname "$(dirname "$SRC")")")
        NAME=$(basename "$SRC")
        append_delta "$SRC" "${UUID}_${NAME}"
    done
fi

NC_BIN=""
if command -v nc >/dev/null 2>&1; then
    NC_BIN=$(command -v nc)
elif [ -x /var/jb/usr/bin/nc ]; then
    NC_BIN=/var/jb/usr/bin/nc
fi

http_get_body() {
    IP="$1"
    PATHNAME="$2"
    [ -n "$NC_BIN" ] || return 1
    {
        printf 'GET %s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n' "$PATHNAME" "$IP"
    } | "$NC_BIN" -w 4 "$IP" 8889 2>/dev/null |
        awk 'BEGIN { body=0 } { sub(/\r$/, ""); if (body) print; else if ($0 == "") body=1 }'
}

poll_cmu() {
    LAST_FILE="$STATE_DIR/cmu-last-poll"
    LAST=0
    [ -f "$LAST_FILE" ] && LAST=$(cat "$LAST_FILE" 2>/dev/null || echo 0)
    case "$LAST" in *[!0-9]*|'') LAST=0;; esac
    [ $((NOW - LAST)) -ge "$CMU_INTERVAL" ] || return 0

    if [ -z "$NC_BIN" ]; then
        record_event 'cmu_poll=skipped reason=no_netcat'
        printf '%s\n' "$NOW" > "$LAST_FILE"
        return 0
    fi

    FOUND=0
    for IP in $CMU_IPS; do
        OUT="$DAY_DIR/cmu/diag-all-${IP}-${CLOCK}.log"
        if http_get_body "$IP" /diag/all > "$OUT.tmp" && [ -s "$OUT.tmp" ]; then
            mv -f "$OUT.tmp" "$OUT"
            record_event "cmu_ip=$IP endpoint=diag/all file=$(basename "$OUT")"
            record_cmu_snapshot "$OUT" "$IP" diag/all
            FOUND=1
            break
        fi
        rm -f "$OUT.tmp"
        if http_get_body "$IP" /diag > "$OUT.tmp" && [ -s "$OUT.tmp" ]; then
            mv -f "$OUT.tmp" "$OUT"
            record_event "cmu_ip=$IP endpoint=diag file=$(basename "$OUT")"
            record_cmu_snapshot "$OUT" "$IP" diag
            FOUND=1
            break
        fi
        rm -f "$OUT.tmp"
        record_event "cmu_ip=$IP endpoint=unreachable"
    done
    [ "$FOUND" -eq 1 ] || record_event 'cmu_poll=complete result=unreachable'
    printf '%s\n' "$NOW" > "$LAST_FILE"
}

poll_cmu

printf '%s files=%s\n' "$(date)" \
    "$(find "$DAY_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')" \
    > "$DAY_DIR/meta/last-run.txt" 2>/dev/null || true
