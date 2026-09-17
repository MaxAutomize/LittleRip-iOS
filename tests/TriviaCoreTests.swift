import Foundation

private struct TestError: Error {}

@MainActor
private final class FakeTriviaProvider: TriviaQuestionProviding {
    var results: [Result<TriviaQuestion, Error>]
    private(set) var assignments: [TriviaQuestionBlueprint] = []

    init(results: [Result<TriviaQuestion, Error>]) {
        self.results = results
    }

    func generateTriviaQuestion(blueprint: TriviaQuestionBlueprint) async throws -> TriviaQuestion {
        assignments.append(blueprint)
        guard !results.isEmpty else { throw TestError() }
        return try results.removeFirst().get()
    }
}

@main
struct TriviaCoreTests {
    @MainActor
    static func main() async {
        testRules()
        testParsingAndShuffle()
        testPromptContract()
        await testStateMachine()
        print("TriviaCoreTests: all deterministic checks passed")
    }

    private static func testRules() {
        precondition(TriviaGameRules.questionTimeLimit == 35)
        precondition(TriviaGameRules.points(forStreak: 0) == 100)
        precondition(TriviaGameRules.points(forStreak: 1) == 200)
        precondition(TriviaGameRules.points(forStreak: 2) == 400)
        precondition(TriviaGameRules.points(forStreak: 40) == TriviaGameRules.maxScore)
        precondition(TriviaGameRules.adding(500, to: TriviaGameRules.maxScore) == TriviaGameRules.maxScore)

        let a = TriviaQuestionBlueprint()
        let b = TriviaQuestionBlueprint()
        precondition(a == b)
        precondition(a.timeLimit == 35)
    }

    private static func testParsingAndShuffle() {
        let fenced = """
        ```json
        {"id":"math-1","question":"A cube's edge doubles. Its volume grows by what factor?","choices":["2×","4×","8×","16×"],"correctIndex":2,"explanation":"Volume scales with the cube of length: 2³ = 8.","concept":"Scale"}
        ```
        """
        let parsed = try! TriviaQuestionParser.parse(fenced)
        precondition(parsed.choices.count == 4)
        precondition(parsed.correctAnswer == "8×")
        precondition(parsed.concept == "Scale")

        var rng = FixedRNG()
        let shuffled = parsed.shuffled(using: &rng)
        precondition(shuffled.correctAnswer == "8×")
        precondition(Set(shuffled.choices) == Set(parsed.choices))

        let duplicate = """
        {"question":"This prompt is long enough to validate.","choices":["same","same","third","fourth"],"correctIndex":0,"explanation":"This explanation is long enough.","concept":"Test"}
        """
        do {
            _ = try TriviaQuestionParser.parse(duplicate)
            preconditionFailure("duplicate choices must be rejected")
        } catch TriviaQuestionValidationError.duplicateChoices {
            // expected
        } catch {
            preconditionFailure("unexpected duplicate-choice error: \(error)")
        }
    }

    private static func testPromptContract() {
        let voice = TriviaQuestionPrompt.system
        precondition(voice.contains("There is no fixed topic list"))
        precondition(voice.contains("no local memory"))
        precondition(voice.contains("There is no increasing difficulty"))
        precondition(voice.contains("The Birth of Tragedy"))
        precondition(voice.contains("numbers and natural structure"))

        let context = TriviaQuestionBlueprint()
        let prompt = TriviaQuestionPrompt.make(blueprint: context)
        precondition(prompt.contains("There is no round tier"))
        precondition(prompt.contains("full universe of knowledge"))
        precondition(!prompt.contains("difficulty"))
        precondition(!prompt.contains("RECENT MEMORY"))
        precondition(prompt.contains("\"concept\":\"short free-form subject label\""))
        precondition(prompt.utf8.count < 4_000)

        let retry = TriviaQuestionPrompt.make(blueprint: context, retryReason: "malformed JSON")
        precondition(retry.contains("different idea"))
    }

    @MainActor
    private static func testStateMachine() async {
        let q1 = question(id: "q1", prompt: "What is the SI unit of time?", choices: ["second", "meter", "joule", "watt"], correctIndex: 0)
        let q2 = question(id: "q2", prompt: "If velocity doubles, what happens to kinetic energy?", choices: ["Half", "Double", "Quadruple", "Zero"], correctIndex: 2)
        let q3 = question(id: "q3", prompt: "Which shape has three equal sides?", choices: ["Circle", "Triangle", "Square", "Line"], correctIndex: 1)

        let suiteName = "littlerip.trivia.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        let provider = FakeTriviaProvider(results: [.success(q1), .success(q2), .success(q3)])
        let game = TriviaGameController(provider: provider, defaults: suite, timeLimitOverride: { _ in 1 })

        game.startNewGame()
        await waitUntil { game.phase == .answering }
        precondition(game.timeLimit == 1)
        game.chooseAnswer(at: game.currentQuestion!.correctIndex)
        precondition(game.lastResult == .correct(points: 100))
        precondition(game.streak == 1)
        precondition(game.phase == .feedback)

        try? await Task.sleep(nanoseconds: 1_400_000_000)
        await waitUntil { game.phase == .answering }
        game.chooseAnswer(at: (game.currentQuestion!.correctIndex + 1) % 4)
        precondition(game.phase == .gameOver)
        precondition(game.lastResult == .incorrect)
        precondition(game.score == 100)
        precondition(game.streak == 0)
        precondition(game.answeredCount == 2)

        let timeoutProvider = FakeTriviaProvider(results: [.success(q3)])
        let timeoutGame = TriviaGameController(provider: timeoutProvider, defaults: suite, timeLimitOverride: { _ in 1 })
        timeoutGame.startNewGame()
        await waitUntil { timeoutGame.phase == .answering }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        await waitUntil { timeoutGame.phase == .gameOver }
        precondition(timeoutGame.lastResult == .timedOut)
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
        correctIndex: Int
    ) -> TriviaQuestion {
        TriviaQuestion(
            id: id,
            prompt: prompt,
            choices: choices,
            correctIndex: correctIndex,
            explanation: "The governing relationship gives one clear answer.",
            concept: "Test concept"
        )
    }
}

private struct FixedRNG: RandomNumberGenerator {
    var state: UInt64 = 0x1234_5678_9ABC_DEF0

    mutating func next() -> UInt64 {
        state = state &* 2862933555777941757 &+ 3037000493
        return state
    }
}
