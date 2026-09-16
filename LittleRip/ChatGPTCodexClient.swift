import Foundation
import Security
import UIKit

struct ChatGPTResult {
    let answer: String
    let thinking: String
}

enum ChatGPTReplyMode {
    case quick
    case wiki
    case wikiPlanning
    case assistantActionPlanning
}

enum ChatGPTCodexError: LocalizedError {
    case invalidResponse(String)
    case loginExpired
    case notAuthenticated
    case missingAccountID
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return message
        case .loginExpired:
            return "ChatGPT sign-in expired. Please try again."
        case .notAuthenticated:
            return "Connect your ChatGPT account before using LittleRip."
        case .missingAccountID:
            return "The ChatGPT login did not include an account ID."
        case .emptyResponse:
            return "GPT-5.6 Terra returned an empty response."
        }
    }
}

@MainActor
final class ChatGPTCodexClient: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isSigningIn = false
    @Published private(set) var deviceCode: String?
    @Published private(set) var errorMessage: String?

    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let authBaseURL = URL(string: "https://auth.openai.com")!
    private static let codexURL = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
    private static let deviceRedirectURI = "https://auth.openai.com/deviceauth/callback"
    private static let verificationURL = URL(string: "https://auth.openai.com/codex/device")!
    private static let keychainService = "com.maxautomize.LittleRip.chatgpt-codex"
    private static let keychainAccount = "oauth"
    private static let pendingLoginKey = "chatgpt.codex.pending-device-login"
    private static let userAgent = "LittleRip/1.0 (iOS)"

    private var credentials: Credentials?
    private var loginTask: Task<Void, Never>?

    init() {
        credentials = Self.loadCredentials()
        isAuthenticated = credentials != nil

        if !isAuthenticated, let pending = Self.loadPendingLogin(), pending.expiresAt > Date() {
            deviceCode = pending.userCode
        } else if !isAuthenticated {
            Self.clearPendingLogin()
        }
    }

    deinit {
        loginTask?.cancel()
    }

    func startLogin() {
        guard !isSigningIn, !isAuthenticated else { return }

        if let pending = Self.loadPendingLogin(), pending.expiresAt > Date() {
            runLogin(with: pending, openBrowser: true)
        } else {
            Self.clearPendingLogin()
            runLogin(with: nil, openBrowser: true)
        }
    }

    func resumeLoginIfNeeded() {
        guard !isSigningIn, !isAuthenticated,
              let pending = Self.loadPendingLogin(), pending.expiresAt > Date() else {
            return
        }
        runLogin(with: pending, openBrowser: false)
    }

    private func runLogin(with existingDevice: DeviceCode?, openBrowser: Bool) {
        isSigningIn = true
        errorMessage = nil

        loginTask = Task { [weak self] in
            guard let self else { return }

            do {
                let device: DeviceCode
                if let existingDevice {
                    device = existingDevice
                } else {
                    device = try await Self.requestDeviceCode()
                    try Self.savePendingLogin(device)
                    deviceCode = device.userCode
                    UIPasteboard.general.string = device.userCode
                }

                if openBrowser {
                    await UIApplication.shared.open(Self.verificationURL)
                }

                let authorization = try await Self.pollForAuthorization(device)
                let newCredentials = try await Self.exchangeAuthorizationCode(
                    authorization.code,
                    verifier: authorization.verifier
                )

                try Self.saveCredentials(newCredentials)
                Self.clearPendingLogin()
                credentials = newCredentials
                isAuthenticated = true
                isSigningIn = false
                deviceCode = nil
                errorMessage = nil
                loginTask = nil
            } catch is CancellationError {
                isSigningIn = false
                loginTask = nil
            } catch {
                isSigningIn = false
                errorMessage = error.localizedDescription
                loginTask = nil

                if Date() >= (Self.loadPendingLogin()?.expiresAt ?? .distantPast) {
                    Self.clearPendingLogin()
                    deviceCode = nil
                }
            }
        }
    }

    func openVerificationPage() {
        Task {
            await UIApplication.shared.open(Self.verificationURL)
        }
    }

    func copyDeviceCode() {
        guard let deviceCode else { return }
        UIPasteboard.general.string = deviceCode
    }

    func signOut() {
        loginTask?.cancel()
        loginTask = nil
        credentials = nil
        isAuthenticated = false
        isSigningIn = false
        deviceCode = nil
        errorMessage = nil
        Self.deleteCredentials()
        Self.clearPendingLogin()
    }

    /// Uses the authenticated reasoning model to select the small set of real
    /// Wikipedia articles that best explain the user's whole idea. This is a
    /// research-planning pass, not an answer, and its titles are verified against
    /// Wikipedia by `WebSearchClient` before they reach the UI.
    func planWikipediaArticles(prompt: String, history: String = "") async throws -> [String] {
        // Prefer a deep reasoning pass, but retain a compatible retry for an
        // account/backend that only accepts the standard medium effort setting.
        let response: ChatGPTResult
        do {
            response = try await ask(
                prompt: prompt,
                history: history,
                mode: .wikiPlanning,
                requestedReasoningEffort: "high"
            )
        } catch {
            response = try await ask(
                prompt: prompt,
                history: history,
                mode: .wikiPlanning,
                requestedReasoningEffort: "medium"
            )
        }
        let titles = Self.parseWikipediaArticleTitles(from: response.answer)
        guard !titles.isEmpty else {
            throw ChatGPTCodexError.invalidResponse("The Wiki research planner did not return article titles.")
        }
        return Array(titles.prefix(6))
    }

    func planAssistantAction(prompt: String, history: String = "") async throws -> AssistantActionPlan {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        let localDate = formatter.string(from: now)
        let planningPrompt = """
        CURRENT LOCAL DATE AND TIME: \(localDate)
        LOCAL TIME ZONE: \(TimeZone.current.identifier)

        USER REQUEST:
        \(prompt)
        """
        let response = try await ask(
            prompt: planningPrompt,
            history: history,
            mode: .assistantActionPlanning,
            requestedReasoningEffort: "medium"
        )
        return Self.parseAssistantActionPlan(from: response.answer)
    }

    func ask(
        prompt: String,
        history: String = "",
        image: UIImage? = nil,
        mode: ChatGPTReplyMode,
        sources: [WebSearchResult] = [],
        liveLookupContext: String? = nil,
        requestedReasoningEffort: String? = nil
    ) async throws -> ChatGPTResult {
        let credentials = try await validCredentials()
        let systemPrompt: String
        switch mode {
        case .quick:
            systemPrompt = """
            You are LittleRip, powered by ChatGPT GPT-5.6 Terra. If asked which model powers you, say GPT-5.6 Terra. Never claim to be GLM, Ollama, Qwen, or another model.

            You are a helpful assistant in a back-and-forth text conversation. Reply naturally and directly to the user's latest message, using the session context for follow-ups. Handle mathematics directly in this normal conversation mode. Write math in readable OmniScript-style plain Unicode: use symbols such as ×, ÷, √, π, ≈, ≤, ≥, superscripts, and clear one-line equations. Never emit LaTeX commands, dollar-sign delimiters, or code blocks for ordinary math.

            In the current iPhone build, you can use fresh DuckDuckGo web context, look up live weather from the user's permitted location, and read public Hacker News top stories or search results with article and discussion links. You accept native Apple speech input. A hidden semantic planner can invoke native schedule_notification and compose_message actions before conversational answering. schedule_notification surfaces a message at a future time without requiring fixed trigger words. compose_message resolves an on-device Contact and opens Apple's native composer with the recipient and body filled in; Apple requires the user to review it and tap Send. Never say LittleRip cannot prepare an iPhone notification or native message. Never claim an outgoing message was delivered; the native action reports whether the user tapped Send, cancelled, or encountered a failure. Deep Wiki mode separately searches Wikipedia and provides encyclopedia-style context.

            When Hacker News results are supplied, accurately discuss the returned stories and retain their article and discussion links; you cannot post, vote, or access a Hacker News account. When describing your abilities, call the notification feature a “LittleRip iPhone notification,” not an alarm; it does not alter Apple's Clock app. You cannot currently send messages, place trades, control the user's Mac, run AppleScript, access a wallet, or use cloud MCP tools unless those integrations are explicitly connected later. If a LIVE LOOKUP RESULT is supplied, use it as fresh evidence and say naturally that you looked it up. If a NATIVE ACTION RESULT is supplied, accurately confirm its outcome; never claim an action succeeded unless that result says it did. Keep the tone warm and conversational; invite a useful next question when appropriate. Do not use canned sections, lecture formatting, or unnecessary lists.
            """
        case .wiki:
            systemPrompt = """
            You are LittleRip, powered by ChatGPT GPT-5.6 Terra. If asked which model powers you, say GPT-5.6 Terra. Never claim to be GLM, Ollama, Qwen, or another model.

            Give a concise, well-structured explanation grounded in the supplied Wikipedia article excerpts. These are not raw keyword-search results: a separate semantic research pass chose the articles to explain the user's entire idea. Read the excerpts before answering. Treat the first article as the most directly useful source and later articles as supporting mechanisms, context, or prerequisites. Do not echo the user's question as a search phrase and do not say "here are the search results." The app lists the verified, tappable Wikipedia links separately below your answer.

            Respond with exactly these plain-text headings, each on its own line and in this order:
            DEFINITION
            EXPLANATION
            ANALOGY
            FIRST PRINCIPLES

            DEFINITION gives a concise dictionary-style definition. EXPLANATION directly addresses the user's actual why/how/comparison question using the article excerpts. ANALOGY compares it to a familiar situation. FIRST PRINCIPLES explains the technical fundamentals that make it work underneath. Do not add a Sources heading or markdown. Do not invent claims that contradict or go beyond the supplied Wikipedia excerpts; if an excerpt is incomplete, qualify the detail rather than pretending it was read.
            """
        case .wikiPlanning:
            systemPrompt = """
            You are the research planner for LittleRip's Wikipedia mode. Do not answer the user's question. Silently reason about the user's full intent, including why they asked, relationships between concepts, and any current-session follow-up context.

            Return ONLY a valid JSON array containing 4 to 6 canonical English Wikipedia article titles, in descending usefulness. The list must collectively teach the user's whole idea:
            - First: the most direct canonical article that answers the core question.
            - Then: the underlying mechanism, prerequisite, cause, contrast, or adjacent concept needed for a genuinely informative answer, even when the user did not use that exact word.
            - Choose educational encyclopedia topics, not loose word matches.
            - Do not choose people, celebrities, TV shows, films, episodes, music, products, lists, or disambiguation pages unless the user's question is specifically about one.
            - Use likely real Wikipedia page titles and do not include explanations, prose, Markdown, or code fences.

            Example for “Why can a motor damage a circuit when switched off?”: ["Flyback diode", "Inductor", "Electromagnetic induction", "Back electromotive force", "DC motor"].
            """
        case .assistantActionPlanning:
            systemPrompt = """
            You are LittleRip's hidden native-action planner. Never answer conversationally and never claim an action happened. Decide whether the user directly wants one of these tools:

            1. schedule_notification(message, fireDate)
            Use when the user wants LittleRip to prompt, tell, nudge, alert, or surface a message at a future time. The user does not need fixed words such as “notification” or “remind.”
            Examples: “At 3 tell me to clock in,” “In 20 minutes check the oven,” “Tomorrow morning, bring my keys.”

            2. compose_message(recipient, message)
            Use when the user wants to text or message another person now.
            Examples: “Text Dad that I’m on my way,” “Tell Sarah I’ll be ten minutes late,” “Send 303-555-0123 the address.” Preserve the user's intended message exactly and do not embellish it. Use recent session context to resolve a follow-up after LittleRip asked which recipient or what body to use.

            Apple requires the user to review the native composer and tap Send. The tool prepares the message; it does not silently send it. If the user asks to send a message to another person at a future time, return clarify asking whether to prepare it now or create a notification at that time. If a compose request lacks the recipient or body, return clarify. If a notification request lacks the future time or body, return clarify.

            Questions, historical dates, statements about plans, requests for writing advice, and hypothetical examples are not actions. “What should I text Dad?” is none, while “Text Dad that I’m leaving” is compose_message. If intent is uncertain, return none.

            Return ONLY one compact JSON object with this exact shape:
            {"action":"schedule_notification|compose_message|clarify|none","recipient":"contact name or phone number, or empty string","message":"exact notification body or exact outgoing message body, or empty string","fireDate":"ISO-8601 date with numeric UTC offset or empty string","clarification":"one short question or empty string"}

            Resolve notification dates from the supplied current local date, time, and time zone. Treat “at 3” or “at 3:15” as the next future 3:00:00 or 3:15:00 in local time; always include seconds and use 00 unless explicitly supplied. The action must be none unless the request is direct.
            """
        }

        let historyContext = history.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : """

        CURRENT SESSION CONTEXT:
        \(history)

        """

        let sourceContext = sources.isEmpty ? "" : "\n\nWIKIPEDIA ARTICLE SUMMARIES, RANKED MOST USEFUL FIRST:\n" + sources.enumerated().map { index, source in "\(index + 1). \(source.title) — \(source.url)\n\(source.snippet)" }.joined(separator: "\n\n")
        let lookupContext = liveLookupContext.map { "\n\nLIVE LOOKUP RESULT:\n\($0)" } ?? ""
        var content: [[String: Any]] = [
            ["type": "input_text", "text": "\(historyContext)USER'S CURRENT QUESTION:\n\(prompt)\(sourceContext)\(lookupContext)"]
        ]

        if let image, let jpegData = image.jpegData(compressionQuality: 0.75) {
            content.append([
                "type": "input_image",
                "detail": "auto",
                "image_url": "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
            ])
        }

        let requestID = UUID().uuidString.lowercased()
        var reasoningEffort: String
        switch mode {
        case .wikiPlanning:
            reasoningEffort = "high"
        case .quick, .wiki, .assistantActionPlanning:
            reasoningEffort = "medium"
        }
        if let requestedReasoningEffort {
            reasoningEffort = requestedReasoningEffort
        }
        let body: [String: Any] = [
            "model": "gpt-5.6-terra",
            "store": false,
            "stream": true,
            "instructions": systemPrompt + "\nUse plain text and never wrap text in double asterisks.",
            "input": [["role": "user", "content": content]],
            "text": ["verbosity": "low"],
            "include": ["reasoning.encrypted_content"],
            "prompt_cache_key": requestID,
            "tool_choice": "auto",
            "parallel_tool_calls": true,
            "reasoning": ["effort": reasoningEffort, "summary": "auto"]
        ]

        var request = URLRequest(url: Self.codexURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(credentials.access)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("pi", forHTTPHeaderField: "originator")
        request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(requestID, forHTTPHeaderField: "session-id")
        request.setValue(requestID, forHTTPHeaderField: "x-client-request-id")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatGPTCodexError.invalidResponse("ChatGPT returned an invalid response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            var responseText = ""
            for try await line in bytes.lines {
                responseText += line
            }
            if httpResponse.statusCode == 401 {
                signOut()
            }
            throw ChatGPTCodexError.invalidResponse(
                "ChatGPT error \(httpResponse.statusCode): \(String(responseText.prefix(300)))"
            )
        }

        var answer = ""
        var thinking = ""
        var completed = false

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", let data = payload.data(using: .utf8),
                  let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else {
                continue
            }

            switch type {
            case "response.output_text.delta", "response.refusal.delta":
                if let delta = event["delta"] as? String {
                    answer += delta
                }
            case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
                if let delta = event["delta"] as? String {
                    thinking += delta
                }
            case "response.output_item.done":
                if let item = event["item"] as? [String: Any],
                   item["type"] as? String == "message",
                   let finalText = Self.textFromMessageItem(item),
                   !finalText.isEmpty {
                    answer = finalText
                }
            case "response.completed", "response.done":
                completed = true
            case "response.incomplete":
                throw ChatGPTCodexError.invalidResponse("GPT-5.6 Terra stopped before completing its response.")
            case "response.failed":
                let response = event["response"] as? [String: Any]
                let error = response?["error"] as? [String: Any]
                let message = error?["message"] as? String ?? "GPT-5.6 Terra request failed."
                throw ChatGPTCodexError.invalidResponse(message)
            case "error":
                let message = event["message"] as? String ?? "GPT-5.6 Terra request failed."
                throw ChatGPTCodexError.invalidResponse(message)
            default:
                break
            }
        }

        let cleanedAnswer = answer
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard completed, !cleanedAnswer.isEmpty else {
            throw ChatGPTCodexError.emptyResponse
        }

        return ChatGPTResult(
            answer: cleanedAnswer,
            thinking: thinking.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func parseAssistantActionPlan(from text: String) -> AssistantActionPlan {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let payload = try? JSONDecoder().decode(AssistantActionPayload.self, from: data) else {
            return .none
        }

        switch payload.action.lowercased() {
        case "schedule_notification":
            let message = (payload.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let clarification = (payload.clarification ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else {
                return .clarification(clarification.isEmpty ? "What should the LittleRip notification say?" : clarification)
            }
            guard let date = parseISO8601Date(payload.fireDate ?? "") else {
                return .clarification(clarification.isEmpty ? "When should LittleRip notify you?" : clarification)
            }
            guard date > Date() else {
                return .clarification("That time has already passed. When should LittleRip notify you instead?")
            }
            return .scheduleNotification(message: message, date: date)
        case "compose_message":
            let recipient = (payload.recipient ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let message = (payload.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let clarification = (payload.clarification ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recipient.isEmpty else {
                return .clarification(clarification.isEmpty ? "Who should I message?" : clarification)
            }
            guard !message.isEmpty else {
                return .clarification(clarification.isEmpty ? "What should the message to \(recipient) say?" : clarification)
            }
            return .composeMessage(recipient: recipient, body: message)
        case "clarify":
            let clarification = (payload.clarification ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .clarification(clarification.isEmpty ? "What details should LittleRip use for that action?" : clarification)
        default:
            return .none
        }
    }

    private static func parseISO8601Date(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func parseWikipediaArticleTitles(from text: String) -> [String] {
        let trimmed = text
            .replacingOccurrences(of: "```json", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var rawTitles: [String] = []
        if let start = trimmed.firstIndex(of: "["),
           let end = trimmed.lastIndex(of: "]"),
           start < end,
           let data = String(trimmed[start...end]).data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String].self, from: data) {
            rawTitles = parsed
        } else {
            rawTitles = trimmed.components(separatedBy: .newlines).map {
                $0.replacingOccurrences(of: "^[•\\-\\d.\\s]+", with: "", options: .regularExpression)
            }
        }

        var seen = Set<String>()
        return rawTitles.compactMap { title in
            let cleaned = title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\\\"'"))
            guard cleaned.count >= 2, cleaned.count <= 120 else { return nil }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return cleaned
        }
    }

    private func validCredentials() async throws -> Credentials {
        guard var credentials else {
            throw ChatGPTCodexError.notAuthenticated
        }

        if credentials.expiresAt <= Date().addingTimeInterval(60) {
            credentials = try await Self.refreshCredentials(credentials.refresh)
            try Self.saveCredentials(credentials)
            self.credentials = credentials
        }

        return credentials
    }

    private static func requestDeviceCode() async throws -> DeviceCode {
        var request = URLRequest(url: authBaseURL.appendingPathComponent("api/accounts/deviceauth/usercode"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": clientID])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data, operation: "device login")

        let decoded = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        guard let interval = Double(decoded.interval), interval >= 0 else {
            throw ChatGPTCodexError.invalidResponse("ChatGPT returned an invalid polling interval.")
        }

        return DeviceCode(
            deviceAuthID: decoded.deviceAuthID,
            userCode: decoded.userCode,
            interval: interval,
            expiresAt: Date().addingTimeInterval(15 * 60)
        )
    }

    private static func pollForAuthorization(_ device: DeviceCode) async throws -> AuthorizationCode {
        var interval = max(device.interval, 1)
        let url = authBaseURL.appendingPathComponent("api/accounts/deviceauth/token")

        while Date() < device.expiresAt {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "device_auth_id": device.deviceAuthID,
                "user_code": device.userCode
            ])

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            if (200..<300).contains(statusCode) {
                let decoded = try JSONDecoder().decode(DeviceAuthorizationResponse.self, from: data)
                return AuthorizationCode(code: decoded.authorizationCode, verifier: decoded.codeVerifier)
            }

            if statusCode == 403 || statusCode == 404 {
                continue
            }

            let errorCode = Self.errorCode(from: data)
            if errorCode == "deviceauth_authorization_pending" {
                continue
            }
            if errorCode == "slow_down" {
                interval += 5
                continue
            }

            let message = String(data: data, encoding: .utf8) ?? "Unknown login error"
            throw ChatGPTCodexError.invalidResponse("ChatGPT device login failed: \(message)")
        }

        throw ChatGPTCodexError.loginExpired
    }

    private static func exchangeAuthorizationCode(_ code: String, verifier: String) async throws -> Credentials {
        try await tokenRequest([
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "redirect_uri", value: deviceRedirectURI)
        ], operation: "login")
    }

    private static func refreshCredentials(_ refreshToken: String) async throws -> Credentials {
        try await tokenRequest([
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientID)
        ], operation: "refresh")
    }

    private static func tokenRequest(_ items: [URLQueryItem], operation: String) async throws -> Credentials {
        var components = URLComponents()
        components.queryItems = items

        var request = URLRequest(url: authBaseURL.appendingPathComponent("oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data, operation: operation)

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let accountID = accountID(from: decoded.accessToken) else {
            throw ChatGPTCodexError.missingAccountID
        }

        return Credentials(
            access: decoded.accessToken,
            refresh: decoded.refreshToken,
            expiresAt: Date().addingTimeInterval(decoded.expiresIn),
            accountID: accountID
        )
    }

    private static func validate(response: URLResponse, data: Data, operation: String) throws {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ChatGPTCodexError.invalidResponse("ChatGPT \(operation) failed (\(statusCode)): \(message)")
        }
    }

    private static func errorCode(from data: Data) -> String? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = payload["error"] as? String {
            return error
        }
        return (payload["error"] as? [String: Any])?["code"] as? String
    }

    private static func accountID(from accessToken: String) -> String? {
        let parts = accessToken.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any] else {
            return nil
        }

        return auth["chatgpt_account_id"] as? String
    }

    private static func textFromMessageItem(_ item: [String: Any]) -> String? {
        guard let content = item["content"] as? [[String: Any]] else { return nil }
        return content.compactMap { part in
            if part["type"] as? String == "output_text" {
                return part["text"] as? String
            }
            return part["refusal"] as? String
        }.joined()
    }

    private static func saveCredentials(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        deleteCredentials()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ChatGPTCodexError.invalidResponse("Could not securely save ChatGPT login (\(status)).")
        }
    }

    private static func loadCredentials() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    private static func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func savePendingLogin(_ device: DeviceCode) throws {
        let data = try JSONEncoder().encode(device)
        UserDefaults.standard.set(data, forKey: pendingLoginKey)
    }

    private static func loadPendingLogin() -> DeviceCode? {
        guard let data = UserDefaults.standard.data(forKey: pendingLoginKey) else { return nil }
        return try? JSONDecoder().decode(DeviceCode.self, from: data)
    }

    private static func clearPendingLogin() {
        UserDefaults.standard.removeObject(forKey: pendingLoginKey)
    }
}

private struct AssistantActionPayload: Decodable {
    let action: String
    let recipient: String?
    let message: String?
    let fireDate: String?
    let clarification: String?
}

private struct Credentials: Codable {
    let access: String
    let refresh: String
    let expiresAt: Date
    let accountID: String
}

private struct DeviceCode: Codable {
    let deviceAuthID: String
    let userCode: String
    let interval: TimeInterval
    let expiresAt: Date
}

private struct AuthorizationCode {
    let code: String
    let verifier: String
}

private struct DeviceCodeResponse: Decodable {
    let deviceAuthID: String
    let userCode: String
    let interval: String

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case interval
    }
}

private struct DeviceAuthorizationResponse: Decodable {
    let authorizationCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeVerifier = "code_verifier"
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
