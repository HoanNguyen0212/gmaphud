# Common source output · v1

Implemented in internal **0.1.20**. This is the adapter/bridge contract for both
CarPlay and foreground Google Maps on iPhone. VietMap is the first migrated source.
The source chooser remains disabled until another adapter is implemented. This
document does not claim support for Waze or other apps.

The owning definitions are [source-output.h](../common/source-output.h),
[source-output.m](../common/source-output.m) and
[source-transport.h](../common/source-transport.h). Keep IDs stable; append new
alert types instead of reordering the enum. An incompatible encoding needs a new
schema version and notification namespace.

## Envelope

Adapters pass an immutable `NSDictionary` to `GVMPublishSourceOutput`. For example:

```json
{
  "schemaVersion": 1,
  "sourceID": 1,
  "speed": { "value": 42, "receivedAt": 100 },
  "speedLimit": { "value": 50, "receivedAt": 101 },
  "alerts": [
    { "type": 4, "value": 80, "distance": 200, "artworkID": 36, "receivedAt": 101 },
    { "type": 30, "value": null, "distance": 400, "artworkID": 44, "receivedAt": 102 }
  ]
}
```

The numbers above are illustrative receive times, not wall-clock dates. JSON here
documents the shape; IPC carries numeric states, not JSON or images.

| Field | Rule |
| --- | --- |
| `schemaVersion` | Integer `1`; unsupported schemas reject the envelope. |
| `sourceID` | Integer 1–7. `1` is VietMap; 2–7 are unassigned, not enabled providers. |
| `speed` | Optional sample, integer 0–400 **km/h**. Stationary zero is valid. |
| `speedLimit` | Optional sample, integer 1–400 **km/h**. Zero means unavailable. |
| sample `receivedAt` | Original `NSProcessInfo.systemUptime` in seconds on the same device/boot. |
| `alerts` | Required array; normalization keeps at most two fresh distinct alerts. Empty clears all alerts. Input is bounded to 64 entries. |
| alert `type` | Stable semantic `GVMRoadAlertType`, independent of an app's image index. |
| alert `value` | Integer 1–400 km/h for `GVMRoadAlertSpeedLimit`; otherwise null. |
| alert `distance` | Integer 0–10000 **metres**, or null when unknown. Zero means at the point. |
| alert `artworkID` | Optional source-local decoration ID, integer 0–127; defaults to 0. |
| alert `receivedAt` | Original receive time of that alert update; independent of scalar fields. |

Missing, null, invalid or expired scalar samples are omitted. Invalid individual
alerts are omitted; malformed envelopes/containers are rejected. Numeric strings,
booleans, fractional values, nonfinite values and out-of-range numbers are not
coerced. Adapters convert native units and rounding before this boundary. Unknown
fields are stripped; coordinates, routes and raw app payloads do not leave it.

Each field expires at **five seconds**, independently, and future timestamps are
rejected. Publication, polling and refresh requests never renew receive times.
IPC floors times to milliseconds, so expiry may be up to 1 ms earlier. No valid
limit means no near-limit/overspeed comparison; existing placeholders remain.

Alerts sort by nearest known distance, then newer receive time. Unknown distances
follow known distances. Identical type/value/distance entries are deduplicated;
the newer wins. Only the first two survive. Supported semantic categories include
cameras, upcoming speed limits, residential boundaries, passing/turn restrictions,
mandatory directions, railway, tunnel, toll and rest-area warnings. Exact numeric
IDs and names are defined by the enum and `GVMRoadAlertName` in the owning files.

## One selected source

VietMap is the default. Consumers call `GVMReadSourceOutput(now)` and use its entire
envelope; they do not independently combine speed, limit or alerts from adapters.
Only the selected adapter can publish. Missing data stays missing; there is no
merge or automatic fallback to another source. Auto-wake also runs only when
VietMap is selected.

`GVMSelectOutputSource` persists the single ID and advances a selection epoch.
Switching source immediately makes the old frame unreadable. Returning to a
previous source also needs a new frame, even if its values have not changed.
`GVMRestoreOutputSelection` restores the saved ID from SpringBoard. Selection is
currently an internal API, not a newly enabled Settings option.

`GVMRequestSelectedSource` posts only the selected provider's request name, returned
by `GVMOutputRequestName`. The running provider checks selection again and replies
with a forced publication of its original samples. Requests do not create data or
start an app; the existing opt-in background supervisor owns that separate task.
The VietMap response retains its existing two-second throttle.

## Numeric IPC

Each source owns eight Darwin states at
`com.chou.gmaphud.output.v1.<sourceID>.<slot>`:

| Slot | Content |
| --- | --- |
| `commit` | Revision in upper bits, schema version in low byte. Odd revision means writing; positive even revision means committed. |
| `selection` | Selection epoch belonging to this frame. |
| `speed`, `limit` | Existing scalar numeric encoding and original timestamps. |
| `alert.first`, `alert.second` | Original timestamp, source ID, **semantic type**, distance. |
| `alert.first.value`, `alert.second.value` | Artwork ID plus optional numeric alert value. |

The writer begins an odd revision, writes selection and all six payload words,
then finishes an even revision. The reader checks commit and selection before and
after; partial writes, source switches, old epochs and unknown schemas are
unavailable. Each source has **one adapter writer process**; local operations are
serialized. This is a consistency protocol, not cross-process writer arbitration
or cryptographic authentication. Other injected/privileged software can still
alter Darwin state. There is no network service, GPS feed or authorization change.

Live production uses this versioned namespace exclusively. Existing bounded
`gvm-test-speed` display samples keep their old test channels and are translated
at the Google Maps test boundary; they never enter the live source namespace.
Old production channels are not a fallback. Loading 0.1.20 requires both apps to
reopen and a respring to load the matching SpringBoard component; mixed loaded
versions will not bridge. No device restart/installation is performed by host tests.

## Adding an adapter

1. Allocate an unused stable source ID and add its display identity. Implement the
   actual app callbacks; do not synthesize missing production data.
2. Convert native units to km/h/metres, map alerts to semantic types, and preserve
   independent receive times. Build/normalize with `GVMSourceOutput`.
3. Publish using `GVMPublishSourceOutput`, handle only that source's request name,
   and send empty fields/alerts when cleared. Do not revive stale caches.
4. Keep app payload parsing/artwork recognition in the adapter. The VietMap example
   is [vietmap-output.m](../provider/vietmap-output.m); the renderer uses semantic
   types and optional decoration, not VietMap indices as alert identities. Missing
   artwork uses a generic camera/warning or a numeric speed sign.
5. Test real callbacks, unit conversion, expiry, invalidation, source switching and
   both Google Maps surfaces before enabling that source in Settings.

## Verification

Run `sh test-source-output.sh` for contract, all 46 VietMap mappings, actual
`VMNavSource` migration, frame validation and isolated real Darwin IPC checks,
including a separate reader process. Run `sh test.sh` for the full regression suite
and `sh build-tweak.sh all` for both package schemes. Host IPC tests use a unique
notification/preferences namespace and remove their saved preference afterward.
The test executable requires that private namespace at compile time.

The matching 0.1.20 modules were installed and tested on iPhone 11 / iOS 18.6.2:
stationary speed/limit, simulated-location movement and upcoming-limit delivery
worked on native CarPlay and Google Maps iPhone; independent expiry and recovery
were checked. Camera rendering was tested separately with bounded display data.
This does not establish real-road accuracy, every alert kind or compatibility
with other devices, OS releases or app versions.
