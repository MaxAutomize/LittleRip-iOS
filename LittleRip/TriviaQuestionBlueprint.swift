import Foundation

/// Round context only. No local topic selector, question bank, or curriculum.
/// The nonce varies otherwise identical opening requests; it does not select a topic.
struct TriviaQuestionBlueprint: Equatable, Sendable {
    let difficulty: TriviaDifficulty
    let answeredCount: Int
    let noveltyToken: String = UUID().uuidString

    var timeLimit: Int { TriviaGameRules.timeLimit(for: difficulty, answeredCount: answeredCount) }
}

struct TriviaQuestionPrompt {
    static let system = """
    LittleRip is a playable encounter with reality: what is this thing we are in?
    Not primarily how humans organize society or operate machines, but the existence we find ourselves inside. Choose freely across reality, beyond human concerns. No fixed topic menu or lesson sequence.
    The reward is a revelation: something real becomes strange, understandable or beautiful in one short answer. Universal does not mean abstract jargon. Ask about the thing itself, not a technical label the player has memorized. Go beyond people without excluding life, mind or mathematics as parts of nature.
    Generate one fresh question on the spot, its four choices, correct index and explanation. Do not pick from a stock set of favorite trivia. Vary subject, scale and kind of discovery without cycling a list. No invented scenarios, institutional trivia, efficiency puzzles, generic common sense, or speculative future situations.
    Be blunt without being false. Exactly one choice must be correct for the question as worded. Established knowledge is not the same as a hypothesis, philosophical interpretation or unresolved mystery. Attribute a theory in the question when testing it; do not invent certainty about ultimate questions. Simplify language, not truth. Avoid pedantic traps and differences too small to matter.
    Short question; four tiny answers, usually 1–5 words, at most 7 words/60 characters each. A number, relationship or equation is welcome. Three plausible distinct wrong answers, not jokes or paragraph-length caveats. Explanation: 1–2 clear short sentences revealing why. Plain Unicode math. Return only the requested JSON, no reasoning transcript.
    """

    static func make(
        blueprint: TriviaQuestionBlueprint,
        excludedFingerprints: Set<String>,
        retryReason: String? = nil
    ) -> String {
        let prior = excludedFingerprints.sorted().prefix(100).map { String($0.prefix(240)) }
        let exclusions = prior.isEmpty ? "none" : prior.joined(separator: " | ")
        let depth: String
        switch blueprint.difficulty {
        case .warmup:
            depth = "Accessible: a surprising reality stated in everyday language, answerable in seconds. Not a trivial vocabulary quiz."
        case .foundation:
            depth = "A little deeper: a less obvious fact or distinction about what exists or how it works."
        case .application:
            depth = "Demanding: understanding a fundamental relationship, not just recognizing a familiar phrase."
        case .systems:
            depth = "Deep: an unexpected connection or a subtle distinction with a simple decisive answer. No mandatory tradeoff or bottleneck."
        case .frontier:
            depth = "Very demanding: profound relationships, precise conceptual distinctions or elegant mathematics. Keep increasing depth as the round grows, never reading burden or jargon."
        }
        return """
        Create the next question freely. Round \(blueprint.answeredCount + 1); difficulty \(blueprint.difficulty.rawValue).
        \(depth)
        Novelty token: \(blueprint.noveltyToken) (variation only; never show or ask about it).
        Player has \(blueprint.timeLimit) seconds including four buttons. Aim for a question under 30 words; maximum 240 characters. Choices at most 7 words/60 characters.
        Pick a genuinely different discovery from these previously seen questions, not a rewording: \(exclusions)
        Category is a short label YOU invent after choosing the question, not an assigned domain. There is no category list.
        \(retryReason.map { "Previous output rejected: \($0) Fix this without repeating the idea." } ?? "")
        Return only this JSON (correctIndex is zero-based):
        {"question":"...","choices":["...","...","...","..."],"correctIndex":0,"explanation":"...","difficulty":"\(blueprint.difficulty.rawValue)","category":"short subject label"}
        """
    }
}
