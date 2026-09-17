# LittleRip for iOS

LittleRip is a compact, chrome/silver/black/white trivia game with the existing robot and green-eye visual language. Each run serves four-choice questions generated dynamically through the user's authenticated ChatGPT account.

## Game loop

- Home is intentionally minimal: the robot, **New Game**, and the durable best score.
- The chat-bubble button is labeled **Back to menu**. One tap immediately abandons the current run, cancels generation/timers/feedback, clears transient state, and returns home without confirmation or starting another game. Best score is preserved. A stale response from a cancelled request cannot re-enter the run.
- In-game UI is limited to score, best, streak, answered count, category, difficulty, timer, next reward, one question, and exactly four shuffled answer buttons.
- The model returns one validated JSON question with exactly four unique answer choices, one correct index, a concise explanation, and a category. Choices are shuffled on-device while preserving the correct answer.
- **The game is a cabinet of revelations.** Questions pull surprising truths from evolution, civilization, the mind, philosophy, AI, physics, and mathematics. The pleasure is: *"I never thought about it that way—and the answer is so simple."* Short, blunt questions. Four tiny, sharply distinct answers: a word, phrase, number, or compact idea—not sentences. Not boilerplate hypothetical scenarios, generic common sense, or invented car/factory stories. Real discoveries, fundamental relationships, powerful ideas, and compact deductions.
- **Reality beyond human systems:** the central question is “what is this thing we are in?” The model chooses the discovery on the spot, without a topic menu, category scheduler, example bank or human-institutions bias. Subject labels are free text generated afterward, not constraints. Hypotheses and interpretations must be distinguished from established knowledge.
- **Question-setter voice:** restless, intensely curious, fascinated by strange connections—not a textbook narrator. Sutskever, Schopenhauer, Musk, Altman, Thiel and documented Masonic symbolism are editorial touchstones, not impersonations, endorsements, a topic menu or a source of factual authority. Keep the core beyond human institutions.
- **Numerical bite:** loosely aim for about a third numerical/quantitative questions, including early rounds, mixed with conceptual discoveries. The model chooses the mix; no local quotas or deterministic scheduler. Short deductions have an intelligence-puzzle feel, not an IQ assessment. Prefer insightful scale, ratios, probability and elegant math over calculation grind; state needed units, rules and rounding. Generation quality and this approximate mix are prompt-guided, not guaranteed by structural tests.
- **Earned difficulty:** round context supplies only depth, timing, prior-question exclusions and a fresh novelty token. Depth grows from accessible discoveries to profound relationships and mathematical understanding. No mandatory calculation, tradeoff or bottleneck. Answers are enforced at at most 7 words/60 characters; stems at most 240 characters. Tokens vary requests but do not guarantee semantic novelty.
- Each blueprint includes the actual timer budget, concise buttons, and misconception-based distractors. Established facts only; contested ideas must be attributed and bounded. Retries retain the same blueprint and receive the validation failure; no extra serial AI call is added.
- Correct answers show brief points feedback, then automatically load the next question. Wrong answers and time expiration end the run and reveal the correct answer, a straightforward explanation, score, and **New Game**.
- Network, authentication, cancellation, or malformed/invalid responses are retryable loading errors, never wrong answers and never score penalties. Malformed model payloads are retried up to three times. If authentication is needed, the game shows only a contextual sign-in affordance; there is no permanent settings UI.
- Trivia requests use reasoning effort `medium`. Reasoning effort is not a guarantee of diversity or factual accuracy.

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

- **`LittleRip/TriviaGameModel.swift`** — typed question/category/explanation contract, bounded JSON/wrapper parsing, validation, shuffle, difficulty, timer, and saturating score rules.
- **`LittleRip/TriviaQuestionBlueprint.swift`** — round depth/timer/novelty context and open-ended reality prompt; no category scheduler or fixed question bank.
- **`LittleRip/TriviaGameController.swift`** — main-actor game state machine, return-home cancellation, stale-result guards, monotonic timer, persistence, feedback, and retry behavior.
- **`LittleRip/ChatGPTCodexClient.swift`** — authenticated ChatGPT client with the world-understanding question contract.
- **`LittleRip/ContentView.swift`** — minimal SwiftUI game experience with preserved robot styling and contextual sign-in only when required.
- **`LittleRipWidgetExtension/`** — no-microphone New Game launcher plus the preserved SmartRent unlock Control Widget.
- **`tests/TriviaCoreTests.swift`** — deterministic standalone regression harness for rules, parsing, shuffle, state transitions, retry, cancellation, return-home, timeout and persistence; also checks fresh request tokens, free subject labels, concise-answer limits and prompt budgets.

Local validation checks shape, expected tier, and exact normalized-text repeats, not factual truth. Generation quality still depends on the model; verify surprising claims independently.

## Manual iOS reset

These apps use a free Apple Developer account, so Apple-controlled provisioning profiles may expire after about 7 days. Say **"reset the iOS app"** in Pi to call `littlerip_ios_reset` once. That single foreground transaction checks the paired iPhone and Xcode Apple Account without attempting sign-in, passwords, or 2FA, quarantines only cached LittleRip profiles, regenerates and signs the app/widget in isolated DerivedData, verifies both embedded profiles and exact expiration timestamps plus code signatures, installs in place without uninstalling or wiping data, and launches it with `devicectl`.

The tool reports the actual embedded profile expiration for both targets. Apple may issue a shorter-lived profile, so no seven-day guarantee is made. There is no launchd, cron, login, or periodic refresh job. `refresh.sh` is only a manual compatibility wrapper around `scripts/littlerip-ios-reset.sh`; local device/team overrides live in the gitignored `local-env.sh`.

## Building and tests

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
xcodebuild -project LittleRip.xcodeproj -scheme LittleRip \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build

swiftc LittleRip/TriviaGameModel.swift LittleRip/TriviaQuestionBlueprint.swift \
  LittleRip/TriviaGameController.swift tests/TriviaCoreTests.swift \
  -parse-as-library -o /tmp/littlerip-trivia-tests && /tmp/littlerip-trivia-tests
# Optional prompt review: writes /tmp/littlerip-prompts.txt
/tmp/littlerip-trivia-tests --dump-prompts
```

## Configuration

- **Bundle ID:** `com.maxautomize.LittleRip`
- **Widget bundle ID:** `com.maxautomize.LittleRip.LittleRipWidgetExtension`
- **App Group:** `group.com.maxautomize.LittleRip`
- **AI connection:** existing authenticated ChatGPT account
- **Reasoning effort:** medium (normal)
- **SmartRent credentials:** local/shared App Group values only
