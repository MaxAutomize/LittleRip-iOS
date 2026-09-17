# LittleRip for iOS

LittleRip is a compact, chrome/silver/black/white trivia game with the existing robot and green-eye visual language. Each run serves four-choice questions generated dynamically through the user's authenticated ChatGPT account using **GPT-5.6 Luna**.

## Game loop

- Home is intentionally minimal: the robot, **New Game**, and the durable best score.
- The chat-bubble button is labeled **Back to menu**. One tap immediately abandons the current run, cancels generation/timers/feedback, clears transient state, and returns home without confirmation or starting another game. Best score is preserved. A stale response from a cancelled request cannot re-enter the run.
- In-game UI is limited to score, best, streak, answered count, category, difficulty, timer, next reward, one question, and exactly four shuffled answer buttons.
- Luna returns one strictly validated JSON question with exactly four unique answer choices, one correct index, a short explanation, an implication, and a category. Choices are shuffled on-device while preserving the correct answer.
- The central theme is understanding what is really going on in the world. Categories intentionally rotate across human nature/psychology, history/civilizations, natural and cultural geography, economics/incentives, power/institutions, technology/AI/intelligence, science/math/energy, epistemology/philosophy, and conditional possible futures. Questions seek mechanisms and first-principles connections rather than cheap trivia or repeated physics.
- The inspiration range may include Einstein, Ilya Sutskever, Schopenhauer, Elon Musk, Sam Altman, Freemasonry, Peter Thiel, Freud, Yuval Noah Harari, and Graham Hancock only as intellectual context—not celebrity biographies, impersonation, endorsements, conspiracy-as-fact, or claims about what a person believes.
- Warm-up questions are genuinely simple. Difficulty then progresses through Foundation, Application, Systems, and Frontier. Established facts must have one defensible answer; contested ideas are attributed as theories; future questions test conditional causal mechanisms rather than certain predictions or unavailable current news. “Derive the equation” prompts select a derivation step/equation and never require text entry.
- Correct answers briefly show the explanation and implication, then automatically load the next question. Wrong answers and time expiration end the run and reveal the correct answer, explanation, implication, score, and **New Game**.
- Network, authentication, cancellation, or malformed/invalid responses are retryable loading errors, never wrong answers and never score penalties. Malformed model payloads are retried up to three times. If authentication is needed, the game shows only a contextual sign-in affordance; there is no permanent settings UI.

## Scoring and timer

- The first correct answer earns 100 points. Each consecutive correct answer doubles the next reward: 100, 200, 400, 800, … . Scores and additions saturate at 10,000,000 so arithmetic cannot overflow.
- A miss resets the streak. Best score is stored in `UserDefaults` and survives relaunches.
- Harder tiers have longer base windows (Warm-up/Foundation/Application/Systems/Frontier = 24/29/36/44/54 seconds). Within a tier, subtract `min(14, answeredCount / 2)`, never below 18 seconds. The timer starts only after a valid question installs.
- Timing uses monotonic `DispatchTime`, not wall-clock time. Answer acceptance checks the deadline before locking the answer; timer callbacks and foreground reconciliation use the same deadline. Main-actor serialization prevents answer/timer races, duplicate taps, suspension/background timing exploits, stale generation, and overflow.

## Account and SmartRent

ChatGPT device login, Keychain credential storage, refresh, sign-out, and security behavior remain in `ChatGPTCodexClient.swift`; authentication values are never logged. The game no longer requests microphone or location access. The former voice launcher is a no-microphone New Game launcher.

The SmartRent flow remains independent of the game and its existing lock-screen Control Widget remains functional:

- **`Shared/SmartRentClient.swift`** logs in, finds the front-door `entry_control` lock, and sends the unlock command over the Phoenix websocket.
- **`Shared/UnlockFrontDoorIntent.swift`** powers the existing one-tap Control Widget.
- SmartRent credentials remain local/shared App Group values and are never committed.
- The app UI intentionally exposes no SmartRent controls or door copy. Existing SmartRent widget credentials, storage, API, and intent code are unchanged.

## Source layout

- **`LittleRip/TriviaGameModel.swift`** — typed question/category contract, bounded JSON/wrapper parsing, validation, shuffle, difficulty, timer, and saturating score rules.
- **`LittleRip/TriviaGameController.swift`** — main-actor game state machine, category history, return-home cancellation, stale-result guards, monotonic timer, persistence, feedback, and retry behavior.
- **`LittleRip/ChatGPTCodexClient.swift`** — existing authenticated ChatGPT client, now using `gpt-5.6-luna` and the world-understanding question contract.
- **`LittleRip/ContentView.swift`** — minimal SwiftUI game experience with preserved robot styling and contextual sign-in only when required.
- **`LittleRipWidgetExtension/`** — no-microphone New Game launcher plus the preserved SmartRent unlock Control Widget.
- **`tests/TriviaCoreTests.swift`** — deterministic standalone regression harness for rules, parsing, shuffle, state transitions, retry, cancellation, return-home, timeout, and persistence.

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
