import AppIntents
import SwiftUI
import WidgetKit

struct LittleRipControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LittleRipUnlockControl") {
            ControlWidgetButton(action: UnlockFrontDoorIntent()) {
                Label("Unlock", systemImage: "lock.open.fill")
            }
        }
        .displayName("Unlock Door")
        .description("Unlock your SmartRent front door.")
    }
}

@main
struct LittleRipWidgetBundle: WidgetBundle {
    var body: some Widget {
        LittleRipControl()
    }
}
