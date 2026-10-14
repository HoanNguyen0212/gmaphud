# GOFA/Waze background delivery — 0.2.2 internal

Date: 2026-10-14. Device: iPhone 11, iOS 18.6.2, rootless. Google Maps visible on CarPlay Simulator; phone stationary on real GPS; all runs in cold background (appState 2) launched by the SpringBoard supervisor. Measured with the device output reader (the common output Google Maps consumes).

## Findings

| Run | Speed present | Limit present |
| --- | --- | --- |
| GOFA 0.2.1 baseline, 60 × 1 s | 60/60 | 24/60 |
| Waze 0.2.1, 90 × 1 s then ~5 min × 3 s | 88/90, 103/104 | 88/90, 103/104 |
| GOFA 0.2.2 (final), 90 × 1 s | 90/90 | 90/90 |
| GOFA 0.2.2 (pre-review build), 60 × 1 s + 80 × 3 s | 140/140 | 140/140 |
| Waze 0.2.2, 60 × 1 s | 58/60 (2 s warm-up) | 58/60 |

Root cause (GOFA limit): GOFA posts `notificationSpeedBoard` only as its GPS pipeline accepts movement — every 5–9 s while nearly stationary in background — while samples expire after 5 s. The 0.2.1 repair read `currentSpeedBoard` from GOFA UI view models, but a cold background launch creates no view model (its bind hook never ran), so background fell back to the 5 s notification TTL.

Waze: no background deficit reproduced in ~8 minutes of cold-background measurement while stationary. Locked-screen, long-idle and on-road behavior were not tested.

Residual (not a regression): iOS sometimes delivers raw GPS sparsely or with invalid speed (-1) while the phone is stationary; GOFA/Waze speed then shows unavailable for those seconds. VietMap's raw callbacks show the same sparsity, but its engine publishes on its own cadence.

## Changes

- `tweak/gofa-source.m`, `tweak/gofa-alert-policy.h`: keep GOFA's latest native board; a fresh GPS fix re-stamps it while within 50 m of its anchor and younger than 30 s. Empty/unknown/zero boards clear. Removed the view-model hook and its per-notification JSON write (review items 1 and 4). Warnings unchanged (still 5 s membership).
- `provider/gofa-payload.swift`: an empty `pushSpeedBoard` now clears the limit; removed `GVMGofaBoardState`.
- `provider/background-location.m`: setter hooks use the existing session off the main thread; lease flag committed before setters; each hook settles on concurrent lease changes (review item 2).
- `tests/gofa-alert-policy-tests.c`, `docs/source-output-contract.md`, `tweak/control` (0.2.2).

Verification: source-test and test PASS; rootful+rootless build PASS (32 existing linker warnings only); installed rootless 0.2.2 dylib hashes match the build; no new crash reports. Independent code review: no critical/high; its medium (stale limit via dropped empty board, unbounded age) and lows were fixed.

## Follow-up: limit flashing while stationary (user report)

User observed VietMap holding limit 50 continuously at the same position while GOFA and Waze flashed it briefly. Cause: both adapters renewed the limit only on a new GPS sample, and iOS may deliver none for tens of seconds while stationary (185 s gap observed in GOFA's log); VietMap's engine re-sends its limit on its own cadence. Change: GOFA re-asserts its latest board every second until replaced/cleared or the latest GPS is >50 m from its anchor (30 s age cap removed); Waze re-reads its live native limit every second once its engine has processed a GPS position. Speed still requires fresh GPS.

Device run after the change: GOFA 180/180, Waze 176/180 (4 s warm-up). GPS stayed continuous in this window, so the GPS-silent hold path itself was not exercised on device; unit tests cover the Waze store and GOFA radius policy.

## Unresolved

- Verify the GPS-silent hold on device (Location Lab hold or a real stop) against VietMap at the same position.
- Locked/long-idle/on-road GOFA and Waze checks; whether GOFA ever posts an empty board.
