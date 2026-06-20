# LittleRip for iOS

LittleRip is a personal iOS app whose headline feature is a **lock-screen Control Widget that unlocks your SmartRent front door** with one tap — no app launch required.

## What's inside

- **`Shared/SmartRentClient.swift`** — talks to the SmartRent API: logs in, finds the front-door `entry_control` lock, and sends the `locked=false` command over their Phoenix websocket.
- **`Shared/UnlockFrontDoorIntent.swift`** — an `AppIntent` the widget runs (always allowed, runs without opening the app).
- **`LittleRipWidgetExtension/`** — a `ControlWidget` ("Unlock Door") that appears in the lock-screen controls / Dynamic Island region and fires `UnlockFrontDoorIntent`.
- **`LittleRip/`** — the main app: save your SmartRent email/password (shared via App Group `group.com.maxautomize.LittleRip` so the widget can read them).

## Why it auto-relaunches every 6 days

These apps are signed with a **free Apple Developer account**, whose provisioning profiles expire after **7 days**. To stay installed, a launchd job runs `check-refresh.sh` → `refresh.sh`:

1. Checks the build age of the installed iOS (and macOS) app
2. If older than **6 days** (518,400 s), rebuilds with XcodeGen + xcodebuild and reinstalls over USB (`xcrun devicectl device install app`)
3. Otherwise skips — keeping the apps perpetually within their 7-day window

The device **UDID is not in the repo** — `refresh.sh` sources a gitignored `local-env.sh`. Copy `local-env.example.sh` to `local-env.sh` and set `IOS_DEVICE_UDID` to your phone's UDID.

## Building

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
xcodebuild -project LittleRip.xcodeproj -scheme LittleRip \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

## Configuration

- **Bundle ID:** `com.maxautomize.LittleRip` (+ `.LittleRipWidgetExtension`)
- **App Group:** `group.com.maxautomize.LittleRip`
- **SmartRent credentials:** stored in the shared `UserDefaults` by the main app; the widget reads them at tap time. No credentials are in this repo.