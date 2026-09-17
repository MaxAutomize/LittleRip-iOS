import Foundation

/// The deliberately paced ladder used by Luna when building a run.
enum TriviaDifficulty: String, Codable, CaseIterable, Equatable, Sendable {
    case warmup
    case foundation
    case application
    case systems
    case frontier

    var title: String {
        switch self {
        case .warmup: return "Warm-up"
        case .foundation: return "Foundation"
        case .application: return "Application"
        case .systems: return "Systems"
        case .frontier: return "Frontier"
        }
    }

    var ordinal: Int {
        switch self {
        case .warmup: return 0
        case .foundation: return 1
        case .application: return 2
        case .systems: return 3
        case .frontier: return 4
        }
    }
}

enum TriviaCategory: String, Codable, CaseIterable, Equatable, Sendable {
    case humanNature = "human_nature"
    case history = "history"
    case geography = "geography"
    case economics = "economics"
    case institutions = "institutions"
    case technology = "technology"
    case science = "science"
    case philosophy = "philosophy"
    case futures = "futures"

    var title: String {
        switch self {
        case .humanNature: return "Human Nature"
        case .history: return "History"
        case .geography: return "Geography"
        case .economics: return "Economics"
        case .institutions: return "Power & Institutions"
        case .technology: return "Technology"
        case .science: return "Science & Math"
        case .philosophy: return "Philosophy"
        case .futures: return "Possible Futures"
        }
    }
}

struct TriviaQuestion: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let prompt: String
    let choices: [String]
    let correctIndex: Int
    let explanation: String
    let implication: String
    let difficulty: TriviaDifficulty
    let category: TriviaCategory

    init(
        id: String = UUID().uuidString,
        prompt: String,
        choices: [String],
        correctIndex: Int,
        explanation: String,
        implication: String,
        difficulty: TriviaDifficulty,
        category: TriviaCategory = .science
    ) {
        self.id = id
        self.prompt = prompt
        self.choices = choices
        self.correctIndex = correctIndex
        self.explanation = explanation
        self.implication = implication
        self.difficulty = difficulty
        self.category = category
    }

    /// A normalized prompt is enough to avoid repeating the same idea in one run,
    /// while leaving Luna free to vary wording and answer order.
    var fingerprint: String {
        prompt
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var correctAnswer: String { choices[correctIndex] }

    func validated(expectedDifficulty: TriviaDifficulty? = nil) throws -> TriviaQuestion {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (12...420).contains(cleanedPrompt.count) else {
            throw TriviaQuestionValidationError.invalidPromptLength
        }
        guard choices.count == 4 else {
            throw TriviaQuestionValidationError.mustHaveFourChoices
        }
        guard choices.allSatisfy({ (1...140).contains($0.trimmingCharacters(in: .whitespacesAndNewlines).count) }) else {
            throw TriviaQuestionValidationError.invalidChoiceLength
        }
        guard (0..<choices.count).contains(correctIndex) else {
            throw TriviaQuestionValidationError.invalidCorrectIndex
        }

        let normalizedChoices = choices.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard Set(normalizedChoices).count == choices.count else {
            throw TriviaQuestionValidationError.duplicateChoices
        }
        guard (10...500).contains(explanation.trimmingCharacters(in: .whitespacesAndNewlines).count) else {
            throw TriviaQuestionValidationError.invalidExplanationLength
        }
        guard (10...500).contains(implication.trimmingCharacters(in: .whitespacesAndNewlines).count) else {
            throw TriviaQuestionValidationError.invalidImplicationLength
        }
        if let expectedDifficulty, difficulty != expectedDifficulty {
            throw TriviaQuestionValidationError.unexpectedDifficulty
        }
        guard !fingerprint.isEmpty else {
            throw TriviaQuestionValidationError.invalidPromptLength
        }
        return self
    }

    func shuffled<R: RandomNumberGenerator>(using generator: inout R) -> TriviaQuestion {
        let indexed = choices.enumerated().map { (index: $0.offset, answer: $0.element) }
        let shuffled = indexed.shuffled(using: &generator)
        let newCorrectIndex = shuffled.firstIndex { $0.index == correctIndex } ?? 0
        return TriviaQuestion(
            id: id,
            prompt: prompt,
            choices: shuffled.map(\.answer),
            correctIndex: newCorrectIndex,
            explanation: explanation,
            implication: implication,
            difficulty: difficulty,
            category: category
        )
    }
}

enum TriviaQuestionValidationError: LocalizedError, Equatable {
    case malformedJSON
    case responseTooLarge
    case mustBeJSONObject
    case missingRequiredField(String)
    case invalidPromptLength
    case mustHaveFourChoices
    case invalidChoiceLength
    case invalidCorrectIndex
    case duplicateChoices
    case duplicateQuestion
    case invalidExplanationLength
    case invalidImplicationLength
    case unexpectedDifficulty

    var errorDescription: String? {
        switch self {
        case .malformedJSON: return "Luna returned malformed JSON."
        case .responseTooLarge: return "Luna's response was too large."
        case .mustBeJSONObject: return "Luna returned something other than one question object."
        case .missingRequiredField(let field): return "Luna's question is missing \(field)."
        case .invalidPromptLength: return "Luna returned an unusable question prompt."
        case .mustHaveFourChoices: return "Luna did not return exactly four choices."
        case .invalidChoiceLength: return "Luna returned an unusable answer choice."
        case .invalidCorrectIndex: return "Luna returned an invalid correct-answer index."
        case .duplicateChoices: return "Luna returned duplicate choices."
        case .duplicateQuestion: return "Luna repeated a question from this run."
        case .invalidExplanationLength: return "Luna returned an unusable explanation."
        case .invalidImplicationLength: return "Luna returned an unusable implication."
        case .unexpectedDifficulty: return "Luna returned the wrong difficulty for this round."
        }
    }
}

/// Parses only the typed JSON contract. A small amount of wrapper recovery keeps
/// fenced Markdown from breaking a run, but prose is never accepted as a question.
struct TriviaQuestionParser {
    private struct Payload: Decodable {
        let id: String?
        let question: String
        let choices: [String]
        let correctIndex: Int
        let explanation: String
        let implication: String
        let difficulty: TriviaDifficulty
        let category: TriviaCategory
    }

    static func parse(_ text: String, expectedDifficulty: TriviaDifficulty) throws -> TriviaQuestion {
        guard text.utf8.count <= 12_000 else {
            throw TriviaQuestionValidationError.responseTooLarge
        }

        let trimmed = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TriviaQuestionValidationError.malformedJSON }

        let candidates = candidateJSONStrings(from: trimmed)
        guard !candidates.isEmpty else { throw TriviaQuestionValidationError.malformedJSON }

        var lastError: Error = TriviaQuestionValidationError.malformedJSON
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            do {
                let payload = try JSONDecoder().decode(Payload.self, from: data)
                let question = TriviaQuestion(
                    id: payload.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? payload.id!.trimmingCharacters(in: .whitespacesAndNewlines)
                        : UUID().uuidString,
                    prompt: payload.question,
                    choices: payload.choices,
                    correctIndex: payload.correctIndex,
                    explanation: payload.explanation,
                    implication: payload.implication,
                    difficulty: payload.difficulty,
                    category: payload.category
                )
                return try question.validated(expectedDifficulty: expectedDifficulty)
            } catch {
                lastError = error
            }
        }

        if let validationError = lastError as? TriviaQuestionValidationError {
            throw validationError
        }
        throw TriviaQuestionValidationError.malformedJSON
    }

    private static func candidateJSONStrings(from text: String) -> [String] {
        var candidates: [String] = [text]
        let fenceStripped = text
            .replacingOccurrences(of: "```json", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if fenceStripped != text { candidates.append(fenceStripped) }

        if let first = fenceStripped.firstIndex(of: "{"),
           let last = fenceStripped.lastIndex(of: "}"), first < last {
            let extracted = String(fenceStripped[first...last])
            if !candidates.contains(extracted) { candidates.append(extracted) }
        }
        return candidates
    }
}

struct TriviaGameRules {
    static let basePoints = 100
    /// Scores and each addition saturate at this bound, so malformed or very long
    /// runs can never overflow Int or make the UI unusable.
    static let maxScore = 10_000_000

    static func difficulty(forAnsweredCount count: Int) -> TriviaDifficulty {
        switch max(0, count) {
        case 0...1: return .warmup
        case 2...4: return .foundation
        case 5...8: return .application
        case 9...13: return .systems
        default: return .frontier
        }
    }

    /// Harder questions start with more thinking time. Within each tier, the
    /// modest pressure term tightens as a run grows, with a safe 18-second floor.
    static func timeLimit(for difficulty: TriviaDifficulty, answeredCount: Int) -> Int {
        let base: Int
        switch difficulty {
        case .warmup: base = 24
        case .foundation: base = 29
        case .application: base = 36
        case .systems: base = 44
        case .frontier: base = 54
        }
        let pressure = min(14, max(0, answeredCount) / 2)
        return max(18, base - pressure)
    }

    static func points(forStreak streak: Int) -> Int {
        var points = basePoints
        for _ in 0..<max(0, streak) {
            let (doubled, overflow) = points.multipliedReportingOverflow(by: 2)
            if overflow || doubled > maxScore { return maxScore }
            points = doubled
        }
        return points
    }

    static func adding(_ points: Int, to score: Int) -> Int {
        let safePoints = max(0, points)
        let (sum, overflow) = max(0, score).addingReportingOverflow(safePoints)
        return overflow ? maxScore : min(maxScore, sum)
    }

    static func remainingSeconds(until deadline: UInt64, now: UInt64) -> Int {
        guard deadline > now else { return 0 }
        let nanoseconds = deadline - now
        let roundedUp = nanoseconds > UInt64.max - 999_999_999
            ? UInt64.max
            : (nanoseconds + 999_999_999) / 1_000_000_000
        return Int(clamping: roundedUp)
    }
}