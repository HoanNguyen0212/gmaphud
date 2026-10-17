#!/bin/sh
# Run direct OEM D-Bus HUD test and preserve a readback log on the USB.
# Vehicle must be parked with Ignition ON or engine running.

mount -o rw,remount / 2>/dev/null
MYDIR=$(dirname "$(readlink -f "$0")")
mount -o rw,remount "$MYDIR" 2>/dev/null
mount -o rw,remount /tmp/mnt/sda1 2>/dev/null
mount -o rw,remount /tmp/mnt/sdb1 2>/dev/null

LOGDIR="$MYDIR/logs"
mkdir -p "$LOGDIR" 2>/dev/null
OUT="$LOGDIR/hud_direct_test.log"
if ! touch "$OUT" 2>/dev/null; then
    OUT="/tmp/hud_direct_test_usb.log"
fi

export LD_LIBRARY_PATH=/jci/lib:/usr/lib
printf '%s\n' "=== DIRECT HUD TEST WRAPPER START ===" > "$OUT"
printf '%s\n' "Vehicle must be parked; ignition must be ON or engine running." >> "$OUT"
printf '%s\n' "The test will display 60 km/h + right turn + HUD_TEST for 15 seconds." >> "$OUT"

"$MYDIR/hud_direct_test" >> "$OUT" 2>&1
RC=$?
printf '%s\n' "HUD_DIRECT_TEST_EXIT_CODE=$RC" >> "$OUT"
sync

if [ "$OUT" = "/tmp/hud_direct_test_usb.log" ]; then
    cp -f "$OUT" "$LOGDIR/hud_direct_test.log" 2>/dev/null
fi

printf '%s\n' ""
printf '%s\n' "[OK] TEST KET THUC. Lay file logs/hud_direct_test.log tren USB."
printf '%s\n' "Ma thoat: $RC"
exit "$RC"
