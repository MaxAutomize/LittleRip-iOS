import Foundation

struct WebSearchResult: Codable, Identifiable {
    let id = UUID()
    let title: String
    let url: String
    let snippet: String
}

struct DuckDuckGoResponse: Decodable {
    let AbstractText: String?
    let AbstractURL: String?
    let Heading: String?
    let Definition: String?
    let DefinitionURL: String?
    let RelatedTopics: [RelatedTopic]?

    struct RelatedTopic: Decodable {
        let Text: String?
        let FirstURL: String?
        let Topics: [RelatedTopic]?
    }
}

struct WikipediaResponse: Decodable {
    let query: Query?

    struct Query: Decodable {
        let search: [SearchItem]?
    }

    struct SearchItem: Decodable {
        let title: String
        let snippet: String
    }
}

struct TopicGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let think: Bool
    let system: String
}

struct TopicGenerateResponse: Decodable {
    let response: String?
}

final class WebSearchClient {
    static func search(_ query: String, history: String = "") async -> [WebSearchResult] {
        // Wikipedia-only search. The topic list is chosen semantically using the
        // current question plus recent session context, so vague follow-ups still
        // produce relevant Wiki links.
        let lexicalTopic = wikipediaTopic(from: query)
        let semanticTitles = await semanticWikipediaTopics(for: query, history: history, cleanedTopic: lexicalTopic, primaryTitle: lexicalTopic)
        let resolvedTopic = semanticTitles.first ?? lexicalTopic

        let primaryCandidates = await searchWikipedia(resolvedTopic) ?? []
        let primary = primaryCandidates.sorted { relevanceScore($0, topic: resolvedTopic) > relevanceScore($1, topic: resolvedTopic) }.first

        var combined: [WebSearchResult] = []
        if let primary { combined.append(primary) }

        for title in semanticTitles {
            if let first = (await searchWikipedia(title))?.sorted(by: { relevanceScore($0, topic: title) > relevanceScore($1, topic: title) }).first {
                combined.append(first)
            }
        }

        combined.append(contentsOf: primaryCandidates)

        var seen = Set<String>()
        let unique = combined.filter { result in
            if seen.contains(result.url) { return false }
            seen.insert(result.url)
            return true
        }

        if !unique.isEmpty { return Array(unique.prefix(8)) }

        // Never silently omit sources: if article lookup fails, show a clickable
        // Wikipedia search link so the user still gets a source area.
        let encoded = resolvedTopic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? resolvedTopic.replacingOccurrences(of: " ", with: "+")
        return [WebSearchResult(
            title: "Wikipedia search: \(resolvedTopic)",
            url: "https://en.wikipedia.org/w/index.php?search=\(encoded)",
            snippet: "Wikipedia search results for the resolved topic: \(resolvedTopic)."
        )]
    }

    private static func searchDuckDuckGo(_ query: String) async -> [WebSearchResult]? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let ddg = try JSONDecoder().decode(DuckDuckGoResponse.self, from: data)
            var results: [WebSearchResult] = []

            if let abstract = ddg.AbstractText, !abstract.isEmpty {
                let title = ddg.Heading ?? "Summary"
                let snippet = abstract
                let urlStr = ddg.AbstractURL ?? ""
                if !urlStr.isEmpty {
                    results.append(WebSearchResult(title: title, url: urlStr, snippet: snippet))
                }
            }

            if let definition = ddg.Definition, !definition.isEmpty {
                let urlStr = ddg.DefinitionURL ?? ""
                if !urlStr.isEmpty {
                    results.append(WebSearchResult(title: "Definition", url: urlStr, snippet: definition))
                }
            }

            for topic in ddg.RelatedTopics ?? [] {
                if let text = topic.Text, let urlStr = topic.FirstURL, !text.isEmpty {
                    let title = text.components(separatedBy: " - ").first ?? text
                    let snippet = text.components(separatedBy: " - ").dropFirst().joined(separator: " - ")
                    results.append(WebSearchResult(title: String(title.prefix(80)), url: urlStr, snippet: snippet.isEmpty ? title : snippet))
                }
                for sub in topic.Topics ?? [] {
                    if let text = sub.Text, let urlStr = sub.FirstURL, !text.isEmpty {
                        let title = text.components(separatedBy: " - ").first ?? text
                        let snippet = text.components(separatedBy: " - ").dropFirst().joined(separator: " - ")
                        results.append(WebSearchResult(title: String(title.prefix(80)), url: urlStr, snippet: snippet.isEmpty ? title : snippet))
                    }
                }
            }

            return results.isEmpty ? nil : results
        } catch {
            return nil
        }
    }

    private static func searchWikipedia(_ query: String) async -> [WebSearchResult]? {
        let topic = wikipediaTopic(from: query)

        // OpenSearch is better for "find the actual article for this topic" than full text search.
        if let openSearchResults = await wikipediaOpenSearch(topic), !openSearchResults.isEmpty {
            return openSearchResults
        }

        guard let encoded = topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encoded)&format=json&srlimit=5") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let wiki = try JSONDecoder().decode(WikipediaResponse.self, from: data)
            return (wiki.query?.search ?? []).map { item in
                let cleanSnippet = cleanWikiText(item.snippet)
                let wikiURL = "https://en.wikipedia.org/wiki/\(item.title.replacingOccurrences(of: " ", with: "_"))"
                return WebSearchResult(title: item.title, url: wikiURL, snippet: cleanSnippet)
            }
        } catch {
            return nil
        }
    }

    private static func wikipediaOpenSearch(_ topic: String) async -> [WebSearchResult]? {
        guard let encoded = topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://en.wikipedia.org/w/api.php?action=opensearch&search=\(encoded)&limit=5&namespace=0&format=json") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  json.count >= 4,
                  let titles = json[1] as? [String],
                  let descriptions = json[2] as? [String],
                  let urls = json[3] as? [String] else { return nil }

            return titles.enumerated().compactMap { index, title in
                guard index < urls.count else { return nil }
                let desc = index < descriptions.count ? descriptions[index] : "Wikipedia article about \(title)."
                return WebSearchResult(title: title, url: urls[index], snippet: desc.isEmpty ? "Wikipedia article about \(title)." : desc)
            }
        } catch {
            return nil
        }
    }

    private static func semanticWikipediaTopics(for query: String, history: String, cleanedTopic: String, primaryTitle: String) async -> [String] {
        guard let url = URL(string: "https://ollama.com/api/generate") else { return [] }

        let prompt = """
        Recent session context:
        \(history.isEmpty ? "No prior context." : history)

        Current user question: \(query)
        Lexically cleaned topic: \(cleanedTopic)
        Initial guess: \(primaryTitle)

        Return ONLY a compact JSON array of 6 to 8 Wikipedia article titles.
        The first title must be the best primary/canonical article for the user's CURRENT question after resolving it against the recent session context.
        The remaining titles must be semantically related by meaning, theme, prerequisite knowledge, people, organizations, mechanisms, or neighboring concepts.
        Do NOT pick pages merely because the words look similar.
        If the current question is vague ("what about him", "what would he say", "this", "that"), infer the missing subject from recent session context before choosing titles.

        Examples:
        - If topic is H-bridge: ["H-bridge", "DC motor", "Power electronics", "MOSFET", "Pulse-width modulation", "Motor controller", "Electric motor"]
        - If topic is physics: ["Physics", "Classical mechanics", "Quantum mechanics", "General relativity", "Electromagnetism", "Thermodynamics", "Particle physics"]
        - If topic is ChatGPT: ["ChatGPT", "Large language model", "OpenAI", "Generative pre-trained transformer", "Reinforcement learning from human feedback", "Sam Altman", "Claude", "Google DeepMind"]
        """

        let body = TopicGenerateRequest(
            model: "glm-5.1",
            prompt: prompt,
            stream: false,
            think: false,
            system: "You select semantically relevant Wikipedia article titles. Output only valid JSON."
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(LittleRipSecrets.ollamaAPIKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return fallbackSemanticTopics(cleanedTopic, primaryTitle: primaryTitle) }
            let decoded = try JSONDecoder().decode(TopicGenerateResponse.self, from: data)
            guard let text = decoded.response else { return fallbackSemanticTopics(cleanedTopic, primaryTitle: primaryTitle) }
            return parseTopicArray(text).isEmpty ? fallbackSemanticTopics(cleanedTopic, primaryTitle: primaryTitle) : parseTopicArray(text)
        } catch {
            return fallbackSemanticTopics(cleanedTopic, primaryTitle: primaryTitle)
        }
    }

    private static func parseTopicArray(_ text: String) -> [String] {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end else { return [] }
        let jsonText = String(text[start...end])
        guard let data = jsonText.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        var seen = Set<String>()
        return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { title in
                if seen.contains(title.lowercased()) { return false }
                seen.insert(title.lowercased())
                return true
            }
    }

    private static func fallbackSemanticTopics(_ topic: String, primaryTitle: String) -> [String] {
        let t = topic.lowercased()
        if t.contains("h bridge") || t.contains("h-bridge") {
            return ["H-bridge", "DC motor", "Power electronics", "MOSFET", "Pulse-width modulation", "Motor controller", "Electric motor"]
        }
        if t.contains("physics") {
            return ["Physics", "Classical mechanics", "Quantum mechanics", "General relativity", "Electromagnetism", "Thermodynamics", "Particle physics"]
        }
        if t.contains("chatgpt") || t.contains("chat gpt") {
            return ["ChatGPT", "Large language model", "OpenAI", "Generative pre-trained transformer", "Reinforcement learning from human feedback", "Sam Altman", "Claude", "Google DeepMind"]
        }
        return [primaryTitle]
    }

    private static func wikipediaTopic(from query: String) -> String {
        var topic = query.lowercased()
        topic = topic.replacingOccurrences(of: "[?!.:,;]", with: " ", options: .regularExpression)
        let prefixes = [
            "what is the", "what is a", "what is an", "what is", "what are the", "what are",
            "who is", "who was", "define", "definition of", "explain the", "explain",
            "tell me about the", "tell me about", "give me an overview of", "overview of",
            "can you explain", "please explain", "i want to know about"
        ]
        for prefix in prefixes {
            if topic.hasPrefix(prefix + " ") {
                topic = String(topic.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        let suffixes = ["in simple terms", "for me", "briefly", "with sources", "from wikipedia", "on wikipedia"]
        for suffix in suffixes {
            if topic.hasSuffix(" " + suffix) {
                topic = String(topic.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        topic = topic.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return topic.isEmpty ? query : topic
    }

    private static func relevanceScore(_ result: WebSearchResult, topic: String) -> Int {
        let title = result.title.lowercased()
        let snippet = result.snippet.lowercased()
        let topic = topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var score = 0

        if title == topic { score += 1000 }
        if title.hasPrefix(topic) { score += 500 }
        if title.contains(topic) { score += 350 }
        if topic.contains(title), title.count > 3 { score += 250 }
        if snippet.contains(topic) { score += 100 }

        let topicWords = Set(topic.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let titleWords = Set(title.split(separator: " ").map(String.init))
        score += topicWords.intersection(titleWords).count * 40

        // Prefer canonical concept pages over category/list/timeline pages.
        if title.hasPrefix("category:") || title.contains("list of") || title.contains("timeline") { score -= 120 }
        if title.contains("disambiguation") { score -= 200 }

        return score
    }

    private static func cleanWikiText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}