import AppIntents
import SwiftUI
import WidgetKit

struct LittleRipGameEntry: TimelineEntry {
    let date: Date
}

struct LittleRipGameProvider: TimelineProvider {
    func placeholder(in context: Context) -> LittleRipGameEntry { LittleRipGameEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (LittleRipGameEntry) -> Void) {
        completion(LittleRipGameEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LittleRipGameEntry>) -> Void) {
        completion(Timeline(entries: [LittleRipGameEntry(date: .now)], policy: .never))
    }
}

struct LittleRipGameWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Button(intent: StartVoiceAssistantIntent()) {
            if family == .systemSmall {
                VStack(spacing: 7) {
                    Image("LittleRipWidgetRobot")
                        .resizable()
                        .scaledToFit()
                    Text("New Game")
                        .font(.headline)
                        .foregroundStyle(.black)
                }
                .padding(10)
            } else {
                Image("LittleRipWidgetRobot")
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            }
        }
        .accessibilityLabel("New trivia game")
    }
}

/// Existing widget identifiers are retained so installed configurations update
/// in place; this is a no-microphone New Game launcher.
struct LittleRipGameWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LittleRipVoiceWidget", provider: LittleRipGameProvider()) { _ in
            LittleRipGameWidgetView()
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("New Game")
        .description("Open LittleRip and start a trivia run.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

struct LittleRipGameControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LittleRipVoiceControl") {
            ControlWidgetButton(action: StartVoiceAssistantIntent()) {
                Label("New Game", systemImage: "sparkles")
            }
        }
        .displayName("New Game")
        .description("Open LittleRip and start a Luna trivia run.")
    }
}

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
        LittleRipGameWidget()
        LittleRipGameControl()
        LittleRipControl()
    }
}
