import Foundation

/// Public, read-only Hacker News discovery via Firebase's official API and Algolia's HN search API.
enum HackerNewsService {
    private static let firebase = "https://hacker-news.firebaseio.com/v0"
    private static let algolia = "https://hn.algolia.com/api/v1"

    static func context(for prompt: String) async -> String? {
        let query = normalizedQuery(prompt)
        if query.isEmpty || query == "top" || query == "top stories" || query == "latest" {
            return await topStoriesContext()
        }
        return await searchContext(query: query)
    }

    private static func topStoriesContext() async -> String? {
        guard let idsURL = URL(string: "\(firebase)/topstories.json") else { return nil }
        do {
            var request = URLRequest(url: idsURL)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let ids = try JSONSerialization.jsonObject(with: data) as? [Int] else { return nil }

            let selected = Array(ids.prefix(10))
            let stories = await withTaskGroup(of: Story?.self) { group in
                for id in selected {
                    group.addTask { await story(id: id) }
                }
                var values: [Story] = []
                for await result in group {
                    if let result { values.append(result) }
                }
                return values.sorted { selected.firstIndex(of: $0.id) ?? .max < selected.firstIndex(of: $1.id) ?? .max }
            }
            guard !stories.isEmpty else { return nil }
            return "Hacker News top stories — \(ISO8601DateFormatter().string(from: Date()))\n\n" + stories.enumerated().map { index, story in
                "\(index + 1). \(story.title)\n\(story.points) points · \(story.comments) comments · by \(story.author)\n\(story.url)\nDiscussion: https://news.ycombinator.com/item?id=\(story.id)"
            }.joined(separator: "\n\n")
        } catch {
            return "Hacker News top-story lookup failed: \(error.localizedDescription)"
        }
    }

    private static func searchContext(query: String) async -> String? {
        var components = URLComponents(string: "\(algolia)/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "tags", value: "story"),
            URLQueryItem(name: "hitsPerPage", value: "10")
        ]
        guard let url = components?.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let responseData = try? JSONDecoder().decode(SearchResponse.self, from: data),
                  !responseData.hits.isEmpty else { return nil }
            return "Hacker News search results for ‘\(query)’ — \(ISO8601DateFormatter().string(from: Date()))\n\n" + responseData.hits.enumerated().map { index, hit in
                let title = hit.title ?? hit.storyTitle ?? "Untitled"
                let articleURL = hit.url ?? hit.storyURL ?? "https://news.ycombinator.com/item?id=\(hit.objectID)"
                return "\(index + 1). \(title)\n\(hit.points ?? 0) points · \(hit.numComments ?? 0) comments · by \(hit.author ?? "unknown")\n\(articleURL)\nDiscussion: https://news.ycombinator.com/item?id=\(hit.objectID)"
            }.joined(separator: "\n\n")
        } catch {
            return "Hacker News search failed: \(error.localizedDescription)"
        }
    }

    private static func story(id: Int) async -> Story? {
        guard let url = URL(string: "\(firebase)/item/\(id).json") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let item = try? JSONDecoder().decode(Item.self, from: data),
              item.type == "story", let title = item.title else { return nil }
        return Story(
            id: item.id,
            title: title,
            url: item.url ?? "https://news.ycombinator.com/item?id=\(item.id)",
            points: item.score ?? 0,
            comments: item.descendants ?? 0,
            author: item.by ?? "unknown"
        )
    }

    private static func normalizedQuery(_ prompt: String) -> String {
        prompt
            .replacingOccurrences(of: "hacker news", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "show me", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "what are", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "stories", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private struct Item: Decodable {
        let id: Int
        let type: String
        let title: String?
        let url: String?
        let score: Int?
        let descendants: Int?
        let by: String?
    }

    private struct Story {
        let id: Int
        let title: String
        let url: String
        let points: Int
        let comments: Int
        let author: String
    }

    private struct SearchResponse: Decodable {
        let hits: [SearchHit]
    }

    private struct SearchHit: Decodable {
        let objectID: String
        let title: String?
        let storyTitle: String?
        let url: String?
        let storyURL: String?
        let points: Int?
        let numComments: Int?
        let author: String?

        enum CodingKeys: String, CodingKey {
            case objectID, title, url, points, author
            case storyTitle = "story_title"
            case storyURL = "story_url"
            case numComments = "num_comments"
        }
    }
}
