import AppIntents
import Foundation

struct StartVoiceAssistantIntent: AppIntent {
    static var title: LocalizedStringResource = "Open LittleRip"
    static var description = IntentDescription("Opens LittleRip. Use the microphone button when you want to speak.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        // Lock Screen widgets may open the app, but never begin microphone recording automatically.
        UserDefaults(suiteName: "group.com.maxautomize.LittleRip")?.removeObject(forKey: "littlerip.startVoice")
        return .result()
    }
}
