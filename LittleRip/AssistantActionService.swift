import Foundation
import UIKit
import UserNotifications

enum AssistantActionPlan {
    case scheduleNotification(message: String, date: Date)
    case composeMessage(recipient: String, body: String)
    case clarification(String)
    case none
}

private enum NotificationSetupError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "Notifications are turned off for LittleRip. Open Settings → Notifications → LittleRip, enable Allow Notifications and Time Sensitive Notifications, then ask again."
    }
}

enum LittleRipNotificationDesign {
    static let categoryIdentifier = "LITTLERIP_NOTIFICATION"
    static let snoozeActionIdentifier = "LITTLERIP_SNOOZE_10"
    static let doneActionIdentifier = "LITTLERIP_DONE"
    static let threadIdentifier = "littlerip.notifications"

    static func configureCategories() {
        let snooze = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: "Snooze 10 min",
            options: []
        )
        let done = UNNotificationAction(
            identifier: doneActionIdentifier,
            title: "Done",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [snooze, done],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "A message from LittleRip",
            categorySummaryFormat: "%u LittleRip notifications",
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func brandedContent(message: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "LittleRip"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.threadIdentifier = threadIdentifier
        content.targetContentIdentifier = "littlerip.notification"
        content.summaryArgument = "LittleRip"
        content.relevanceScore = 1.0
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["littleripMessage": message]

        if let attachment = logoAttachment() {
            content.attachments = [attachment]
        }
        return content
    }

    private static func logoAttachment() -> UNNotificationAttachment? {
        guard let image = UIImage(named: "RobotMinerIcon"),
              let data = image.pngData() else {
            return nil
        }

        do {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LittleRipNotifications", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("LittleRip-logo.png")
            if !FileManager.default.fileExists(atPath: url.path) {
                try data.write(to: url, options: .atomic)
            }
            return try UNNotificationAttachment(identifier: "LittleRipLogo", url: url)
        } catch {
            // The system still shows the app icon even if an expanded image
            // attachment cannot be prepared.
            return nil
        }
    }
}

@MainActor
final class AssistantActionService: ObservableObject {
    private let center = UNUserNotificationCenter.current()

    init() {
        LittleRipNotificationDesign.configureCategories()
    }

    /// Recognizes direct notification commands without turning ordinary questions
    /// that merely mention reminders or dates into actions.
    func shouldPlanNotification(for prompt: String) -> Bool {
        let lower = normalized(correctedPrompt(prompt))
        let politePrefix = #"(?:hey\s+littlerip[,.]?\s*)?(?:please\s+)?(?:(?:can|could|would|will)\s+you\s+)?(?:please\s+)?"#
        let nativeAction = #"(?:send\s+me\s+(?:a\s+)?notification|send\s+(?:a\s+)?notification|give\s+me\s+a\s+notification|set\s+(?:me\s+)?a\s+(?:notification|reminder)|schedule\s+a\s+notification|create\s+a\s+reminder|notify\s+me|remind\s+me|alert\s+me|ping\s+me|nudge\s+me|give\s+me\s+a\s+heads\s+up|set\s+(?:an?\s+)?alarm|wake\s+me|notification\s+(?:at|in)|reminder\s+(?:at|in))"#
        let messageAction = #"(?:say|tell\s+me|let\s+me\s+know|message\s+me|remember\s+to|make\s+sure\s+(?:i|to)|don'?t\s+let\s+me\s+forget|do\s+not\s+let\s+me\s+forget)"#
        let informationalQuestion = #"^"# + politePrefix
            + #"(?:remind\s+me|tell\s+me|let\s+me\s+know|message\s+me)\s+(?:what|why|who|where|when|how|whether)\b"#
        if matches(informationalQuestion, in: lower) {
            return false
        }

        if matches(#"^"# + politePrefix + nativeAction + #"\b"#, in: lower) ||
            matches(#"^i\s+(?:want|need|would\s+like)\s+(?:you\s+to\s+)?"# + nativeAction + #"\b"#, in: lower) {
            return true
        }

        let hasFutureLanguage = detectedDate(in: prompt) != nil || relativeDelay(in: prompt) != nil
        guard hasFutureLanguage else { return false }

        if matches(#"^"# + politePrefix + messageAction + #"\b"#, in: lower) {
            return true
        }

        let timeFirst = #"^(?:at|on|in|after|today|tonight|tomorrow|next|this|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
        return matches(timeFirst + #".*\b(?:"# + nativeAction + #"|"# + messageAction + #")\b"#, in: lower)
    }

    /// Executes only a notification action the user directly requested. A
    /// semantic plan handles free-form language; deterministic parsing remains as
    /// an offline fallback if the planning request is unavailable.
    func perform(for prompt: String, semanticPlan: AssistantActionPlan? = nil) async -> String? {
        // A complete local plan schedules immediately and cannot be cancelled by
        // an AI `.none` result. AI planning is only a fallback for wording the
        // deterministic parser could not fully understand.
        let localPlan = localPlan(for: prompt)
        let plan: AssistantActionPlan
        switch localPlan {
        case .scheduleNotification, .composeMessage:
            plan = localPlan
        case .clarification, .none:
            if let semanticPlan {
                switch semanticPlan {
                case .scheduleNotification, .composeMessage, .clarification:
                    plan = semanticPlan
                case .none:
                    plan = localPlan
                }
            } else {
                plan = localPlan
            }
        }

        switch plan {
        case .scheduleNotification(let message, let date):
            return await scheduleNotification(message: message, at: date)
        case .composeMessage:
            // Message composition is presented by MessageComposeService in the UI.
            return nil
        case .clarification(let question):
            return question
        case .none:
            return nil
        }
    }

    private func scheduleNotification(message: String, at date: Date) async -> String {
        let cleanMessage = message
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !cleanMessage.isEmpty else {
            return "What should the LittleRip notification say?"
        }
        guard date.timeIntervalSinceNow > 1 else {
            return "That time has already passed. When should LittleRip notify you instead?"
        }

        do {
            _ = try await usableNotificationSettings()

            LittleRipNotificationDesign.configureCategories()
            let content = LittleRipNotificationDesign.brandedContent(message: cleanMessage)
            let preciseDate = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
            var userInfo = content.userInfo
            userInfo["littleripFireDate"] = preciseDate.timeIntervalSince1970
            content.userInfo = userInfo

            let components = Calendar.current.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                from: preciseDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = "littlerip.notification.\(UUID().uuidString)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try await center.add(request)

            guard let pending = await center.pendingNotificationRequests().first(where: { $0.identifier == identifier }),
                  let pendingTrigger = pending.trigger as? UNCalendarNotificationTrigger,
                  let nextDate = pendingTrigger.nextTriggerDate(),
                  abs(nextDate.timeIntervalSince(preciseDate)) < 1 else {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                return "LittleRip could not verify the exact notification time, so it was not scheduled. Please try again."
            }

            return "LittleRip notification scheduled\n\n“\(cleanMessage)”\n\n\(confirmationDate(nextDate))"
        } catch {
            return "LittleRip could not schedule that notification: \(error.localizedDescription)"
        }
    }

    private func usableNotificationSettings() async throws -> UNNotificationSettings {
        var settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            throw NotificationSetupError.permissionDenied
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])
            guard granted else { throw NotificationSetupError.permissionDenied }
            settings = await center.notificationSettings()
        @unknown default:
            throw NotificationSetupError.permissionDenied
        }
        return settings
    }

    private func settingsWarnings(_ settings: UNNotificationSettings) -> [String] {
        var warnings: [String] = []
        if settings.timeSensitiveSetting != .enabled {
            warnings.append("enable Settings → Notifications → LittleRip → Time Sensitive Notifications")
        }
        if settings.alertSetting != .enabled || settings.notificationCenterSetting != .enabled {
            warnings.append("enable alerts and Notification Center for LittleRip")
        }
        if settings.soundSetting != .enabled {
            warnings.append("enable Sounds for LittleRip")
        }
        return warnings
    }

    func localPlan(for prompt: String) -> AssistantActionPlan {
        guard shouldPlanNotification(for: prompt) else { return .none }
        guard let date = detectedDate(in: prompt) ?? relativeDelay(in: prompt) else {
            return .clarification("When should LittleRip send the notification?")
        }
        var message = extractedMessage(from: prompt)
        let lower = normalized(correctedPrompt(prompt))
        if message.isEmpty, containsWholePhrase("wake me", in: lower) {
            message = "Wake up"
        } else if message.isEmpty,
                  containsWholePhrase("set alarm", in: lower) || containsWholePhrase("set an alarm", in: lower) {
            message = "Alarm"
        }
        guard !message.isEmpty else {
            return .clarification("What should the LittleRip notification say?")
        }
        return .scheduleNotification(message: message, date: date)
    }

    private func detectedDate(in prompt: String) -> Date? {
        let corrected = correctedPrompt(prompt)
        if !containsExplicitCalendarDay(corrected),
           let nextClock = nextClockDate(in: corrected) {
            return nextClock
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(corrected.startIndex..., in: corrected)
        guard let detected = detector?.firstMatch(in: corrected, range: range)?.date else {
            return nil
        }

        // A time without an explicit day means its next occurrence. NSDataDetector
        // otherwise resolves a passed “8 PM” to earlier today.
        if detected <= Date(), !containsExplicitCalendarDay(corrected) {
            return Calendar.current.date(byAdding: .day, value: 1, to: detected)
        }
        return detected
    }

    private func nextClockDate(in text: String) -> Date? {
        let patterns = [
            #"\b(?:at|for)\s+(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?\b"#,
            #"\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b"#
        ]
        let now = Date()

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let hourRange = Range(match.range(at: 1), in: text),
                  let rawHour = Int(text[hourRange]),
                  (0...23).contains(rawHour) else {
                continue
            }

            let minute: Int
            if match.range(at: 2).location != NSNotFound,
               let minuteRange = Range(match.range(at: 2), in: text),
               let parsedMinute = Int(text[minuteRange]),
               (0...59).contains(parsedMinute) {
                minute = parsedMinute
            } else {
                minute = 0
            }

            let meridiem: String?
            if match.range(at: 3).location != NSNotFound,
               let meridiemRange = Range(match.range(at: 3), in: text) {
                meridiem = text[meridiemRange].lowercased().replacingOccurrences(of: ".", with: "")
            } else {
                meridiem = nil
            }

            let candidateHours: [Int]
            if let meridiem {
                guard (1...12).contains(rawHour) else { continue }
                candidateHours = [meridiem == "pm" ? (rawHour % 12) + 12 : rawHour % 12]
            } else if rawHour > 12 {
                candidateHours = [rawHour]
            } else if rawHour == 0 {
                candidateHours = [0]
            } else {
                candidateHours = [rawHour % 12, (rawHour % 12) + 12]
            }

            let candidates = candidateHours.flatMap { hour -> [Date] in
                guard let today = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now),
                      let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
                    return []
                }
                return [today, tomorrow]
            }
            if let next = candidates.filter({ $0 > now }).min() {
                return next
            }
        }
        return nil
    }

    private func containsExplicitCalendarDay(_ text: String) -> Bool {
        matches(
            #"\b(?:today|tonight|tomorrow|yesterday|next|this|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december)\b|\b\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?\b"#,
            in: normalized(text)
        )
    }

    private func relativeDelay(in prompt: String) -> Date? {
        let lower = normalized(correctedPrompt(prompt))
        if lower.range(of: #"\b(?:in|after)\s+half\s+(?:an?\s+)?hour\b"#, options: .regularExpression) != nil {
            return Date().addingTimeInterval(30 * 60)
        }

        let quantity = #"(\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"#
        let patterns: [(String, TimeInterval)] = [
            (#"\b(?:in|after)\s+"# + quantity + #"\s*(?:sec|secs|second|seconds)\b"#, 1),
            (#"\b(?:in|after)\s+"# + quantity + #"\s*(?:min|mins|minute|minutes)\b"#, 60),
            (#"\b(?:in|after)\s+"# + quantity + #"\s*(?:hr|hrs|hour|hours)\b"#, 3_600),
            (#"\b(?:in|after)\s+"# + quantity + #"\s*(?:day|days)\b"#, 86_400)
        ]
        for (pattern, multiplier) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  let valueRange = Range(match.range(at: 1), in: lower),
                  let value = numericQuantity(String(lower[valueRange])) else {
                continue
            }
            return Date().addingTimeInterval(value * multiplier)
        }
        return nil
    }

    private func numericQuantity(_ text: String) -> Double? {
        if let number = Double(text) { return number }
        let words: [String: Double] = [
            "a": 1, "an": 1, "one": 1, "two": 2, "three": 3,
            "four": 4, "five": 5, "six": 6, "seven": 7,
            "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12
        ]
        return words[text]
    }

    private func extractedMessage(from prompt: String) -> String {
        var message = correctedPrompt(prompt)

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(message.startIndex..., in: message)
            if let match = detector.firstMatch(in: message, range: range),
               let swiftRange = Range(match.range, in: message) {
                message.removeSubrange(swiftRange)
            }
        }

        message = message
            .replacingOccurrences(of: #"^\s*hey\s+littlerip[,.]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\s*(?:can|could|would|will)\s+you\s+(?:please\s+)?"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\s*please\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\s*i\s+(?:want|need|would\s+like)\s+(?:you\s+to\s+)?"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(?:at|for)\s+\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(?:in|after)\s+(?:half\s+(?:an?\s+)?hour|\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s*(?:sec|secs|second|seconds|min|mins|minute|minutes|hr|hrs|hour|hours|day|days)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(?:send me a notification|send me notification|send a notification|give me a notification|set a notification|schedule a notification|notification|reminder|notify me|remind me(?: to)?|remember to|set me a reminder(?: to)?|set a reminder(?: to)?|create a reminder(?: to)?|set an? alarm(?: to)?|alert me|ping me|give me a heads up(?: to)?|nudge me(?: to)?|make sure (?:i|to)|don'?t let me forget(?: to)?|do not let me forget(?: to)?|say|tell me|let me know|message me|wake me)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(?:that\s+)?(?:says?|saying)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\s*(?:(?:at|on|for|about|that|to)\b\s*)+"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(?:at|on)\s*$"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        return message
    }

    private func confirmationDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "EEEE, MMMM d 'at' h:mm:ss a"
        return formatter.string(from: date)
    }

    private func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func containsWholePhrase(_ phrase: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(
            for: phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return text.range(
            of: #"\b"# + escaped + #"\b"#,
            options: .regularExpression
        ) != nil
    }

    private func correctedPrompt(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\b(?:snd|sned|sedn)\b"#, with: "send", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(?:notifaction|notificaton|notifcation|notfication|notificatoin|notificaiton)\b"#, with: "notification", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(?:remeind|reomind|remid|remaind|remimd|rember)\b"#, with: "remind", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bminuite\b"#, with: "minute", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(\d{1,2})\s*pom\b"#, with: "$1 pm", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b(\d{1,2})\s*aom\b"#, with: "$1 am", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "wednsday", with: "wednesday", options: .caseInsensitive)
            .replacingOccurrences(of: "tommorow", with: "tomorrow", options: .caseInsensitive)
            .replacingOccurrences(of: "tomorow", with: "tomorrow", options: .caseInsensitive)
    }

    private func normalized(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
