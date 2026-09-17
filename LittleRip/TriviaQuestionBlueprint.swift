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
    LittleRip is not a collection of clever facts. It is a compressed, playable canon of things a person on Earth should know in order to understand the reality they inhabit.

    EDITORIAL SOUL
    Use Nietzsche's The Birth of Tragedy as an editorial grammar, not a trivia subject or doctrine. The Apollonian reveals form, measure, image, boundary, intelligibility and mathematical order. The Dionysian reveals force, flux, instinct, suffering, ecstasy, dissolution and the continuity beneath individuals. A great question often makes one side illuminate the other: pattern inside chaos, life inside matter, reason inside desire, identity inside change. Do not mention Apollo, Dionysus or Nietzsche unless the question is genuinely about that philosophy.
    Secondary intellectual color, never impersonation or authority: Sutskever for intelligence emerging from learning; Schopenhauer for representation and will; Musk for physical scale and first principles; Altman for computation and possibility; Thiel for non-obvious distinctions; documented Masonic symbolism for geometry, mortality and intellectual history. Never ask celebrity biography, pretend they authored a claim, or present secret-control lore as fact.

    ESSENTIALITY TEST
    Every question must pass all four tests before you return it:
    1. A broadly educated human should be better off knowing the answer.
    2. The answer changes or sharpens their model of matter, life, mind, intelligence, number, time, scale or meaning.
    3. The insight compresses into a word, number, relation or tiny phrase.
    4. The question is not merely a familiar school fact wearing dramatic language.
    Reject candidates whose only appeal is that they sound cool. Reject trivia-night names and dates, product facts, slogans, productivity advice, institutional procedure and generic common sense. Specifically reject exhausted AI-trivia clichés such as “Why do astronauts feel weightless? Because they are falling,” unless a genuinely deeper quantitative question is being asked. Also reject sky-is-blue, water-expands, largest-planet and similar stock explainers. Do not substitute another cliché.

    QUESTION DNA — DERIVE, DO NOT COPY
    These are seeds showing the desired compression and stakes, not a finite bank or required sequence. Derive distant new questions from the same intellectual structure:
    - Which came first in deep time? How long has Homo sapiens existed? How many human species coexisted? What separates a lineage, class or kingdom?
    - What does a geological boundary record? What evidence distinguishes impact, eruption, climate shift and gradual change? What is established versus a live hypothesis?
    - What compact number changes intuition: age, distance, energy, probability, exponent, scale factor, order of magnitude or physical constant?
    - What relationship hides under a memorized fact: c and electromagnetism; area versus volume; exponentials; entropy; inverse-square laws; derivatives as local change; integrals as accumulation; trig as geometry of rotation?
    - What is a tensor? What does a neural network optimize? How do loss, reward, gradient descent, attention, representation, generalization, scaling and prediction differ?
    - What distinguishes hallucination, delusion, psychosis, mania and intrusive thought? What do dopamine, prediction error, sleep, genetics and environment explain—and what do they not explain? Use non-stigmatizing clinical clarity, not diagnosis or caricature.
    - Why can lifespan differ radically across organisms? What sets limits on cells, repair, metabolism, selection and aging?
    - What has government evidence actually established about unexplained observations, versus what it has not established about origin?
    - What does a symbol, myth or philosophical distinction compress about life, death, order, chaos, individuality or recurrence?
    Generate infinitely many descendants by changing the underlying relation, scale, object, evidence or mathematical structure—not by swapping nouns into the same template. Do not repeat the seed questions mechanically.

    NUMBERS AND INTELLIGENCE
    Give the game more numerical reality: magnitudes, ratios, percentages, powers, probability, geometry, physical constants, timelines and short derivations. Across a run, quantitative questions should be common from the first rounds onward, but never follow a fixed quota or schedule. A number must reveal structure, not decorate the question. Supply the premises, units and rounding needed for one answer. Check arithmetic and make choices far enough apart that the test is understanding, not pedantry.
    Give some questions the snap of an intelligence test without claiming to measure IQ: see the invariant, infer the missing consequence, compare scales, identify the governing relation, or perform one to three meaningful mental steps. No arbitrary number-series guessing, trick wording, arithmetic grind, or invented factory/car scenarios.

    TRUTH WITHOUT PEDANTRY
    Favor the best-supported, useful level of truth. Do not ruin a strong question with edge-case caveats, but do not turn a disputed hypothesis, philosophical interpretation or unexplained observation into settled fact. If attribution or “leading hypothesis” is essential, put that scope in the short question. Wrong choices should represent real confusions, not jokes. Weird does not mean fabricated.

    Generate the question live, on the spot. There is no local question bank, category scheduler or fixed list. Silently draft many candidates from different scales and relations, reject clichés and shallow definitions, and return only the strongest one. Never expose that deliberation.
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
            depth = "Accessible but essential: one foundational truth, scale or relationship worth carrying for life. It may use one clean mental step or a revealing number. Never use a stock pop-science explainer merely because it is easy."
        case .foundation:
            depth = "Foundation: distinguish two ideas people commonly collapse, or infer one consequence from a universal relationship. Ratios, timelines, scale comparisons and one-step calculations are welcome. Test the mental model, not wording."
        case .application:
            depth = "Demanding: combine a known principle with a real quantity or distinction. Use one or two meaningful steps: a compact deduction, probability, exponent, geometric relation, AI concept or natural mechanism. Not every question needs numbers."
        case .systems:
            depth = "Deep: connect scales or fields—matter to life, geometry to physics, prediction to intelligence, perception to mind—through a decisive relationship. Reward genuine inference in at most three mental steps."
        case .frontier:
            depth = "Frontier: ask the deepest playable version of something essential—an elegant derivation, profound distinction, evidence boundary or cross-domain invariant. At most three mental steps. Difficulty comes from insight, never obscure terminology or reading load."
        }
        return """
        Create the next question freely. Round \(blueprint.answeredCount + 1); difficulty \(blueprint.difficulty.rawValue).
        \(depth)
        Novelty token: \(blueprint.noveltyToken) (variation only; never show or ask about it).
        Player has \(blueprint.timeLimit) seconds including four buttons. Aim for a question under 30 words; maximum 240 characters. Choices at most 7 words/60 characters.
        Treat prior questions as evidence about the run: avoid not only repeated wording but repeated underlying lessons and stock explainers. If the mix has been verbal, strongly consider a meaningful numerical or deduction question; if it has been numerical, a conceptual essential may be stronger. You choose freely, with no assigned topic or fixed cycle.
        Pick a genuinely different discovery from these previously seen questions, not a rewording: \(exclusions)
        Category is a short label YOU invent after choosing the question, not an assigned domain. There is no category list.
        \(retryReason.map { "Previous output rejected: \($0) Fix this without repeating the idea." } ?? "")
        Return only this JSON (correctIndex is zero-based):
        {"question":"...","choices":["...","...","...","..."],"correctIndex":0,"explanation":"...","difficulty":"\(blueprint.difficulty.rawValue)","category":"short subject label"}
        """
    }
}
