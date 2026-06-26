import Foundation

struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let think: Bool
    let system: String
}

struct OllamaGenerateResponse: Decodable {
    let response: String?
    let thinking: String?
    let error: String?
}

enum OllamaClientError: LocalizedError {
    case invalidURL
    case badResponse(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Ollama URL."
        case .badResponse(let code, let body):
            return "Ollama error \(code): \(body)"
        case .emptyResponse:
            return "Ollama returned an empty response."
        }
    }
}

struct OllamaResult {
    let answer: String
    let thinking: String
    let sources: [WebSearchResult]
}

final class OllamaClient {
    private let baseURL: URL
    private let model: String
    private let apiKey: String

    init(baseURLString: String = "https://ollama.com", model: String = "glm-5.1", apiKey: String = LittleRipSecrets.ollamaAPIKey) throws {
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw OllamaClientError.invalidURL
        }
        self.baseURL = url
        self.model = model
        self.apiKey = apiKey
    }

    func ask(_ prompt: String, sources: [WebSearchResult], history: String = "") async throws -> OllamaResult {
        let searchContext: String
        if sources.isEmpty {
            searchContext = ""
        } else {
            let sourceTexts = sources.prefix(6).enumerated().map { index, s in
                "[\(index + 1)] \(s.title)\n    URL: \(s.url)\n    Description: \(s.snippet)"
            }.joined(separator: "\n")
            searchContext = """

            WIKIPEDIA SEARCH RESULTS (use these to answer accurately and cite sources):
            \(sourceTexts)
            """
        }

        let systemPrompt = """
        You are LittleRip, a professional AI assistant integrated into an iPhone application.

        Use current session context to understand follow-up questions, pronouns, and references. This context lasts only while the app session is alive; do not imply permanent memory. Use Wikipedia search results as the primary source material when they are provided. Use high-effort internal reasoning: compare the user's question against the Wikipedia titles/descriptions, ignore irrelevant pages, and ground the answer in the most relevant article(s).

        Respond in a clear, professional manner using these exact section labels, without numbers:
        DEFINITION: Provide a dictionary-style overview of what the user is asking about. Format it as the term followed by a concise definition, like a dictionary entry.
        EXPLANATION: Add a brief, clear explanation (two to three sentences) suitable for both reading and text-to-speech.
        ANALOGY: Provide an everyday analogy that makes the concept easy to understand.
        FIRST PRINCIPLES: Break down the concept to its most fundamental truths — the irreducible facts of reality that underlie it.

        Do NOT number the section labels. Do NOT include a "Sources" section in your text response. The Wikipedia source links are displayed separately at the bottom of the screen. Just provide the four sections above.

        Guidelines:
        - The dictionary definition must come FIRST, before any other content.
        - Be concise and authoritative.
        - Dictionary descriptions for sources should be brief: one line defining what the source is.
        - If no web results are relevant, provide the definition and explanation from your own knowledge without the sources section.
        - Do not use markdown formatting. Use plain text only.
        - Reason deeply before responding. In your hidden thinking, identify the core topic, check which Wikipedia result is most relevant, then compose the final answer.
        """

        let historyContext = history.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : """

        CURRENT SESSION CONTEXT:
        \(history)

        """

        let fullPrompt = "\(historyContext)USER'S CURRENT QUESTION:\n\(prompt)\(searchContext)"

        let endpoint = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = OllamaGenerateRequest(
            model: model,
            prompt: fullPrompt,
            stream: false,
            think: true,
            system: systemPrompt
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "Request failed"
            throw OllamaClientError.badResponse(statusCode, bodyText)
        }

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        if let error = decoded.error, !error.isEmpty {
            throw OllamaClientError.badResponse(statusCode, error)
        }
        guard let text = decoded.response?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw OllamaClientError.emptyResponse
        }

        return OllamaResult(
            answer: text,
            thinking: decoded.thinking ?? "",
            sources: sources
        )
    }
}