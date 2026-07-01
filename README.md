# LittleRip for iOS

LittleRip is a personal iOS app with two parts:

1. **LittleRip AI assistant** — a Siri-like text/voice assistant powered by direct Ollama Cloud `glm-5.1`.
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

- **`LittleRip/OllamaClient.swift`** — direct Ollama Cloud API client.
- **`LittleRip/WebSearchClient.swift`** — semantic Wikipedia topic selection and Wiki card fetching.
- **`LittleRip/VoiceInputManager.swift`** — Apple speech recognizer / microphone handling.
- **`LittleRip/ContentView.swift`** — assistant UI, selectable text, session context, Wiki cards, and keyboard behavior.
- **`LittleRip/OllamaSecrets.swift`** — local-only API key file. The committed version is a placeholder; real secrets stay out of Git.

## Refresh automation

These apps are signed with a free Apple Developer account, so provisioning profiles expire after 7 days. Launchd runs:

- `check-refresh.sh` — checks actual `embedded.mobileprovision` expiration for the iOS app, widget extension, and WebDriverAgent.
- `refresh.sh` — rebuilds and reinstalls LittleRip + WebDriverAgent over USB when signing is close to expiry.

Local device/team overrides live in a gitignored `local-env.sh`.

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
- **Default model:** `glm-5.1`
- **Default Ollama host:** `https://ollama.com`
- **SmartRent credentials:** local/shared user defaults only
- **Ollama API key:** local-only `OllamaSecrets.swift`; never commit the real key
