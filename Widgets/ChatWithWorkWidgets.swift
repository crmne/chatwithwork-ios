import ActivityKit
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

// MARK: - Live Activity

/// An answer that works on after the person left it: the organization, the
/// step it's on ("Searching Todoist") with a timer and how many steps it
/// took, then how it ended. Nothing from the chat: the server sends steps
/// in words that name only the kind of step and a built-in service.
struct ChatLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChatActivityAttributes.self) { context in
            LockScreenActivity(context: context)
                .activityBackgroundTint(Color("Canvas"))
                .widgetURL(AppLink.open(path: context.attributes.path))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("Mark").resizable().scaledToFit().frame(width: 28, height: 28)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isWorking {
                        Text(context.attributes.startedAt, style: .timer)
                            .font(.callout.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chat with Work · \(context.attributes.organization)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        StepLine(state: context.state, font: .subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isWorking, let steps = context.state.stepsLine {
                        Text(steps)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 36)
                    }
                }
            } compactLeading: {
                Image("Mark").resizable().scaledToFit().frame(width: 18, height: 18)
            } compactTrailing: {
                if context.state.isWorking {
                    Text(context.attributes.startedAt, style: .timer)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 40)
                } else {
                    Image(systemName: context.state.symbol)
                }
            } minimal: {
                if context.state.isWorking {
                    Image("Mark").resizable().scaledToFit().frame(width: 16, height: 16)
                } else {
                    Image(systemName: context.state.symbol)
                }
            }
            .widgetURL(AppLink.open(path: context.attributes.path))
        }
    }
}

/// The step it's on, or how it ended, after its symbol, which changes in
/// place as the steps do.
private struct StepLine: View {
    let state: ChatActivityAttributes.ContentState
    let font: Font

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.symbol)
                .font(font)
                .foregroundStyle(state.phase == "failed" ? Color("NegativeInk") : Color("Ink"))
                .contentTransition(.symbolEffect(.replace))
            Text(state.line)
                .font(font)
                .foregroundStyle(Color("Ink"))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.opacity)
        }
    }
}

private struct LockScreenActivity: View {
    let context: ActivityViewContext<ChatActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("Mark").resizable().scaledToFit().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("Chat with Work · \(context.attributes.organization)")
                    .font(.caption)
                    .foregroundStyle(Color("InkMuted"))
                    .lineLimit(1)
                StepLine(state: context.state, font: .headline)
                    .opacity(context.isStale ? 0.6 : 1)
            }
            Spacer(minLength: 8)
            if context.state.isWorking {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Color("InkMuted"))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64, alignment: .trailing)
                    if let steps = context.state.stepsLine {
                        Text(steps)
                            .font(.caption)
                            .foregroundStyle(Color("InkMuted"))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(16)
    }
}
