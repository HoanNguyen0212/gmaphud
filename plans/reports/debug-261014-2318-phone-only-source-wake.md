# Phone-only source wake and keep-alive — 0.2.3 internal

Date: 2026-10-14. Device: iPhone 11, iOS 18.6.2, rootless; GMapHUD 0.2.3 installed with respring. CarPlay Simulator quit to simulate leaving the car; Google Maps (`com.google.Maps` 26.41.1) foregrounded on the iPhone.

## Cause

With "Thoát nguồn khi ngắt CarPlay" enabled, the SpringBoard supervisor closed the source 20 s after a CarPlay disconnect and set `exitCompleted`, which only a CarPlay reconnect cleared. Any later phone-only use could never wake the source. The phone heartbeat was also zeroed on any brief inactivity (banner, Control Center, app switch), ending the lease within one 2 s tick.

## Change

- `GVMBackgroundExitHolds`: auto-exit holds the source closed only while CarPlay is disconnected and no Google Maps is visible on the iPhone. A visible phone map restarts the countdown from when it is hidden and clears `exitCompleted`.
- The phone heartbeat expires after 12 s instead of being cleared immediately.
- Settings footer and `docs/source-output-contract.md` updated; policy tests added. `test.sh` and both builds PASS.

## Device verification

1. CarPlay quit → countdown → GOFA closed after 20 s (19:49:14).
2. Google Maps opened on the iPhone 12 min later → `iPhone Google Maps visible; CarPlay exit deferred`, supervisor restarted, GOFA cold-launched in background with its GPS lease applied.
3. VietMap phone-only: woken immediately; limit 39/45 samples while stationary indoors.
4. Location Lab route (4 points, 1,845 m, 37 km/h, GOFA TEST), phone-only, 230 × 1 s samples: speed 230/230 (0–38 km/h), limit 222/230 (60 → 50 → 80; 3 s warm-up and one 5 s gap at a board change), residential-end warning on 46 samples. The supervisor session stayed continuous from 23:14:00 through the route and after return to real GPS. No new crash reports.
5. Location Lab returned to real GPS (speed 2–4 km/h, limit 50 at the real position), disconnected and restored to 120 km/h.

## Unresolved

- The 12 s grace for brief inactivity (Control Center, banners) was not exercised on device; it needs a manual check on the phone screen.
- While stationary indoors without CarPlay, iOS delivered sparse GPS with invalid speed, so no source showed speed then; this is environmental.
