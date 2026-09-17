import Foundation

struct TriviaQuestionBlueprint: Equatable, Sendable {
    let timeLimit: Int

    init(timeLimit: Int = TriviaGameRules.questionTimeLimit) {
        self.timeLimit = max(1, timeLimit)
    }
}

struct TriviaQuestionPrompt {
    static let system = """
    Generate one fresh LittleRip trivia question about understanding reality.
    Imagine awakening after a million years: what exists, what happened, how long has it been, what have we learned?
    Choose freely across human knowledge with obsessive curiosity and radical breadth.
    Make the insight profound and the language blunt, simple and essential.
    Take inspiration from Sutskever, Schopenhauer, Musk, Altman, Thiel and Masonic symbolism.
    Develop new questions from these interests and extend far beyond them:
    Plants before insects; insects as animals; human species and human origins.
    Cellular aging and death; turtles versus flies; mind, motivation and psychosis.
    Confirmed UFO evidence; Younger Dryas causes; dollar inscriptions and their origins.
    Cosmic expansion alternatives; light speed; tensors; neural-network rewards.
    Apollo and Dionysus in The Birth of Tragedy; calculus, trigonometry, binary logic and natural science.
    Use meaningful numbers and elegant relationships alongside history, life and foundational knowledge.
    Use established knowledge, prevailing scientific views and clearly attributed interpretations.
    Write a question under 240 characters, four distinct choices, and exactly one correct answer.
    Answers: a word, phrase, number or equation, at most 7 words and 60 characters.
    Give a one- or two-sentence explanation and return the requested JSON.
    """

    static func make(
        blueprint: TriviaQuestionBlueprint,
        departurePoint: String,
        retryReason: String? = nil
    ) -> String {
        """
        Fresh inspiration: \(departurePoint). Follow a connection into a freely chosen subject.
        Reading and answering time: \(blueprint.timeLimit) seconds.
        \(retryReason.map { "Correction: \($0) Generate a fresh question." } ?? "")
        {"question":"...","choices":["...","...","...","..."],"correctIndex":0,"explanation":"...","concept":"short free-form subject label"}
        """
    }
}
