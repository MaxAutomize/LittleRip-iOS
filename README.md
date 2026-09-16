# LittleRip for iOS

LittleRip is a personal iOS app with two parts:

1. **LittleRip AI assistant** — a Siri-like text/voice assistant powered by the user's authenticated ChatGPT account.
2. **SmartRent door widget** — a preserved Control Widget that unlocks the SmartRent front door without opening the app.

## Current app experience

- Chrome / black / white robot branding with green robot eyes.
- Text and voice input.
- Responses are structured with `DEFINITION`, `EXPLANATION`, `ANALOGY`, and `FIRST PRINCIPLES` sections.
- Wikipedia source cards are labeled **Wiki**.
- Wiki articles are selected semantically using the current prompt plus recent in-session context, so vague follow-ups like “what about him?” still choose relevant articles.
- Chat context is session-only: it survives while the app is open, but resets when the app is killed/restarted.
- Model audio is not spoken aloud automatically.
- Response text is selectable.

## SmartRent widget

The door unlock flow remains independent of the AI assistant:

- **`Shared/SmartRentClient.swift`** — talks to the SmartRent API: logs in, finds the front-door `entry_control` lock, and sends the unlock command over the Phoenix websocket.
- **`Shared/UnlockFrontDoorIntent.swift`** — `AppIntent` used by the widget.
- **`LittleRipWidgetExtension/`** — Control Widget for one-tap unlock.

SmartRent credentials are stored in the shared App Group user defaults by the app. No credentials are committed.

## AI / Wiki files

- **`LittleRip/ChatGPTCodexClient.swift`** — authenticated ChatGPT conversation, Wiki planning, and notification intent planning.
- **`LittleRip/WebSearchClient.swift`** — verified Wikipedia article retrieval and Wiki card fetching.
- **`LittleRip/AssistantActionService.swift`** — branded, Time Sensitive local notifications.
- **`LittleRip/VoiceInputManager.swift`** — Apple speech recognizer / microphone handling.
- **`LittleRip/ContentView.swift`** — assistant UI, selectable text, session context, Wiki cards, and keyboard behavior.

## Manual iOS reset

These apps use a free Apple Developer account, so Apple-controlled provisioning profiles may expire after about 7 days. Say **“reset the iOS app”** in Pi to call `littlerip_ios_reset` once. That single foreground transaction:

- checks the paired iPhone and Xcode Apple Account without attempting sign-in, passwords, or 2FA;
- quarantines only cached LittleRip profiles, regenerates and signs the app/widget in isolated DerivedData;
- verifies both embedded profiles and their exact expiration timestamps plus code signatures;
- installs the app in place (no uninstall or data wipe) and launches it with `devicectl`.

The tool reports the actual embedded profile expiration for both the app and widget. Apple may reuse a shorter-lived profile, so the tool does **not** promise seven days. If Xcode needs sign-in, the iPhone is locked/disconnected, or trust is required, it stops with an actionable error. There is no launchd, cron, login, or periodic refresh job.

`refresh.sh` remains only as a manual compatibility wrapper around `scripts/littlerip-ios-reset.sh`; it never schedules itself. Local device/team overrides live in the gitignored `local-env.sh`.

## Building

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
xcodebuild -project LittleRip.xcodeproj -scheme LittleRip \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

## Configuration

- **Bundle ID:** `com.maxautomize.LittleRip`
- **Widget bundle ID:** `com.maxautomize.LittleRip.LittleRipWidgetExtension`
- **App Group:** `group.com.maxautomize.LittleRip`
- **AI connection:** authenticated ChatGPT account
- **SmartRent credentials:** local/shared user defaults only
