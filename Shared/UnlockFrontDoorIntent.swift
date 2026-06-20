import AppIntents
import WidgetKit

struct UnlockFrontDoorIntent: AppIntent {
    static var title: LocalizedStringResource = "Unlock Front Door"
    static var description = IntentDescription("Unlocks your SmartRent front door lock.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        SmartRentClient.setWidgetStatus("Running…")
        WidgetCenter.shared.reloadAllTimelines()

        do {
            let creds = try SmartRentClient.loadCredentials()
            let client = SmartRentClient(email: creds.email, password: creds.password)
            try await client.unlockFrontDoor()
            SmartRentClient.setWidgetStatus("Unlock sent")
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Unlock sent")
        } catch {
            SmartRentClient.setWidgetStatus("Error: \(error.localizedDescription)")
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }
    }
}
