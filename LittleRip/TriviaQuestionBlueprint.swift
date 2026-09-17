import Foundation

/// A loose assignment for one round: difficulty tier + suggested domain.
/// The model has full freedom to pick any concrete topic within the domain.
/// No skill curriculum, no editorial test, no rigid form requirements.
struct TriviaQuestionBlueprint: Equatable, Sendable {
    let difficulty: TriviaDifficulty
    let answeredCount: Int
    let category: TriviaCategory

    var timeLimit: Int { TriviaGameRules.timeLimit(for: difficulty, answeredCount: answeredCount) }
}

struct TriviaEditorialPlan {
    /// Pick a random domain, balanced so every domain appears before any
    /// domain repeats too often. Never repeat the last 2 domains.
    static func make<R: RandomNumberGenerator>(
        difficulty: TriviaDifficulty,
        answeredCount: Int,
        categoryHistory: [TriviaCategory],
        using random: inout R
    ) -> TriviaQuestionBlueprint {
        let count = max(0, answeredCount)
        let history = Array(categoryHistory.suffix(18))
        let candidates = TriviaCategory.allCases.filter { !history.suffix(2).contains($0) }
        let visits = Dictionary(grouping: history, by: { $0 }).mapValues(\.count)
        let fewest = candidates.map { visits[$0, default: 0] }.min() ?? 0
        let balanced = candidates.filter { visits[$0, default: 0] == fewest }
        let category = balanced.randomElement(using: &random) ?? .science
        return TriviaQuestionBlueprint(difficulty: difficulty, answeredCount: count, category: category)
    }
}

struct TriviaQuestionPrompt {
    static let system = """
    You are the question engine for LittleRip, a game about the hidden structure of reality. \
    Generate one surprising, true, blunt question. The correct answer should land like an axiom — short, distinct, irreducible. \
    Four short answers: a word, phrase, number, or compact idea. Never sentences. \
    One correct answer. Three plausible distractors from real misconceptions, not random nonsense. \
    Plain text only. No Markdown, no LaTeX, no chain of thought. No hypothetical scenarios or invented examples.
    """

    static func make(
        blueprint: TriviaQuestionBlueprint,
        excludedFingerprints: Set<String>,
        retryReason: String? = nil
    ) -> String {
        let prior = excludedFingerprints.sorted().prefix(12).map { String($0.prefix(420)) }
        let exclusions = prior.isEmpty ? "none" : prior.joined(separator: " | ")

        let tierGuide: String
        switch blueprint.difficulty {
        case .warmup:
            tierGuide = "Recognize a surprising concrete fact. Anyone could know it; few have noticed it."
        case .foundation:
            tierGuide = "One step of inference from a concrete fact. Distinguish cause from correlation."
        case .application:
            tierGuide = "Apply a principle to a real case. Math questions should require actual calculation."
        case .systems:
            tierGuide = "Two interacting mechanisms. Include a tradeoff or bottleneck that defeats the obvious answer."
        case .frontier:
            tierGuide = "Connect two domains. The correct answer must follow from explicit facts, not speculative expertise."
        }

        let mathNudge = blueprint.answeredCount >= 5
            ? "\nAt higher tiers, include questions that require real calculation or mathematical understanding (rates, ratios, constants, trig, calculus, geometry)."
            : ""

        return """
        Round \(blueprint.answeredCount + 1). Tier: \(blueprint.difficulty.rawValue).
        \(tierGuide)
        Domain: \(blueprint.category.rawValue) — \(blueprint.category.topicHint)
        Pick any concrete topic within this domain. No predictable lesson plan. \
        Ask what exists, what came first, what something means, what causes it. \
        Not hypothetical scenarios, generic common sense, classroom exercises, or invented examples about cars and factories.\(mathNudge)
        Player has \(blueprint.timeLimit) seconds including reading four buttons. Question under 60 words. Each choice under 8 words.
        Exactly one correct answer. Distractors from distinct real misconceptions (wrong cause, reversal, scale error, wrong unit, common myth), not random nonsense.
        Explanation: 1–2 short sentences stating the decisive fact or mechanism. No lesson pitch, no citation invented from memory.
        Avoid these earlier question ideas, even reworded: \(exclusions)
        \(retryReason.map { "Previous output rejected: \($0) Fix that defect." } ?? "")

        Return ONLY this JSON (correctIndex is zero-based):
        {"question":"...","choices":["...","...","...","..."],"correctIndex":0,"explanation":"...","difficulty":"\(blueprint.difficulty.rawValue)","category":"\(blueprint.category.rawValue)"}
        """
    }
}
