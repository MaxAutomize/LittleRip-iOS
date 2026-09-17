import AppIntents
import Foundation

/// Kept under the existing type name so installed widget configurations remain
/// valid; it now starts a Luna trivia run and never touches the microphone.
struct StartVoiceAssistantIntent: AppIntent {
    static var title: LocalizedStringResource = "New Game"
    static var description = IntentDescription("Open LittleRip and start a trivia game.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.com.maxautomize.LittleRip")?.set(true, forKey: "littlerip.startNewGame")
        return .result()
    }
}
