# LittleRip for iOS

LittleRip is a polished physics-and-mathematics trivia game built around the existing chrome/silver/black/white robot and green-eye visual language. Questions are generated dynamically by the user's authenticated ChatGPT account through **GPT-5.6 Luna**.

## Game loop

- Home has one primary **New Game** action. Settings and SmartRent unlock remain available from the secondary controls.
- Luna returns one strictly validated JSON question with exactly four unique answer choices, one correct index, a short explanation, and a grounded implication. Choices are shuffled on-device while preserving the correct answer.
- Runs progress from genuinely simple **Warm-up** questions through Foundation, Application, Systems, and Frontier tiers. The prompt emphasizes mathematical/physical first principles, energy, probability, geometry, information, intelligence, fundamental equations, and implications—not celebrity trivia or impersonation. “Derive the equation” prompts use selectable derivation steps/equations rather than text entry.
- Correct answers show a short readable explanation, then automatically load the next question. Wrong answers and time expiration end the run and reveal the correct answer, explanation, implication, score, and **New Game**.
- Network, authentication, cancellation, or malformed/invalid Luna responses are retryable generation errors, never wrong answers and never score penalties. Malformed model payloads are retried up to three times.

## Scoring and timer

- The first correct answer earns 100 points. Each consecutive correct answer doubles the next reward: 100, 200, 400, 800, … . Scores and additions saturate at 10,000,000 so arithmetic cannot overflow.
- A miss resets the streak. Best score is stored in `UserDefaults` and survives relaunches.
- Each tier has a longer base thinking window for harder questions (24/29/36/44/54 seconds). A bounded answered-count pressure term gradually tightens the window within a tier, never below 18 seconds. The timer starts only after a valid question is installed; it uses a monotonic clock, cancels on answer, and serializes answer/timeout transitions to prevent races, duplicate taps, and background-clock exploits.
- The HUD shows current score, best score, streak, answered count, difficulty, timer, and the next reward.

## Account and SmartRent

ChatGPT device login, Keychain credential storage, refresh, sign-out, and security behavior remain in `ChatGPTCodexClient.swift`; no authentication values are logged. The app no longer requests microphone or location access for the game. The old voice launcher is coherently repurposed as a New Game launcher and never starts a microphone.

The SmartRent door flow remains independent and unchanged:

- **`Shared/SmartRentClient.swift`** logs in, finds the front-door `entry_control` lock, and sends the unlock command over the Phoenix websocket.
- **`Shared/UnlockFrontDoorIntent.swift`** powers the one-tap Control Widget unlock.
- SmartRent credentials remain local/shared App Group values and are never committed.
- The existing voice widget/control identifiers are retained so installed configurations update in place; they now open a Luna New Game. The SmartRent unlock control remains separate.

## Source layout

- **`LittleRip/TriviaGameModel.swift`** — typed question contract, bounded JSON/wrapper parsing, validation, shuffle, difficulty, timer, and saturating score rules.
- **`LittleRip/TriviaGameController.swift`** — main-actor game state machine, generation cancellation/stale-result guards, monotonic timer, persistence, feedback, and retry behavior.
- **`LittleRip/ChatGPTCodexClient.swift`** — existing authenticated ChatGPT client, now using `gpt-5.6-luna` and the strict trivia generation contract.
- **`LittleRip/ContentView.swift`** — SwiftUI game experience and preserved account/SmartRent settings access.
- **`LittleRipWidgetExtension/`** — New Game launcher plus preserved SmartRent unlock Control Widget.
- **`tests/TriviaCoreTests.swift`** — deterministic standalone regression harness for game rules, parsing, shuffle, state transitions, retry, cancellation, timeout, and persistence.

AI-generated explanations are educational context, not a guarantee of factual correctness; verify surprising claims independently.

## Manual iOS reset

These apps use a free Apple Developer account, so Apple-controlled provisioning profiles may expire after about 7 days. Say **“reset the iOS app”** in Pi to call `littlerip_ios_reset` once. That single foreground transaction checks the paired iPhone and Xcode Apple Account without attempting sign-in, passwords, or 2FA, quarantines only cached LittleRip profiles, regenerates and signs the app/widget in isolated DerivedData, verifies both embedded profiles and exact expiration timestamps plus code signatures, installs in place without uninstalling or wiping data, and launches it with `devicectl`.

The tool reports the actual embedded profile expiration for both targets. Apple may issue a shorter-lived profile, so no seven-day guarantee is made. There is no launchd, cron, login, or periodic refresh job. `refresh.sh` is only a manual compatibility wrapper around `scripts/littlerip-ios-reset.sh`; local device/team overrides live in the gitignored `local-env.sh`.

## Building and tests

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
xcodebuild -project LittleRip.xcodeproj -scheme LittleRip \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build

swiftc LittleRip/TriviaGameModel.swift LittleRip/TriviaGameController.swift tests/TriviaCoreTests.swift \
  -o /tmp/littlerip-trivia-tests && /tmp/littlerip-trivia-tests
```

## Configuration

- **Bundle ID:** `com.maxautomize.LittleRip`
- **Widget bundle ID:** `com.maxautomize.LittleRip.LittleRipWidgetExtension`
- **App Group:** `group.com.maxautomize.LittleRip`
- **AI connection:** existing authenticated ChatGPT account, model `gpt-5.6-luna`
- **SmartRent credentials:** local/shared App Group values only
