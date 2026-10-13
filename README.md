# GMapHUD

**English** · [Tiếng Việt](README.vi.md)

Experimental rootful/rootless iOS tweak that displays fresh **VietMap Live speed and speed-limit data in Google Maps on CarPlay and iPhone**. Inspired by the traffic bubble feature in DuoDash and TrueDash. Google Maps continues to handle navigation.

**Author: chou · AI-assisted with Codex.** chou leads, tests and publishes this independent community project; Codex provided AI development assistance. This credit does not imply that OpenAI is the publisher, copyright holder, maintainer or support provider. Not affiliated with or endorsed by VietMap, Google, Apple or OpenAI.

> Experimental software for stationary testing and research. It is not a certified driving aid. Displayed information may be wrong, unavailable or delayed. Follow actual signs, road conditions and applicable law. Read [DISCLAIMER.md](DISCLAIMER.md) before use; a disclaimer does not guarantee legal protection.

## Bubble placement previews

These are the same CarPlay preview images shown in Settings. They illustrate all supported placements; the displayed values and alerts are examples, not a claim of live-road accuracy.

| Full map · top left | Full map · top right |
| --- | --- |
| ![Full-map bubble at top left](docs/screenshots/full-map-top-left.png) | ![Full-map bubble at top right](docs/screenshots/full-map-top-right.png) |

| Full map · bottom left | Full map · bottom right |
| --- | --- |
| ![Full-map bubble at bottom left](docs/screenshots/full-map-bottom-left.png) | ![Full-map bubble at bottom right](docs/screenshots/full-map-bottom-right.png) |

| Dashboard · left | Dashboard · right |
| --- | --- |
| ![Dashboard bubble at left](docs/screenshots/dashboard-left.png) | ![Dashboard bubble at right](docs/screenshots/dashboard-right.png) |

## Features

The horizontal CarPlay bubble places speed on the left, the limit sign on the right, and a VietMap Live label above. Dashboard uses a vertical bubble with the limit above current speed. Recognized VietMap road alerts use the corresponding bundled artwork and source distance in a shaded VietMap region: up to two side by side on full map, two stacked below speed on Dashboard. Input recognition matches observed image digests from VietMap Live 3.4.3. Bubble size adapts uniformly to the viewport and the user’s size setting. Navigation controls affect placement only, so each corner keeps the same dimensions. Full-map and Dashboard layouts are selected relative to screen width. The preview images above illustrate each supported placement.

In iPhone Settings → GMapHUD, choose any of the four corners for the full map and the left or right edge for Dashboard. The images above show each option. Top-right is the default in both layouts. The alert-source row shows VietMap Live but remains disabled until another source is supported. Placement changes update an open Google Maps CarPlay view; a SpringBoard relay restores saved placement after the phone interface restarts.

- Full-map speed pill and compact vertical Dashboard card; light/dark map colors.
- Current speed remains visible, with `--` when unavailable. Missing limits show a dashed sign.
- Amber from 5 km/h below the limit through the limit; red above it. Visual cues only, no audible alert system.
- Card placement follows the map toolbar's safe area. The Google CarPlay heading/compass control is hidden.
- Speed and limit expire independently after five seconds. A heartbeat does not make old data fresh.
- Optional stationary display test with a TEST badge and automatic expiry.

Published 0.1.13 does not port road alerts. Release 0.1.14 recognizes 46 known alert-image digests from VietMap Live 3.4.3; unknown or changed artwork stays hidden. VietMap's upcoming speed-limit message may omit its image, so supported numeric limits use the matching bundled VietMap Live sign. Camera and upcoming 80 km/h delivery were observed live; other sign categories are mapped from observed app artwork but have not yet been observed in live payloads. Navigation instructions and Live Activities remain unsupported. It includes no GPS spoofing, location replay, DRM bypass or subscription bypass.

## 0.1.22 · updated sign artwork

All 46 display icons now use the supplied condensed-font artwork. The main speed-limit sign uses SF Pro Condensed Semibold, with the system Semibold Condensed descriptor when the named font is unavailable. Font fitting preserves the chosen face; source recognition and bubble geometry are unchanged.

## 0.1.21 · modular bubble

Settings → GMapHUD now groups the master **Hiển thị bong bóng** switch, **Nguồn cảnh báo**, **Chạy nền**, three screen settings and **Chẩn đoán / Xuất log**. Under **Thiết lập bong bóng cảnh báo**, choose **Bản đồ đầy đủ**, **Dashboard** or **Trên iPhone**. Each screen has its own visibility switch, position, Auto/Horizontal/Vertical layout, draggable module order and size slider. iPhone position also keeps the X/Y sliders. Existing selections are preserved; missing visibility settings default to on. The master switch hides all GMapHUD bubbles without changing individual screen choices or the separate background-wake option. Visibility changes apply while Google Maps is open.

**Thứ tự các phần** moves Current speed, Current limit and Upcoming alerts. Upcoming alerts remain a group of up to two source-ordered warnings, hidden when absent. Uncustomized ordering preserves the former horizontal and vertical defaults. Orientation does not change the screen's size/position settings. Dashboard uses the same text, sign and cell scale in Horizontal/Vertical at the same percentage. Only the physical map boundary can reduce that scale, with a shared ceiling sized for two alerts in either orientation. Switching direction or adding/removing alerts therefore changes the group shape without resizing its contents. Screenshots illustrate placement, not every customized layout.

The **Đặt lại** row beneath each adjustment resets only that part: size to 100%, an iPhone axis to 0%, position to top-right (right in Dashboard), layout to Auto, or module order to the default for the orientation. Other settings are preserved. Percentages use smaller gray text beneath the slider; both iPhone position sliders have matching track lengths.

Each speed, current-limit and individual warning cell now has equal dimensions in either orientation. Content is centered inside each cell; sign artwork preserves its aspect ratio, and a sign with distance is centered as one unit. Two warnings still move together and occupy two cells. The shared grid has been checked on iPhone, CarPlay Full Map and Dashboard with live data.

Host tests and rootful/rootless arm64/arm64e builds passed. Earlier 0.1.21 trial builds were installed on iPhone 11/iOS 18.6.2; the new menu, Full Map reorder page and drag persistence were verified. Turning off Full Map hid its bubble while Dashboard remained visible. The custom table uses an independent UIKit delegate to avoid Preferences-specific callbacks. App metadata and related crash listing were observed; file sharing and other devices still need validation. The final Dashboard sizing correction was subsequently verified on iPhone with 0/1/2/0 alerts; existing content retained its size.

Version 0.1.21 replaces all 46 bundled display signs with user-supplied redesigned artwork, optimized to transparent 256 px PNGs. Original VietMap input digests remain unchanged; display images are no longer recognition fixtures. Earlier published packages still contain their original artwork.

## Compatibility

| Component | Verified target |
| --- | --- |
| Device / OS | iPhone 11, iOS 18.6.2, rootless jailbreak |
| Google Maps | 26.40.3 |
| VietMap Live | 3.4.3 |
| Package | `com.chou.googlemaps.vietmap` 0.1.20, arm64/arm64e |

From 0.1.13, Google Maps is not restricted by version or executable UUID. Required private classes and method signatures are still checked; passing these checks does not guarantee compatibility with every release. The package identifier remains unchanged. Release 0.1.20 introduces a versioned production notification namespace; bounded display-test channels retain their original names.

From 0.1.13, the VietMap source also has no version restriction. Flutter channel structure and incoming data validation remain enabled. New app versions still require on-device verification.

UI states were checked using a real phone connected to Apple's CarPlay Simulator: normal, near-limit, overspeed and Dashboard. Live stationary values and simulated-location movement were observed. Physical-road accuracy, broad vehicle/head-unit compatibility and reliable background operation across OS/app updates are not established. VietMap display values are interpreted as km/h; simulated playback showed app-side differences from selected playback speed. This is not calibrated instrumentation.

## Install and remove

1. Use a compatible jailbreak and legitimately installed apps with any required VietMap entitlement/subscription. These are not supplied here.
2. Copy **https://gmaphud.caidat.app/** into **Sileo → Sources → +** or **Zebra → Sources → +**, refresh, then search for **GMapHUD**. The [source page](https://gmaphud.caidat.app/) has quick-add buttons for both. Alternatively, download the `.deb` from [Releases](https://github.com/bechou0410/gmaphud/releases), and verify its SHA-256 against `SHA256SUMS`. The [original GitHub Pages source](https://bechou0410.github.io/gmaphud/) remains available as a fallback; downloads through it are not counted.
3. Install through your jailbreak's package manager. Review removal prompts for old bridge/probe packages listed in [tweak/control](tweak/control). This package does not uninstall vendor TrueDash. The source includes rootless (`iphoneos-arm64`) and rootful (`iphoneos-arm`) packages. Rootful still requires device testing on iOS 14; older app builds may need additional integration changes.
4. Close and reopen VietMap and Google Maps, then open Google Maps in CarPlay. Keep VietMap's background alerts running. A Live Activity alone does not prove fresh speed samples.

No default SSH password is provided or required. After updating to 0.1.20, respring once to load the background component, then reopen Google Maps and Settings. Optional automatic wake supports When In Use or Always location access; enable VietMap alerts first.

To remove: uninstall `com.chou.googlemaps.vietmap` through the package manager, then close and reopen both apps. Removing files does not unload an injected library from an already-running process.

## Build and test

Requires macOS with Python 3.9+, Xcode command-line tools, Theos, a rootless-capable toolchain and an iPhoneOS 16.5 SDK obtained under its applicable license. SDKs and dependencies are not bundled.

```sh
git clone https://github.com/bechou0410/gmaphud.git
cd gmaphud
sh test.sh
THEOS="$HOME/theos" sh build-tweak.sh all
```

Packages appear in `packages/`. Both scripts use disposable directories and support spaces in the checkout path. The tested toolchain emits a pre-existing `-multiply_defined is obsolete` linker warning.

Build/test commands now keep full logs locally and return a compact result. Successful runs never call AI; failures can use the configured Jev key to classify filtered diagnostics while preserving the command's exit code. See [build/test triage](docs/build-triage.md) for key setup, local reports and the `GMAPHUD_JEV=off` / `GMAPHUD_CHECK_RAW=1` options.

## Maintain the Sileo source

Version policy: keep one next version throughout each unpublished development cycle, including every edit, build, and test installation. If the published version is `0.1.13`, all trial builds use `0.1.14`, and the release publishes that same `0.1.14`. Only after publication does the next development cycle use `0.1.15`. Do not increment the version for each trial. Use a commit hash or checksum to distinguish internal builds sharing a version; never overwrite a published package.

The [static source](https://bechou0410.github.io/gmaphud/) is published by GitHub Pages from `main` → `/docs`. [build-repo.py](build-repo.py) owns package/index/site generation, including the bilingual native Sileo depiction, CarPlay screenshot carousel, and changelog tab; [repo-template.html](repo-template.html) owns the shared landing-page layout and [repo-locales.json](repo-locales.json) owns its Vietnamese/English copy. The default page is Vietnamese; [en.html](https://gmaphud.caidat.app/en.html) is English. GitHub repository Settings → Pages owns this publishing configuration. Check deployment logs in the repository's Actions tab or `gh api repos/bechou0410/gmaphud/pages/builds/latest`.

The primary [installation source](https://gmaphud.caidat.app/) uses a Cloudflare Pages proxy to count full package-download starts by day, version and architecture. Existing GitHub Pages clients keep working through the fallback source. See [download statistics](docs/download-statistics.md) for the proxy source, aggregate queries, deployment and fallback behavior.

`docs/CydiaIcon*.png` are the repository icons Sileo fetches from the source root. The `Icon` field in [tweak/control](tweak/control) is the separate package icon; `docs/gmaphud-icon.svg/png` serve the website favicon and branding.

To publish an audited package, run `python3 build-repo.py packages/<rootless>.deb packages/<rootful>.deb` with Python 3 and `dpkg-deb` installed, review the resulting `docs/` changes, then commit and push. The index advertises the supplied version; previous package files remain available for existing downloads. Published filenames are immutable: bump the version before changing package bytes. Only audited production GMapHUD packages belong in this source. Never put logs, keys, app dumps or other local files in `docs/`; the entire directory becomes public.

This is a flat HTTPS APT source (`deb https://gmaphud.caidat.app/ ./`) with package/index checksums. Release metadata is not PGP-signed; checksums alone do not authenticate the publisher. No global APT trust/security overrides are supplied. To roll back a source publication, revert its commit and push, retaining any already published package files. Confirm that the Pages build succeeded and public indexes match the intended package before announcing an update.

Rollback through a new higher package version if clients have already upgraded; reverting the source index alone does not downgrade installed packages.

## Stationary display test

Run on the phone in a shell with access to the installed tool while Google Maps is open in CarPlay:

```sh
/var/jb/usr/bin/gvm-test-speed 42 50 60
/var/jb/usr/bin/gvm-test-speed 48 50 60
/var/jb/usr/bin/gvm-test-speed 62 50 60
/var/jb/usr/bin/gvm-test-speed 42 60 60 speed_limit_80:200 no_passing_in:400
/var/jb/usr/bin/gvm-test-speed off
```

Arguments: current speed (0–400 km/h), limit (1–400 km/h), duration (1–300 seconds), and optionally two VietMap asset names with distances (0–10000 m each), as `SIGN:METERS`, for trial 0.1.14. Bare distance numbers remain accepted as camera signs. Only the Google CarPlay display model changes; GPS, navigation and real VietMap data remain unchanged. By default, TEST remains visible until `off` or expiry. Missing live values remain missing after testing.

## Diagnostics

After installing, close and reopen both Google Maps and VietMap Live. Reproduce the issue, then open **Settings → GMapHUD → Chẩn đoán / Xuất log**. Tap **Làm mới** (Refresh), then **Sao chép báo cáo** (Copy report) or **Xuất file…** (Export file) to share a `.txt` report. Review the visible report first; nothing is uploaded automatically.

The summary includes hardware model (no serial number), OS, hook/channel status, sample freshness and CarPlay rendering checkpoints. It retains up to 16 recent checkpoints per app plus the last checkpoint for each stage. The summary excludes coordinates, routes and accounts. Notification state may disappear when processes or the notification service restart; collect it while reproducing the issue. Add the jailbreak version and split-screen tweak name manually when requesting support.

Version 0.1.21 also reads installed Google Maps and VietMap Live version and build metadata independently of module checkpoints. Unsupported metadata access is reported as unavailable. Refresh lists up to three readable related `.ips`/`.crash` files from the last seven days (at most 2 MB each); exporting can include these original files beside the summary. Disable **Đính kèm crash liên quan** to export only the summary. Crash files can contain device/app identifiers or other personal information; inspect attachments before sharing. Inaccessible or missing crash logs are reported explicitly, not treated as proof that no crash occurred.

0.1.15 has passed host tests, built for arm64/arm64e, and installed on iPhone 11. Clipboard/sharing and cross-app diagnostic transport still need device validation; this release adds diagnostics, not a confirmed fix for missing data on iOS 16.

## Architecture and privacy

`provider/vietmap-source.x` observes the existing VietMap Flutter overlay channel and forwards its original handler/reply unchanged. Validated speed and limit, each with their own monotonic receive time, travel through local Darwin notification state. Road alerts are decoded from JSON-string items in `vml_main_channel/updateUpcommingAlerts` and `updateStickyAlerts`, matched against exact 3.4.3 asset digests, and converted by a VietMap adapter into up to two semantic road alerts. Release 0.1.20 uses a [versioned common source output](docs/source-output-contract.md) for speed, limit and alerts on both Google Maps surfaces. Each frame belongs to one selected source; partial frames and old source selections are refused. VietMap is the only enabled source. Empty lists clear their source; original timestamps expire after five seconds. Release 0.1.14 bundles the 46 VietMap sign images for display; notifications remain numeric only. Those third-party images are excluded from the project MIT license. CarPlay hooks apply them to external map windows. A separate foreground-only overlay displays the same fresh data in the Google Maps iPhone window without intercepting touches.

The tweak creates no network listener, telemetry upload, publisher daemon or saved credentials. App-sandbox `tmp/googlemaps-vietmap-source.log` and `tmp/googlemaps-vietmap.log` record numeric speed/limit availability and hook status, not coordinates or routes. Local notification state is not cryptographically authenticated and can be affected by other privileged/injected software. Review device logs before sharing.

## License

Project-authored code is offered under [MIT](LICENSE). Current display artwork is supplied by the user; replacing images does not establish their provenance or grant redistribution rights. Artwork is not automatically covered by the code’s MIT license. Older published packages may contain original VietMap images. Third-party apps, maps, traffic/sign data, trademarks, SDKs and dependencies retain their owners' rights and terms. See [DISCLAIMER.md](DISCLAIMER.md) for lawful-use, safety, compatibility and warranty notices. Licensing does not certify legality, accuracy or roadworthiness.

For unedited Settings screenshots, append `--photo` to hide the badge for that bounded sample only. `gvm-test-speed position top-left left` changes Full Map/Dashboard placement temporarily without writing user preferences; restore the previous placement after capture.

## Automatic VietMap wake

After installation, respring once to load the SpringBoard component. In iOS Settings, enable Location Services and grant VietMap Live **When In Use** or **Always** location access, then enable **Settings → GMapHUD → Tự đánh thức VietMap Live**. The switch defaults to off and stays disabled until these conditions are confirmed. It refreshes while the page is visible. Revoking permission or disabling Location Services turns the feature off; restoring permission does not automatically turn it on again.

From 0.1.19, while Google Maps is visible on CarPlay or iPhone, GMapHUD can launch VietMap in the background and keep it active without bringing it to the foreground. Enable alerts in VietMap first; the tweak cannot sign in, activate a subscription or guarantee fresh data. Relaunch attempts are bounded to avoid a restart loop. Leaving Google Maps on both screens releases the added background session after the heartbeat expires; VietMap retains its real location permission. Private system APIs can vary by iOS version; if unavailable, automatic wake remains disabled. Runtime wake was tested on iPhone 11/iOS 18.6.2; the new switch gating has host/build validation, not complete on-device permission-transition validation on every supported OS. Rootful/iOS 14 behavior remains unverified. Waze is not included in this release.

Background state is recorded locally in `/var/mobile/Library/Logs/gmaphud-background.log` (bounded, no coordinates). Google Maps can request a fresh retransmission from the running source; cached values retain their original timestamps and expire normally.

## 0.1.18 · size controls and iPhone

Settings → GMapHUD provides independent sliders for Full Map, Dashboard and Google Maps on iPhone. Each ranges from 50% to 150%, default 100%, and uniform scaling is capped to fit the available area. Values persist independently. Respring once after installation to load size restoration in SpringBoard; reopen Google Maps and Settings to load the new UI.

The phone bubble appears only within foreground Google Maps, defaulting to the top-right corner. Auto layout switches to a vertical card in a tall/narrow app window and a horizontal card in a wide/landscape window. It is not a system-wide overlay and does not intercept map touches. It consumes real VietMap values with the same expiry as CarPlay, showing placeholders for missing data. Open VietMap and enable alerts first; from 0.1.19, optional automatic wake also works from Google Maps on iPhone. Waze is excluded. Phone placement, sizing and portrait/landscape layout were confirmed on the test iPhone; other devices and OS versions remain unverified.

The **Kích cỡ bong bóng** (Bubble size) menu controls CarPlay Full Map and Dashboard. The separate **Google Maps trên iPhone** menu contains phone size, four corners, Auto/Horizontal/Vertical layout, and X/Y offsets from −100% to +100%. X uses map width and Y uses map height; positive values move right/down, clamped to the full app window without safe-area exclusions. Sliders mark and snap near their midpoint: 0% for position and 100% for size. Opening Settings migrates legacy point offsets to percentages using the current screen dimensions.

Corner and layout choices use native iOS segmented controls. Percentage values are centered below the sliders, with selection feedback when dragging back to the neutral midpoint.

On iPhone, X/Y placement spans the entire Google Maps window with no toolbar, notch or home-indicator reserve. Zero anchors directly to the selected corner. The card stays within the window bounds; system UI or the physical notch may cover content placed there.

On CarPlay, the same viewport, alerts and size percentage produce the same bubble dimensions at every corner. Guidance panels and toolbar safe areas affect placement only. If the reserved area is too small, the bubble stays within the map without shrinking; use the size slider if it overlaps a control.

## 0.1.19 · performance

The phone and CarPlay overlays share one refresh timer at the existing 0.5-second interval. Each CarPlay update reads speed/limit once and reuses its native model unless values, style, units or the native view change; Google-originated updates still force synchronization. Data expiry, source requests and background-wake permission checks retain their existing behavior. Settings preview PNGs are recompressed losslessly, with identical dimensions and decoded pixels. Short on-device before/after captures found lower Google Maps process CPU in the fixed-display CarPlay scenarios. These process-wide samples do not isolate tweak overhead or establish battery savings; a restart also changes app caches.

## 0.1.19 · temporary location activity

The existing opt-in auto-wake switch now covers Google Maps visibly active on CarPlay or iPhone. A separate phone pulse clears when the app moves to the background; either active surface sustains the supervisor lease. Lost pulses expire within 12 seconds, then supervisor/provider checks withdraw the added session and restore manager flags. Switch-off or loss of qualifying location permission also withdraws it. VietMap's own background behavior is not disabled.

VietMap retains its real Always or When In Use permission. For When In Use, the provider owns one CLBackgroundActivitySession on iOS17+ while the lease qualifies, with diagnostics on iOS18+. No authorization request, TCC/locationd mutation, independent GPS feed or refreshed stale samples. Original callbacks and app stop requests remain intact. iOS14–16 retain manager continuation without this newer API.

A new public background activity alone was insufficient on the test device: it reported `insufficientlyInUse=1` until direct app use. For the opted-in When In Use route, SpringBoard now requests one temporary, bundle-scoped Core Location in-use assertion before launching VietMap suspended. Its runtime method signatures are checked; the default factory level was verified on the device. The assertion is released when Google visibility or eligibility ends. No foreground activation or authorization change is performed; unavailable private APIs fail without granting permission.

On iPhone 11/iOS 18.6.2/VietMap 3.4.3, a controlled test began with no VietMap process and the phone kept in Settings. Opening only Google Maps CarPlay launched VietMap in the background, cleared the insufficient-use diagnostic and delivered fresh GPS plus real 0/50 continuously. The user confirmed no manual VietMap opening in this repeated trial. An isolated phone-only launch also delivered fresh GPS/0/50 with the real permission still When In Use. Withdrawal restored manager flags and invalidated the added session on CarPlay; phone-only withdrawal verification is recorded in the local trial report.

A further locked-device trial held VietMap absent for over ten minutes after a controlled process termination. Opening only Google Maps CarPlay started a new background provider process and restored fresh GPS and real 0/50 while the phone stayed locked; its real permission remained When In Use. A warm ten-minute locked interval also resumed output, although VietMap had continued its own GPS during that interval. These bounded trials do not establish recovery after reboot, every crash, app-switcher force-quit, overnight idle or battery impact. Older iOS versions remain unverified. Six host suites and both package builds passed; the background feature has been tested on the setup above. VietMap must already be configured for alerts and have the required account/subscription. A bounded local `gmaphud-location-session.log` in VietMap's temporary directory records lifecycle, diagnostic flags, callback age/count and app state, never coordinates.
