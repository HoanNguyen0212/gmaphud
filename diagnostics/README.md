# Automatic GMapHUD + Mazda CMU diagnostics

This package installs a rootless Dopamine `launchd` job. It runs every 60 seconds and does not require `live.sh` or `diag.sh` for each drive.

## What it collects

- Incremental 5SE logs from fixed paths and known application-container basenames.
- CMU `/diag/all` every 5 minutes when `192.168.53.1` or `192.168.100.1` answers.
- `/diag` fallback for older CMU listeners.
- Device/iOS/package/dylib metadata and hashes.
- CMU snapshot metadata with timestamp, endpoint, byte size and hash.
- `last-run.txt` heartbeat and unreachable events.

## Storage and retention

```text
/var/mobile/Documents/GMapHUD/auto-sessions/YYYY-MM-DD/
  iphone/
  cmu/
  meta/
  .state/
```

Default retention is 7 days: the current day plus the previous six full days. Old dated folders are removed by the logger and each removal is recorded in `meta/retention.log`. Source logs are never deleted or truncated; only the collector's copies are pruned.

Edit the installed configuration only if needed:

```text
/var/mobile/Documents/GMapHUD/auto-session.conf
```

## Install once on the 5SE

Install the `.deb` through Sileo/Zebra or, after verifying the package and root channel, with the standard package manager. The package installs:

```text
/var/jb/usr/local/bin/gmaphud-auto-session-logger.sh
/var/jb/Library/LaunchDaemons/com.hoan.gmaphud.autosessionlogger.plist
/var/mobile/Documents/GMapHUD/auto-session.conf
```

The job runs as `mobile` with `/var/jb/usr/bin/sh`; it does not need an SSH session to stay alive. After installation, verify `launchctl print system/com.hoan.gmaphud.autosessionlogger` and wait for `meta/last-run.txt` to advance.

## Important boundary

This collector removes the need to run `diag.sh` for routine phone/CMU evidence. It does not capture the CMU's raw D-Bus stream continuously. That raw stream still requires `live.sh`, or a separate CMU-side rotating `dbus-monitor` service. The collector is honest when the vehicle route is unavailable: it saves 5SE evidence and records `cmu_ip`/unreachable instead of fabricating a CMU capture.
