import Foundation

private struct TestError: Error {}

@MainActor
private final class TestMonotonicTime {
    var now: UInt64 = 1_000_000_000_000
}

@MainActor
private final class FakeTriviaProvider: TriviaQuestionProviding {
    var results: [Result<TriviaQuestion, Error>]
    var delays: [UInt64]
    var ignoreCancellation: Bool
    private(set) var callCount = 0

    init(results: [Result<TriviaQuestion, Error>], delays: [UInt64] = [], ignoreCancellation: Bool = false) {
        self.results = results
        self.delays = delays
        self.ignoreCancellation = ignoreCancellation
    }

    func generateTriviaQuestion(
        difficulty: TriviaDifficulty,
        answeredCount: Int,
        excludedFingerprints: Set<String>,
        recentCategories: [TriviaCategory]
    ) async throws -> TriviaQuestion {
        let index = callCount
        callCount += 1
        let delay = index < delays.count ? delays[index] : 0
        guard !results.isEmpty else { throw TestError() }
        // Reserve the response before the delay so a cancelled request cannot
        // accidentally make the replacement request receive the stale payload.
        let result = results.removeFirst()
        if delay > 0 {
            if ignoreCancellation {
                try? await Task.sleep(nanoseconds: delay)
            } else {
                try await Task.sleep(nanoseconds: delay)
            }
        }
        return try result.get()
    }
}

private struct FixedRNG: RandomNumberGenerator {
    var state: UInt64 = 0x1234_5678_9ABC_DEF0

    mutating func next() -> UInt64 {
        state = state &* 2862933555777941757 &+ 3037000493
        return state
    }
}

@main
struct TriviaCoreTests {
    @MainActor
    static func main() async {
        testRules()
        testParsingAndShuffle()
        await testStateMachine()
        print("TriviaCoreTests: all deterministic checks passed")
    }

    private static func testRules() {
        precondition(TriviaGameRules.difficulty(forAnsweredCount: 0) == .warmup)
        precondition(TriviaGameRules.difficulty(forAnsweredCount: 2) == .foundation)
        precondition(TriviaGameRules.difficulty(forAnsweredCount: 5) == .application)
        precondition(TriviaGameRules.difficulty(forAnsweredCount: 9) == .systems)
        precondition(TriviaGameRules.difficulty(forAnsweredCount: 14) == .frontier)
        precondition(TriviaGameRules.timeLimit(for: .frontier, answeredCount: 14) > TriviaGameRules.timeLimit(for: .warmup, answeredCount: 0))
        precondition(TriviaGameRules.timeLimit(for: .application, answeredCount: 8) < TriviaGameRules.timeLimit(for: .application, answeredCount: 5))
        precondition(TriviaGameRules.timeLimit(for: .frontier, answeredCount: 200) == 40)

        precondition(TriviaGameRules.points(forStreak: 0) == 100)
        precondition(TriviaGameRules.points(forStreak: 1) == 200)
        precondition(TriviaGameRules.points(forStreak: 2) == 400)
        precondition(TriviaGameRules.points(forStreak: 40) == TriviaGameRules.maxScore)
        precondition(TriviaGameRules.adding(500, to: TriviaGameRules.maxScore) == TriviaGameRules.maxScore)
        precondition(TriviaGameRules.adding(Int.max, to: TriviaGameRules.maxScore - 1) == TriviaGameRules.maxScore)
    }

    private static func testParsingAndShuffle() {
        let fenced = """
        ```json
        {"id":"warm-1","question":"What is 2 + 2?","choices":["3","4","5","22"],"correctIndex":1,"explanation":"Adding two and two gives four.","implication":"Simple arithmetic is a reliable first step.","difficulty":"warmup","category":"science"}
        ```
        """
        let parsed = try! TriviaQuestionParser.parse(fenced, expectedDifficulty: .warmup)
        precondition(parsed.choices.count == 4)
        precondition(parsed.correctAnswer == "4")

        var rng = FixedRNG()
        let shuffled = parsed.shuffled(using: &rng)
        precondition(shuffled.choices.count == 4)
        precondition(shuffled.correctAnswer == "4")
        precondition(Set(shuffled.choices) == Set(parsed.choices))

        let duplicate = """
        {"question":"This prompt is long enough to validate.","choices":["same","same","third","fourth"],"correctIndex":0,"explanation":"This explanation is long enough.","implication":"This implication is long enough.","difficulty":"warmup","category":"science"}
        """
        do {
            _ = try TriviaQuestionParser.parse(duplicate, expectedDifficulty: .warmup)
            preconditionFailure("duplicate choices must be rejected")
        } catch TriviaQuestionValidationError.duplicateChoices {
            // expected
        } catch {
            preconditionFailure("unexpected duplicate-choice error: \(error)")
        }

        do {
            _ = try TriviaQuestionParser.parse("not json", expectedDifficulty: .warmup)
            preconditionFailure("malformed JSON must be rejected")
        } catch {
            // expected
        }
    }

    @MainActor
    private static func testStateMachine() async {
        let q1 = question(id: "q1", prompt: "What is the SI unit of time?", choices: ["second", "meter", "joule", "watt"], correctIndex: 0)
        let q2 = question(id: "q2", prompt: "If velocity doubles, what happens to kinetic energy?", choices: ["It halves", "It doubles", "It quadruples", "It stays zero"], correctIndex: 2)
        let q3 = question(id: "q3", prompt: "Which shape has three equal sides?", choices: ["Circle", "Triangle", "Square", "Line"], correctIndex: 1)
        let q4 = question(id: "q4", prompt: "What is the simplest prime number?", choices: ["0", "1", "2", "4"], correctIndex: 2)
        let q5 = question(id: "q5", prompt: "Which symbol commonly represents probability?", choices: ["P", "E", "G", "M"], correctIndex: 0)

        let suiteName = "littlerip.trivia.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        let provider = FakeTriviaProvider(results: [.success(q1), .success(q2), .success(q3)])
        let game = TriviaGameController(provider: provider, defaults: suite, timeLimitOverride: { _, _ in 1 })

        game.startNewGame()
        await waitUntil { game.phase == .answering }
        precondition(game.secondsRemaining == 1)
        let firstCorrect = game.currentQuestion!.correctIndex
        game.chooseAnswer(at: firstCorrect)
        precondition(game.lastResult == .correct(points: 100))
        precondition(game.score == 100)
        precondition(game.phase == .feedback)

        try? await Task.sleep(nanoseconds: 1_400_000_000)
        await waitUntil { game.phase == .answering }
        let wrong = (game.currentQuestion!.correctIndex + 1) % 4
        game.chooseAnswer(at: wrong)
        precondition(game.phase == .gameOver)
        precondition(game.lastResult == .incorrect)
        precondition(game.score == 100)
        precondition(game.streak == 0)
        precondition(game.answeredCount == 2)

        let restored = TriviaGameController(provider: FakeTriviaProvider(results: [.success(q3)]), defaults: suite, timeLimitOverride: { _, _ in 1 })
        precondition(restored.bestScore == 100)

        let timeoutProvider = FakeTriviaProvider(results: [.success(q4)])
        let timeoutGame = TriviaGameController(provider: timeoutProvider, defaults: suite, timeLimitOverride: { _, _ in 1 })
        timeoutGame.startNewGame()
        await waitUntil { timeoutGame.phase == .answering }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        await waitUntil { timeoutGame.phase == .gameOver }
        precondition(timeoutGame.lastResult == .timedOut)
        precondition(timeoutGame.gameOverReason == .timeExpired)
        precondition(timeoutGame.score == 0)

        // Deterministic race regression: advance the injected monotonic source
        // beyond the deadline, then tap before the timer task gets a turn.
        let acceptanceTime = TestMonotonicTime()
        let acceptanceProvider = FakeTriviaProvider(results: [.success(q5)])
        let acceptanceGame = TriviaGameController(
            provider: acceptanceProvider,
            defaults: suite,
            timeLimitOverride: { _, _ in 1 },
            monotonicNow: { acceptanceTime.now }
        )
        acceptanceGame.startNewGame()
        await waitUntil { acceptanceGame.phase == .answering }
        acceptanceTime.now += 1_000_000_001
        acceptanceGame.chooseAnswer(at: acceptanceGame.currentQuestion!.correctIndex)
        precondition(acceptanceGame.phase == .gameOver)
        precondition(acceptanceGame.lastResult == .timedOut)
        precondition(acceptanceGame.score == 0)

        let retryProvider = FakeTriviaProvider(results: [.failure(TestError()), .success(q5)])
        let retryGame = TriviaGameController(provider: retryProvider, defaults: suite, timeLimitOverride: { _, _ in 1 })
        retryGame.startNewGame()
        await waitUntil { retryGame.phase == .error }
        precondition(retryGame.score == 0)
        retryGame.retryGeneration()
        await waitUntil { retryGame.phase == .answering }
        precondition(retryGame.currentQuestion?.id == "q5")

        let staleProvider = FakeTriviaProvider(results: [.success(q1), .success(q3)], delays: [400_000_000, 0])
        let staleGame = TriviaGameController(provider: staleProvider, defaults: suite, timeLimitOverride: { _, _ in 1 })
        staleGame.startNewGame()
        try? await Task.sleep(nanoseconds: 30_000_000)
        staleGame.startNewGame()
        await waitUntil { staleGame.phase == .answering }
        precondition(staleGame.currentQuestion?.id == "q3")
        precondition(staleProvider.callCount == 2)

        // Returning home cancels timers/feedback and makes a delayed response
        // stale even when the provider ignores cancellation.
        let homeProvider = FakeTriviaProvider(results: [.success(q1)], delays: [400_000_000], ignoreCancellation: true)
        let homeGame = TriviaGameController(provider: homeProvider, defaults: suite, timeLimitOverride: { _, _ in 1 })
        homeGame.startNewGame()
        try? await Task.sleep(nanoseconds: 30_000_000)
        homeGame.returnToHome()
        precondition(homeGame.phase == .idle)
        precondition(homeGame.currentQuestion == nil)
        precondition(homeGame.score == 0)
        precondition(homeGame.bestScore == 100)
        try? await Task.sleep(nanoseconds: 500_000_000)
        precondition(homeGame.phase == .idle)
        precondition(homeGame.currentQuestion == nil)
        precondition(homeGame.secondsRemaining == 0)
        precondition(homeProvider.callCount == 1)
    }

    @MainActor
    private static func waitUntil(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<60 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        preconditionFailure("timed out waiting for deterministic game state")
    }

    private static func question(
        id: String,
        prompt: String,
        choices: [String],
        correctIndex: Int,
        difficulty: TriviaDifficulty = .warmup
    ) -> TriviaQuestion {
        TriviaQuestion(
            id: id,
            prompt: prompt,
            choices: choices,
            correctIndex: correctIndex,
            explanation: "The underlying rule gives a clear answer from the supplied quantities.",
            implication: "Starting from a small invariant makes the larger idea easier to reason about.",
            difficulty: difficulty
        )
    }
}
