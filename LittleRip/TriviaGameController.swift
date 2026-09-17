import Combine
import Foundation

@MainActor
protocol TriviaQuestionProviding: AnyObject {
    func generateTriviaQuestion(
        blueprint: TriviaQuestionBlueprint
    ) async throws -> TriviaQuestion
}

enum TriviaGamePhase: Equatable {
    case idle
    case generating
    case answering
    case feedback
    case gameOver
    case error
}

enum TriviaGameOverReason: Equatable {
    case wrongAnswer
    case timeExpired
}

enum TriviaAnswerResult: Equatable {
    case correct(points: Int)
    case incorrect
    case timedOut
}

enum TriviaGameError: LocalizedError {
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .generationFailed(let message):
            return message
        }
    }
}

/// Main-actor state machine for one run. All answer, timeout, and generation
/// transitions happen serially here, so a late timer cannot beat a tap and a
/// cancelled request cannot install a stale question.
@MainActor
final class TriviaGameController: ObservableObject {
    @Published private(set) var phase: TriviaGamePhase = .idle
    @Published private(set) var currentQuestion: TriviaQuestion?
    @Published private(set) var selectedAnswerIndex: Int?
    @Published private(set) var lastResult: TriviaAnswerResult?
    @Published private(set) var gameOverReason: TriviaGameOverReason?
    @Published private(set) var errorMessage: String?
    @Published private(set) var score = 0
    @Published private(set) var bestScore: Int
    @Published private(set) var streak = 0
    @Published private(set) var answeredCount = 0
    @Published private(set) var secondsRemaining = 0
    @Published private(set) var timeLimit = 0

    private let provider: any TriviaQuestionProviding
    private let defaults: UserDefaults
    private let bestScoreKey = "littlerip.trivia.best-score.v2"
    private let legacyBestScoreKey = "littlerip.trivia.best-score.v1"
    private let timeLimitOverride: ((Int) -> Int)?
    /// DispatchTime is monotonic and is not affected by wall-clock changes or
    /// an app being suspended. The closure is injectable for deterministic tests.
    private let monotonicNow: () -> UInt64

    private var generationTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var roundToken = UUID()
    private var questionDeadline: UInt64?
    private var answerLocked = false
    private var pendingBlueprint: TriviaQuestionBlueprint?

    init(
        provider: any TriviaQuestionProviding,
        defaults: UserDefaults = .standard,
        timeLimitOverride: ((Int) -> Int)? = nil,
        monotonicNow: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.provider = provider
        self.defaults = defaults
        self.timeLimitOverride = timeLimitOverride
        self.monotonicNow = monotonicNow
        defaults.removeObject(forKey: legacyBestScoreKey)
        self.bestScore = min(TriviaGameRules.maxScore, max(0, defaults.integer(forKey: bestScoreKey)))
    }

    deinit {
        generationTask?.cancel()
        timerTask?.cancel()
        feedbackTask?.cancel()
    }

    var nextReward: Int {
        TriviaGameRules.points(forStreak: streak)
    }

    var isAnswering: Bool { phase == .answering && !answerLocked }

    func startNewGame() {
        cancelTasks()
        roundToken = UUID()
        currentQuestion = nil
        selectedAnswerIndex = nil
        lastResult = nil
        gameOverReason = nil
        errorMessage = nil
        score = 0
        streak = 0
        answeredCount = 0
        secondsRemaining = 0
        timeLimit = 0
        answerLocked = false
        phase = .generating
        requestQuestion(for: roundToken)
    }

    /// Abandons every in-flight operation and returns to the clean home menu.
    /// Rotating the token makes even a non-cooperative provider response stale.
    func returnToHome() {
        cancelTasks()
        roundToken = UUID()
        currentQuestion = nil
        selectedAnswerIndex = nil
        lastResult = nil
        gameOverReason = nil
        errorMessage = nil
        score = 0
        streak = 0
        answeredCount = 0
        secondsRemaining = 0
        timeLimit = 0
        answerLocked = false
        phase = .idle
    }

    /// Retrying generation deliberately does not reset score, streak, or the
    /// completed-question count. Only a valid question starts the timer.
    func retryGeneration() {
        guard phase == .error else { return }
        errorMessage = nil
        phase = .generating
        requestQuestion(for: roundToken)
    }

    func chooseAnswer(at index: Int) {
        guard phase == .answering,
              !answerLocked,
              let question = currentQuestion,
              question.choices.indices.contains(index) else { return }

        // Reconcile against the monotonic deadline before accepting the tap. The
        // timer task can be delayed by suspension or scheduling, so a visible
        // answer must never win after its deadline.
        if let deadline = questionDeadline, monotonicNow() >= deadline {
            timeout(for: roundToken)
            return
        }

        // This is the single linearization point shared with the timer callback.
        answerLocked = true
        timerTask?.cancel()
        timerTask = nil
        questionDeadline = nil
        selectedAnswerIndex = index
        answeredCount += 1

        if index == question.correctIndex {
            streak += 1
            let earned = TriviaGameRules.points(forStreak: streak - 1)
            score = TriviaGameRules.adding(earned, to: score)
            persistBestScoreIfNeeded()
            lastResult = .correct(points: earned)
            phase = .feedback
            scheduleFeedbackAdvance(for: roundToken)
        } else {
            streak = 0
            lastResult = .incorrect
            gameOverReason = .wrongAnswer
            phase = .gameOver
        }
    }

    private func requestQuestion(for token: UUID) {
        if pendingBlueprint == nil {
            pendingBlueprint = TriviaQuestionBlueprint()
        }
        guard let blueprint = pendingBlueprint else { return }
        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let question = try await self.provider.generateTriviaQuestion(blueprint: blueprint)
                try Task.checkCancellation()
                self.install(question, for: token, blueprint: blueprint)
            } catch is CancellationError {
                // Starting a new game intentionally cancels the previous request.
            } catch {
                self.generationFailed(error, for: token)
            }
        }
    }

    private func install(_ question: TriviaQuestion, for token: UUID, blueprint: TriviaQuestionBlueprint) {
        guard token == roundToken, phase == .generating else { return }
        do {
            _ = try question.validated()
        } catch {
            generationFailed(error, for: token)
            return
        }

        var generator = SystemRandomNumberGenerator()
        let presented = question.shuffled(using: &generator)
        pendingBlueprint = nil
        currentQuestion = presented
        selectedAnswerIndex = nil
        lastResult = nil
        gameOverReason = nil
        answerLocked = false
        errorMessage = nil
        let limit = timeLimitOverride?(answeredCount) ?? blueprint.timeLimit
        timeLimit = max(1, limit)
        secondsRemaining = timeLimit
        phase = .answering
        startTimer(for: token, limit: timeLimit)
    }

    private func generationFailed(_ error: Error, for token: UUID) {
        guard token == roundToken, phase == .generating else { return }
        timerTask?.cancel()
        timerTask = nil
        questionDeadline = nil
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        errorMessage = message.isEmpty ? "LittleRip could not load a question. Try again." : message
        phase = .error
    }

    private func startTimer(for token: UUID, limit: Int) {
        timerTask?.cancel()
        let now = monotonicNow()
        let seconds = UInt64(limit)
        let interval = seconds > UInt64.max / 1_000_000_000
            ? UInt64.max
            : seconds * 1_000_000_000
        let (candidateDeadline, overflow) = now.addingReportingOverflow(interval)
        let deadline = overflow ? UInt64.max : candidateDeadline
        questionDeadline = deadline

        timerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 200_000_000)
                } catch {
                    return
                }
                guard token == self.roundToken,
                      self.phase == .answering,
                      self.questionDeadline == deadline else { return }

                let now = self.monotonicNow()
                if now >= deadline {
                    self.timeout(for: token)
                    return
                }
                self.secondsRemaining = TriviaGameRules.remainingSeconds(until: deadline, now: now)
            }
        }
    }

    /// Called when returning to the foreground so an expired question is ended
    /// immediately even if the timer task was suspended.
    func reconcileTimer() {
        guard phase == .answering, !answerLocked, let deadline = questionDeadline else { return }
        let now = monotonicNow()
        if now >= deadline {
            timeout(for: roundToken)
        } else {
            secondsRemaining = TriviaGameRules.remainingSeconds(until: deadline, now: now)
        }
    }

    private func timeout(for token: UUID) {
        guard token == roundToken, phase == .answering, !answerLocked else { return }
        guard currentQuestion != nil else { return }
        answerLocked = true
        timerTask?.cancel()
        timerTask = nil
        questionDeadline = nil
        answeredCount += 1
        streak = 0
        lastResult = .timedOut
        gameOverReason = .timeExpired
        secondsRemaining = 0
        phase = .gameOver
    }

    /// Correct feedback is intentionally brief, then the next question loads
    /// automatically. The timer is not running during this feedback phase.
    private func scheduleFeedbackAdvance(for token: UUID) {
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_250_000_000)
            } catch {
                return
            }
            guard let self, token == self.roundToken, self.phase == .feedback else { return }
            self.currentQuestion = nil
            self.selectedAnswerIndex = nil
            self.lastResult = nil
            self.phase = .generating
            self.requestQuestion(for: token)
        }
    }

    private func persistBestScoreIfNeeded() {
        guard score > bestScore else { return }
        bestScore = score
        defaults.set(bestScore, forKey: bestScoreKey)
    }

    private func cancelTasks() {
        pendingBlueprint = nil
        generationTask?.cancel()
        timerTask?.cancel()
        feedbackTask?.cancel()
        generationTask = nil
        timerTask = nil
        feedbackTask = nil
        questionDeadline = nil
    }
}