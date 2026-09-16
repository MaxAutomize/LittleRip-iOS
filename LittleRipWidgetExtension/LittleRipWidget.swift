import AppIntents
import SwiftUI
import WidgetKit

struct LittleRipVoiceEntry: TimelineEntry {
    let date: Date
}

struct LittleRipVoiceProvider: TimelineProvider {
    func placeholder(in context: Context) -> LittleRipVoiceEntry { LittleRipVoiceEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (LittleRipVoiceEntry) -> Void) {
        completion(LittleRipVoiceEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LittleRipVoiceEntry>) -> Void) {
        completion(Timeline(entries: [LittleRipVoiceEntry(date: .now)], policy: .never))
    }
}

struct LittleRipVoiceWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Button(intent: StartVoiceAssistantIntent()) {
            if family == .systemSmall {
                VStack(spacing: 8) {
                    Image("LittleRipWidgetRobot")
                        .resizable()
                        .scaledToFit()
                    Text("Talk to LittleRip")
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
    }
}

/// A tappable Lock Screen widget. It opens LittleRip; voice starts only from the in-app microphone button.
struct LittleRipVoiceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LittleRipVoiceWidget", provider: LittleRipVoiceProvider()) { _ in
            LittleRipVoiceWidgetView()
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Talk to LittleRip")
        .description("Tap the LittleRip robot to open the app.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

struct LittleRipVoiceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LittleRipVoiceControl") {
            ControlWidgetButton(action: StartVoiceAssistantIntent()) {
                Label("Talk to LittleRip", systemImage: "waveform")
            }
        }
        .displayName("Talk to LittleRip")
        .description("Open LittleRip from Control Center or the Lock Screen.")
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
        LittleRipVoiceWidget()
        LittleRipVoiceControl()
        LittleRipControl()
    }
}
