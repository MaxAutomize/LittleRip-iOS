import Foundation

/// One live question. The model supplies a free-form concept label solely so
/// the game can avoid returning the same underlying idea again.
struct TriviaQuestion: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let prompt: String
    let choices: [String]
    let correctIndex: Int
    let explanation: String
    let concept: String

    init(
        id: String = UUID().uuidString,
        prompt: String,
        choices: [String],
        correctIndex: Int,
        explanation: String,
        concept: String = "Reality"
    ) {
        self.id = id
        self.prompt = prompt
        self.choices = choices
        self.correctIndex = correctIndex
        self.explanation = explanation
        self.concept = concept
    }

    /// Exact prompt deduplication. Semantic repetition is discouraged by the
    /// Model-authored label shown on the card; it is never stored for generation.
    var fingerprint: String {
        prompt
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var correctAnswer: String { choices[correctIndex] }

    func validated() throws -> TriviaQuestion {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...240).contains(cleanedPrompt.count) else {
            throw TriviaQuestionValidationError.invalidPromptLength
        }
        guard choices.count == 4 else {
            throw TriviaQuestionValidationError.mustHaveFourChoices
        }
        guard choices.allSatisfy({
            (1...60).contains($0.trimmingCharacters(in: .whitespacesAndNewlines).count)
                && $0.split(whereSeparator: { $0.isWhitespace }).count <= 7
        }) else {
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
        guard (1...60).contains(concept.trimmingCharacters(in: .whitespacesAndNewlines).count) else {
            throw TriviaQuestionValidationError.invalidConcept
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
            concept: concept
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
    case invalidExplanationLength
    case invalidConcept

    var errorDescription: String? {
        switch self {
        case .malformedJSON: return "The model returned malformed JSON."
        case .responseTooLarge: return "The model response was too large."
        case .mustBeJSONObject: return "The model returned something other than one question object."
        case .missingRequiredField(let field): return "The question is missing \(field)."
        case .invalidPromptLength: return "The model returned an unusable question prompt."
        case .mustHaveFourChoices: return "The model did not return exactly four choices."
        case .invalidChoiceLength: return "Each answer must be at most 7 words and 60 characters."
        case .invalidCorrectIndex: return "The model returned an invalid correct-answer index."
        case .duplicateChoices: return "The model returned duplicate choices."
        case .invalidExplanationLength: return "The model returned an unusable explanation."
        case .invalidConcept: return "The model returned an unusable concept label."
        }
    }
}

/// Parses one live model-generated question. No local difficulty, category or
/// topic vocabulary is required; the concept label is free text.
struct TriviaQuestionParser {
    private struct Payload: Decodable {
        let id: String?
        let question: String
        let choices: [String]
        let correctIndex: Int
        let explanation: String
        let concept: String
    }

    static func parse(_ text: String) throws -> TriviaQuestion {
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
                    concept: payload.concept
                )
                return try question.validated()
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
    static let questionTimeLimit = 35
    static let maxScore = 10_000_000

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
