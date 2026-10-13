---
title: Common source output for GMapHUD 0.1.20
date: 2026-10-13
summary: "VietMap and Google Maps use one versioned single-source contract; eight test suites and dual packages pass, unpublished."
---

# Common source output for GMapHUD 0.1.20

## Changes
Independent speed/limit timestamps and semantic road alerts share one normalized output. VietMap owns native payload recognition; both Google surfaces read committed source-scoped frames. Selection epochs reject previous-source data and incomplete writes. No fallback or simultaneous sources.

## Verification
Eight host suites pass, including all 46 VietMap mappings and real Darwin IPC across separate processes. Rootful/rootless 0.1.20 packages compile successfully. Validation rejects malformed sample containers and boolean adapter timestamps. Rendering ignores receive-time-only changes to preserve caching. A compile-time test container warning was corrected before the full checks.

## Boundaries
No device installation/restarts, commit, source index update or push. Real iPhone/CarPlay migration remains to be verified with matching modules. Owning standard: docs/source-output-contract.md. IDs 2–7 remain unassigned.

> Historical work record — not durable authority. Prefer docs/specs/ADRs for current decisions.

## Authorized follow-up

Installed matching 0.1.20 modules on the test iPhone and verified production speed,
limits and upcoming-limit delivery on CarPlay and iPhone, plus expiry/recovery.
Fixed a future timestamp in the CarPlay display-test alert conversion by sharing
the enclosing frame clock; all eight host suites and both package builds passed
again. Temporary location-module compatibility testing was reverted afterward.
Publication was subsequently authorized with the release note “Cải thiện tính ổn định”.
