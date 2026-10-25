#!/bin/sh
# GMapHUD session collector: run from Mina, control an SSH-reachable 5SE.
# Stores one dated, versioned session archive on Mina without requiring USB.
set -eu

PHONE_HOST="${PHONE_HOST:-mobile@100.86.242.57}"
SSH_KEY="${SSH_KEY:-/home/hermes/.ssh/id_ed25519}"
LOCAL_ROOT="${LOCAL_ROOT:-/srv/hermes-workspace/gmaphud-se-logs/ssh-sessions}"
REMOTE_ROOT="${REMOTE_ROOT:-/var/mobile/Documents/GMapHUD/sessions}"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o PubkeyAuthentication=yes -o PasswordAuthentication=no -o BatchMode=yes -o ConnectTimeout=5"

usage() {
    echo "Usage: $0 start [label] | $0 stop | $0 status | $0 fetch SESSION_ID"
    exit 2
}

ssh_phone() {
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "$PHONE_HOST" "$@"
}

scp_phone() {
    # shellcheck disable=SC2086
    scp -O $SSH_OPTS "$@"
}

session_id_from_remote() {
    ssh_phone "cat '$REMOTE_ROOT/current_session' 2>/dev/null" | tr -d '\r\n'
}

start_session() {
    label="${1:-googlemaps}"
    stamp=$(date +%Y%m%d-%H%M%S)
    session_id="${stamp}-${label}"
    ssh_phone "sh -s -- '$REMOTE_ROOT' '$session_id'" <<'REMOTE_START'
set -eu
ROOT="$1"
ID="$2"
DIR="$ROOT/$ID"
mkdir -p "$DIR/iphone" "$DIR/cmu"
printf '%s\n' "$ID" > "$ROOT/current_session"
{
    echo "session_id=$ID"
    echo "started_at=$(date)"
    echo "device_id=$(uname -a 2>/dev/null || true)"
    echo "ios=$(sw_vers 2>/dev/null || true)"
    echo "network=$(scutil --nwi 2>/dev/null || true)"
    echo "package=$(dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' com.chou.googlemaps.vietmap 2>/dev/null || true)"
    for f in /var/jb/usr/lib/TweakInject/GoogleMapsVietMap.dylib \
             /var/jb/usr/lib/TweakInject/VietMapGoogleMapsSource.dylib; do
        [ -f "$f" ] && md5sum "$f" 2>/dev/null || true
    done
} > "$DIR/metadata-start.txt"

# Mark the CMU listener when a vehicle route is available. Failure is recorded,
# never treated as a successful HUD connection.
for ip in 192.168.53.1 192.168.100.1; do
    if command -v nc >/dev/null 2>&1; then
        printf 'SESSION_START %s\n' "$ID" | nc -u -w 1 "$ip" 8888 2>/dev/null || true
    elif [ -x /var/jb/usr/bin/nc ]; then
        printf 'SESSION_START %s\n' "$ID" | /var/jb/usr/bin/nc -u -w 1 "$ip" 8888 2>/dev/null || true
    fi
done
printf 'SESSION_STARTED=%s\n' "$ID"
REMOTE_START
}

stop_session() {
    session_id=$(session_id_from_remote)
    [ -n "$session_id" ] || { echo "No active remote session" >&2; exit 1; }

    ssh_phone "sh -s -- '$REMOTE_ROOT' '$session_id'" <<'REMOTE_STOP'
set -eu
ROOT="$1"
ID="$2"
DIR="$ROOT/$ID"
mkdir -p "$DIR/iphone" "$DIR/cmu"

# Snapshot iPhone logs without assuming one app-container UUID.
for f in /var/mobile/Library/Logs/gmaphud-background.log \
         /var/tmp/gmaphud-wifi.log \
         /var/mobile/Library/Logs/gmaphud-carplay-bootstrap.log; do
    [ -f "$f" ] && cp -f "$f" "$DIR/iphone/" 2>/dev/null || true
done
CONTAINERS=/var/mobile/Containers/Data/Application
if [ -d "$CONTAINERS" ]; then
    find "$CONTAINERS" -maxdepth 3 -type f \( \
        -name gmaphud-relay.log -o \
        -name gmaphud-background-client.log -o \
        -name gmaphud-location-session.log -o \
        -name googlemaps-vietmap-source.log \
    \) -exec cp -f {} "$DIR/iphone/" \; 2>/dev/null || true
fi

# Fetch the full CMU evidence endpoint over either vehicle transport.
CMU_IP=""
for ip in 192.168.53.1 192.168.100.1; do
    if command -v curl >/dev/null 2>&1 && curl -fsS -m 3 "http://${ip}:8889/diag/all" > "$DIR/cmu/diag-all-${ip}.log" 2>/dev/null; then
        if [ -s "$DIR/cmu/diag-all-${ip}.log" ]; then
            CMU_IP="$ip"
            break
        fi
    fi
done
printf 'cmu_ip=%s\n' "$CMU_IP" > "$DIR/metadata-cmu.txt"

for ip in 192.168.53.1 192.168.100.1; do
    if command -v nc >/dev/null 2>&1; then
        printf 'SESSION_END %s\n' "$ID" | nc -u -w 1 "$ip" 8888 2>/dev/null || true
    elif [ -x /var/jb/usr/bin/nc ]; then
        printf 'SESSION_END %s\n' "$ID" | /var/jb/usr/bin/nc -u -w 1 "$ip" 8888 2>/dev/null || true
    fi
done
{
    echo "session_id=$ID"
    echo "ended_at=$(date)"
    echo "files:"
    find "$DIR" -type f -print 2>/dev/null | sort
} > "$DIR/metadata-end.txt"
rm -f "$ROOT/current_session"
printf 'SESSION_STOPPED=%s\n' "$ID"
REMOTE_STOP

mkdir -p "$LOCAL_ROOT"
local_dir="$LOCAL_ROOT/$session_id"
rm -rf "$local_dir"
mkdir -p "$local_dir"
scp_phone -r "$PHONE_HOST:$REMOTE_ROOT/$session_id" "$LOCAL_ROOT/"
tar -czf "$LOCAL_ROOT/${session_id}.tar.gz" -C "$LOCAL_ROOT" "$session_id"
sha256sum "$LOCAL_ROOT/${session_id}.tar.gz"
echo "LOCAL_SESSION=$local_dir"
}

status_session() {
    session_id=$(session_id_from_remote || true)
    if [ -n "$session_id" ]; then
        echo "ACTIVE_SESSION=$session_id"
    else
        echo "NO_ACTIVE_SESSION"
    fi
}

fetch_session() {
    id="${1:-}"
    [ -n "$id" ] || usage
    mkdir -p "$LOCAL_ROOT"
    rm -rf "$LOCAL_ROOT/$id"
    scp_phone -r "$PHONE_HOST:$REMOTE_ROOT/$id" "$LOCAL_ROOT/"
    tar -czf "$LOCAL_ROOT/${id}.tar.gz" -C "$LOCAL_ROOT" "$id"
    sha256sum "$LOCAL_ROOT/${id}.tar.gz"
}

case "${1:-}" in
    start) shift; start_session "${1:-googlemaps}" ;;
    stop) stop_session ;;
    status) status_session ;;
    fetch) shift; fetch_session "${1:-}" ;;
    *) usage ;;
esac
