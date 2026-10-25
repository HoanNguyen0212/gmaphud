#!/bin/sh
# ==============================================================================
# GMapHUD & Mazda CMU Live Diagnostic Collector
# Runs on iPhone SE (iOS 15.8 Dopamine Rootless)
# Probes both 192.168.53.1 (Wired USB) and 192.168.100.1 (Wireless AP)
# ==============================================================================

OUT_DIR="/var/mobile/Documents/GMapHUD"
if [ ! -d "/var/mobile" ] && [ -d "/var/jb/var/mobile" ]; then
    OUT_DIR="/var/jb/var/mobile/Documents/GMapHUD"
fi
mkdir -p "$OUT_DIR" 2>/dev/null

echo "========================================================"
echo "   GMAPHUD & MAZDA CMU AUTOMATED DIAGNOSTIC COLLECTOR   "
echo "========================================================"
echo "Output Directory: $OUT_DIR"
echo "Capture Time: $(date)"
echo ""

# 1. Collect iPhone Sandboxed & System Logs
echo "[1/3] Dang tim va gom log tren iPhone SE..."
COPIED_COUNT=0

# Fixed logs
for fixed in /var/mobile/Library/Logs/gmaphud-background.log \
             /var/mobile/Library/Logs/gmaphud-carplay-bootstrap.log \
             /var/mobile/Library/Logs/gmaphud-wifi.log; do
    if [ -f "$fixed" ]; then
        cp -f "$fixed" "$OUT_DIR/" 2>/dev/null
        echo "  + Phat hien: $(basename "$fixed")"
        COPIED_COUNT=$((COPIED_COUNT + 1))
    fi
done

# Sandboxed app containers (Google Maps, VietMap Live)
CONTAINERS="/var/mobile/Containers/Data/Application"
if [ -d "$CONTAINERS" ]; then
    for target in gmaphud-relay.log googlemaps-vietmap-source.log googlemaps-vietmap.log truedash-vietmap.log; do
        found=$(find "$CONTAINERS" -maxdepth 3 -name "$target" 2>/dev/null | head -n 1)
        if [ -n "$found" ] && [ -f "$found" ]; then
            cp -f "$found" "$OUT_DIR/$target" 2>/dev/null
            echo "  + Tim thay trong sandbox: $target ($(wc -l < "$found" 2>/dev/null) lines)"
            COPIED_COUNT=$((COPIED_COUNT + 1))
        fi
    done
fi

if [ $COPIED_COUNT -eq 0 ]; then
    echo "  ! Chua tim thay log nao trong sandbox (vui long mo Google Maps / VietMap truoc)."
fi
echo ""

# 2. Probe & Fetch CMU Logs from Headunit
echo "[2/3] Dang kiem tra ket noi CMU (192.168.53.1 & 192.168.100.1)..."
CMU_ACTIVE=""

for ip in 192.168.53.1 192.168.100.1; do
    # Prefer the full evidence endpoint; fall back to the compact status endpoint
    # so this collector remains compatible with older CMU listeners.
    for endpoint in diag/all diag; do
        endpoint_file=$(echo "$endpoint" | tr '/' '_')
        if curl -s -m 2 "http://${ip}:8889/${endpoint}" > "$OUT_DIR/cmu_${endpoint_file}_${ip}.log" 2>/dev/null; then
            if [ -s "$OUT_DIR/cmu_${endpoint_file}_${ip}.log" ]; then
                CMU_ACTIVE="$ip"
                echo "  [OK] Ket noi thanh cong CMU tai $ip (Micro-HTTP :8889/${endpoint})!"
                cp -f "$OUT_DIR/cmu_${endpoint_file}_${ip}.log" "$OUT_DIR/cmu_diag.log" 2>/dev/null
                break 2
            fi
        fi
    done

    # Fallback: Check port 22 (SSH)
    if nc -z -w 1 "$ip" 22 2>/dev/null; then
        CMU_ACTIVE="$ip"
        echo "  [OK] Phat hien CMU tai $ip (SSH :22). Dang keo log..."
        ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no jci@"$ip" "cat /tmp/cmu_listener.log" > "$OUT_DIR/cmu_listener.log" 2>/dev/null
        ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no jci@"$ip" "cat /tmp/carplay_bridge.log" > "$OUT_DIR/carplay_bridge.log" 2>/dev/null
        break
    fi
done

if [ -z "$CMU_ACTIVE" ]; then
    echo "  [FAIL] Khong thay phan hoi tu ca 192.168.53.1 (USB) lan 192.168.100.1 (Wi-Fi)."
    echo "         (Hay dam bao da cam cap Lightning hoac bat Wi-Fi ket noi vao xe)."
fi
echo ""

# 3. Summary & Quick Inspection
echo "[3/3] TOM TAT DU LIEU THU THAP DUOC:"
echo "--------------------------------------------------------"
if [ -f "$OUT_DIR/gmaphud-relay.log" ]; then
    echo "--- 10 dong cuoi cua gmaphud-relay.log (iPhone) ---"
    tail -n 10 "$OUT_DIR/gmaphud-relay.log"
    echo "--------------------------------------------------------"
fi

if [ -f "$OUT_DIR/cmu_diag.log" ]; then
    echo "--- Thong tin chan doan CMU tu $CMU_ACTIVE ---"
    head -n 25 "$OUT_DIR/cmu_diag.log"
    echo "--------------------------------------------------------"
elif [ -f "$OUT_DIR/cmu_listener.log" ]; then
    echo "--- 10 dong cuoi cua cmu_listener.log (CMU) ---"
    tail -n 10 "$OUT_DIR/cmu_listener.log"
    echo "--------------------------------------------------------"
fi

echo ""
echo "[HOAN TAT] Tat ca file log da luu tai: $OUT_DIR/"
ls -lh "$OUT_DIR" 2>/dev/null
