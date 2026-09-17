import Foundation

struct WebSearchResult: Codable, Identifiable {
    let id = UUID()
    let title: String
    let url: String
    /// A verified lead excerpt from the actual Wikipedia article.
    let snippet: String
}

/// Also used by the weather/location lookup service.
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

private struct WikipediaRandomResponse: Decodable {
    let query: Query?

    struct Query: Decodable {
        let random: [RandomPage]?
    }

    struct RandomPage: Decodable {
        let title: String
    }
}

private struct WikipediaSearchResponse: Decodable {
    let query: Query?

    struct Query: Decodable {
        let search: [SearchItem]?
    }

    struct SearchItem: Decodable {
        let title: String
        let snippet: String
    }
}

private struct WikipediaArticleResponse: Decodable {
    let query: Query?

    struct Query: Decodable {
        let pages: [Page]?
    }

    struct Page: Decodable {
        let pageid: Int?
        let title: String
        let extract: String?
        let description: String?
    }
}

/// Wikipedia research is deliberately two-stage:
/// 1. ChatGPT's Wiki planner understands the complete user idea and chooses
///    canonical articles (passed as `plannedTopics`).
/// 2. This client verifies each title against Wikipedia and retrieves a real
///    lead excerpt before the answering model is allowed to respond.
///
/// Keyword search exists only as a recovery path when a selected title does not
/// resolve, never as the normal way of inventing a pile of loosely related links.
final class WebSearchClient {
    /// Returns one fresh encyclopedic departure point. It is deliberately only
    /// a jump-off signal for trivia generation, never a stored question bank or
    /// a claim that the final question is about this page.
    static func randomDiscoverySeed() async -> String? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "list", value: "random"),
            URLQueryItem(name: "rnnamespace", value: "0"),
            URLQueryItem(name: "rnlimit", value: "1")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("LittleRip/1.0 (iOS trivia generation)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let decoded = try? JSONDecoder().decode(WikipediaRandomResponse.self, from: data),
              let title = decoded.query?.random?.first?.title.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        return title
    }

    static func search(
        _ query: String,
        history: String = "",
        plannedTopics: [String] = []
    ) async -> [WebSearchResult] {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = cleanTopics(plannedTopics)
        let userWantsPersonOrWork = questionWantsPeopleOrCreativeWorks(question)

        // Keep the planner's order. The planner has already considered the whole
        // intent and session context, so it is the authority for source order.
        var selected: [WebSearchResult] = []
        for topic in plan.prefix(6) {
            if let article = await resolvePlannedArticle(
                named: topic,
                question: question,
                allowsPeopleOrWorks: userWantsPersonOrWork
            ) {
                appendUnique(article, to: &selected)
            }
        }

        // If an article name was invalid or the planner was temporarily
        // unavailable, recover from Wikipedia itself. Do not append a broad tail
        // after a successful plan; that was what made old Wiki cards feel random.
        if selected.count < min(3, max(plan.count, 3)) {
            let fallbackQuery = fallbackSearchQuery(question: question, history: history)
            if let candidates = await wikipediaSearch(fallbackQuery) {
                let needed = max(3 - selected.count, 1)
                let fallback = await bestFallbackArticles(
                    from: candidates,
                    for: question,
                    allowsPeopleOrWorks: userWantsPersonOrWork,
                    maximum: needed
                )
                for article in fallback {
                    appendUnique(article, to: &selected)
                }
            }
        }

        if !selected.isEmpty {
            return Array(selected.prefix(6))
        }

        // A tappable search page is only the final network-failure fallback.
        let fallback = cleanedFallbackTopic(from: question)
        return [WebSearchResult(
            title: "Search Wikipedia: \(fallback)",
            url: "https://en.wikipedia.org/w/index.php?search=\(encodeQuery(fallback))",
            snippet: "Wikipedia could not return an article right now. Tap to search Wikipedia for this topic."
        )]
    }

    /// Resolves a model-selected title to a real Wikipedia page, including a
    /// lead excerpt. A miss is corrected with Wikipedia's own title search.
    private static func resolvePlannedArticle(
        named requestedTitle: String,
        question: String,
        allowsPeopleOrWorks: Bool
    ) async -> WebSearchResult? {
        if let exact = await wikipediaArticle(named: requestedTitle),
           isUsefulArticle(exact, allowsPeopleOrWorks: allowsPeopleOrWorks) {
            return exact
        }

        guard let candidates = await wikipediaSearch(requestedTitle) else { return nil }
        return await bestFallbackArticles(
            from: candidates,
            for: requestedTitle,
            allowsPeopleOrWorks: allowsPeopleOrWorks,
            maximum: 1
        ).first
    }

    /// Fetches a canonical page title, redirect-resolved, plus actual lead text.
    /// This is deliberately not an OpenSearch description: it is article content
    /// sent to the answering model as its Wikipedia research material.
    private static func wikipediaArticle(named title: String) async -> WebSearchResult? {
        guard let url = wikipediaAPIURL([
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exchars", value: "1200"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "titles", value: title)
        ]) else { return nil }

        guard let data = await wikipediaData(from: url),
              let response = try? JSONDecoder().decode(WikipediaArticleResponse.self, from: data),
              let page = response.query?.pages?.first(where: { $0.pageid != nil }),
              page.pageid != nil else {
            return nil
        }

        let description = page.description?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let extract = page.extract?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let excerpt: String
        if !description.isEmpty, !extract.isEmpty {
            excerpt = "\(description.capitalized). \(extract)"
        } else if !extract.isEmpty {
            excerpt = extract
        } else if !description.isEmpty {
            excerpt = description.capitalized
        } else {
            return nil
        }

        return WebSearchResult(
            title: page.title,
            url: wikiURL(for: page.title),
            snippet: cleanWikiText(excerpt)
        )
    }

    private static func wikipediaSearch(_ query: String) async -> [WebSearchResult]? {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let url = wikipediaAPIURL([
                URLQueryItem(name: "list", value: "search"),
                URLQueryItem(name: "srsearch", value: cleaned),
                URLQueryItem(name: "srlimit", value: "8"),
                URLQueryItem(name: "srnamespace", value: "0")
              ]),
              let data = await wikipediaData(from: url),
              let response = try? JSONDecoder().decode(WikipediaSearchResponse.self, from: data) else {
            return nil
        }

        let results = (response.query?.search ?? []).map { item in
            WebSearchResult(
                title: item.title,
                url: wikiURL(for: item.title),
                snippet: cleanWikiText(item.snippet)
            )
        }
        return results.isEmpty ? nil : results
    }

    /// Used only after the semantic plan cannot resolve enough sources. It still
    /// enriches and filters search hits before returning them, rather than showing
    /// raw matching titles as if they were research.
    private static func bestFallbackArticles(
        from candidates: [WebSearchResult],
        for question: String,
        allowsPeopleOrWorks: Bool,
        maximum: Int
    ) async -> [WebSearchResult] {
        var scored: [(article: WebSearchResult, score: Int)] = []

        for candidate in candidates.prefix(8) {
            guard let article = await wikipediaArticle(named: candidate.title),
                  isUsefulArticle(article, allowsPeopleOrWorks: allowsPeopleOrWorks) else {
                continue
            }
            scored.append((article, fallbackRelevanceScore(article, question: question)))
        }

        return uniqueResults(scored
            .sorted { $0.score > $1.score }
            .map(\.article))
            .prefix(maximum)
            .map { $0 }
    }

    private static func fallbackRelevanceScore(_ article: WebSearchResult, question: String) -> Int {
        let title = normalizedText(article.title)
        let excerpt = normalizedText(article.snippet)
        let terms = significantTerms(from: question)
        let titleWords = Set(title.split(separator: " ").map(String.init))
        let excerptWords = Set(excerpt.split(separator: " ").map(String.init))

        var score = 0
        score += terms.intersection(titleWords).count * 260
        score += terms.intersection(excerptWords).count * 55
        for term in terms where title.contains(term) {
            score += 90
        }
        if isInformationalConceptPage(title: title, excerpt: excerpt) { score += 240 }
        if article.snippet.count > 250 { score += 80 }
        return score
    }

    private static func isUsefulArticle(_ article: WebSearchResult, allowsPeopleOrWorks: Bool) -> Bool {
        let title = normalizedText(article.title)
        let excerpt = normalizedText(article.snippet)
        guard !title.isEmpty, !excerpt.isEmpty else { return false }
        if title.hasPrefix("category ") || title.hasPrefix("list of ") || title.contains("disambiguation") || title.contains("timeline") {
            return false
        }
        if !allowsPeopleOrWorks && isPeopleOrMediaPage(title: title, excerpt: excerpt) {
            return false
        }
        return true
    }

    private static func questionWantsPeopleOrCreativeWorks(_ question: String) -> Bool {
        let normalized = normalizedText(question)
        let terms = significantTerms(from: question)
        if normalized.hasPrefix("who is") || normalized.hasPrefix("who was") { return true }
        if normalized.contains(" biography") || normalized.contains(" born") || normalized.contains(" died") { return true }
        let requestSignals: Set<String> = [
            "actor", "actress", "album", "artist", "author", "band", "biography", "book", "character", "director", "episode", "film",
            "movie", "musician", "novel", "person", "president", "rapper", "series", "show", "singer", "song", "tv", "writer"
        ]
        return !terms.intersection(requestSignals).isEmpty
    }

    private static func isPeopleOrMediaPage(title: String, excerpt: String) -> Bool {
        let text = "\(title) \(excerpt)"
        let signals = [
            "actor", "actress", "album", "animated series", "anime", "artist", "band", "character", "comedy series", "drama series",
            "episode", "fictional", "film", "manga", "movie", "musician", "novel", "record producer", "rapper", "singer", "sitcom",
            "song", "soundtrack", "television series", "tv series", "video game", "web series", "youtuber"
        ]
        return signals.contains { text.contains($0) }
    }

    private static func isInformationalConceptPage(title: String, excerpt: String) -> Bool {
        let text = "\(title) \(excerpt)"
        let signals = [
            "academic discipline", "algorithm", "branch of", "chemical", "concept", "device", "effect", "engineering", "field of",
            "force", "form of", "law", "mathematical", "method", "model", "network", "phenomenon", "philosophy", "principle",
            "process", "protocol", "science", "scientific", "system", "technique", "technology", "theory", "type of"
        ]
        return signals.contains { text.contains($0) }
    }

    private static func fallbackSearchQuery(question: String, history: String) -> String {
        let cleaned = cleanedFallbackTopic(from: question)
        // For a short follow-up, retain a small amount of immediately preceding
        // context so Wikipedia can recover even if the planner request failed.
        let terms = significantTerms(from: cleaned)
        guard terms.count <= 3, !history.isEmpty else { return cleaned }
        let context = history.components(separatedBy: .newlines)
            .suffix(6)
            .joined(separator: " ")
        let contextTerms = significantTermArray(from: context).prefix(5).joined(separator: " ")
        return contextTerms.isEmpty ? cleaned : "\(contextTerms) \(cleaned)"
    }

    private static func cleanedFallbackTopic(from question: String) -> String {
        var topic = question
            .replacingOccurrences(of: "^[Ww]iki(?:pedia)?(?: search)?\\s*[:,-]?\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if topic.isEmpty { topic = question }
        return topic
    }

    private static func wikipediaAPIURL(_ items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2")
        ] + items
        return components?.url
    }

    private static func wikipediaData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.setValue("LittleRip/1.0 (iOS Wikipedia research; contact: support@littlerip.app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private static func cleanTopics(_ topics: [String]) -> [String] {
        var seen = Set<String>()
        return topics.compactMap { raw in
            let cleaned = raw
                .replacingOccurrences(of: "^[•\\-\\d.\\s]+", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\\\"'"))
            guard cleaned.count >= 2, cleaned.count <= 120 else { return nil }
            let key = normalizedText(cleaned)
            guard !key.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return cleaned
        }
    }

    private static func appendUnique(_ article: WebSearchResult, to articles: inout [WebSearchResult]) {
        let key = article.url.lowercased()
        guard !articles.contains(where: { $0.url.lowercased() == key }) else { return }
        articles.append(article)
    }

    private static func uniqueResults(_ articles: [WebSearchResult]) -> [WebSearchResult] {
        var unique: [WebSearchResult] = []
        for article in articles {
            appendUnique(article, to: &unique)
        }
        return unique
    }

    private static func significantTerms(from text: String) -> Set<String> {
        Set(significantTermArray(from: text))
    }

    private static func significantTermArray(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "because", "been", "but", "by", "can", "could", "did", "do", "does",
            "for", "from", "give", "had", "has", "have", "he", "her", "here", "him", "his", "how", "i", "if", "in", "into", "is",
            "it", "its", "just", "like", "look", "me", "more", "my", "of", "on", "or", "please", "question", "really", "say", "search",
            "she", "should", "so", "that", "the", "their", "them", "then", "there", "these", "they", "this", "to", "use", "used", "was",
            "we", "were", "what", "when", "where", "which", "who", "why", "wiki", "wikipedia", "will", "with", "work", "works", "would", "you", "your"
        ]

        let words = normalizedText(text).split(separator: " ").map(String.init)
        var ordered: [String] = []
        var seen = Set<String>()
        for word in words {
            var token = word
            if token.hasSuffix("s"), token.count > 4 { token = String(token.dropLast()) }
            guard (token.count > 2 || ["ai", "ac", "dc"].contains(token)), !stopWords.contains(token), !seen.contains(token) else {
                continue
            }
            seen.insert(token)
            ordered.append(token)
        }
        return ordered
    }

    private static func normalizedText(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "&amp;", with: " and ")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wikiURL(for title: String) -> String {
        let encoded = title
            .replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title.replacingOccurrences(of: " ", with: "_")
        return "https://en.wikipedia.org/wiki/\(encoded)"
    }

    private static func encodeQuery(_ text: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text.replacingOccurrences(of: " ", with: "+")
    }

    private static func cleanWikiText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
