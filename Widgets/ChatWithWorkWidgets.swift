import SwiftUI
import WidgetKit

/// The app's widgets: Ask on the home screen, and the Live Activity for an
/// answer that works on after the person left it.
@main
struct ChatWithWorkWidgets: WidgetBundle {
    var body: some Widget {
        AskWidget()
        ChatLiveActivity()
    }
}

// MARK: - Ask

/// "Ask anything" and the microphone: a new chat, or one that starts
/// listening. Static, and never shows anything from the person's chats.
struct AskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ask", provider: AskTimeline()) { _ in
            AskView()
                .containerBackground(for: .widget) { Color("Canvas") }
        }
        .configurationDisplayName("Ask Chat with Work")
        .description("Start a new chat, or dictate one.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct AskEntry: TimelineEntry {
    let date: Date
}

struct AskTimeline: TimelineProvider {
    func placeholder(in context: Context) -> AskEntry { AskEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (AskEntry) -> Void) { completion(AskEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AskEntry>) -> Void) {
        completion(Timeline(entries: [AskEntry(date: .now)], policy: .never))
    }
}

struct AskView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "square.and.pencil").font(.title3)
            }
            .widgetURL(AppLink.newChat())
            .accessibilityLabel("New chat")
        case .systemSmall:
            VStack(alignment: .leading, spacing: 10) {
                Image("Mark").resizable().scaledToFit().frame(width: 30, height: 30)
                Spacer(minLength: 0)
                Text("Ask anything")
                    .font(.headline)
                    .foregroundStyle(Color("Ink"))
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                    Text("Dictate")
                }
                .font(.footnote)
                .foregroundStyle(Color("InkMuted"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(AppLink.newChat())
        default:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image("Mark").resizable().scaledToFit().frame(width: 26, height: 26)
                    Text("Chat with Work").font(.subheadline.weight(.semibold)).foregroundStyle(Color("Ink"))
                }
                HStack(spacing: 8) {
                    Link(destination: AppLink.newChat()) {
                        HStack {
                            Text("Ask anything").foregroundStyle(Color("InkMuted"))
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Capsule().fill(Color("Surface")))
                    }
                    Link(destination: AppLink.newChat(dictate: true)) {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(Color("Canvas"))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color("Ink")))
                    }
                    .accessibilityLabel("Dictate")
                }
            }
        }
    }
}
