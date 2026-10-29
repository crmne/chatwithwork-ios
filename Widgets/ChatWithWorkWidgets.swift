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

/// A compact dashboard for one running answer. State is always content-free:
/// the current kind of work, elapsed time, steps so far and a way back to chat.
struct ChatLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChatActivityAttributes.self) { context in
            ActivityCard(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .padding(16)
                .activityBackgroundTint(Color("Canvas"))
                .widgetURL(AppLink.open(path: context.attributes.path))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityIdentity(organization: context.attributes.organization)
                        .environment(\.colorScheme, .dark)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityElapsed(startedAt: context.attributes.startedAt, state: context.state, isStale: context.isStale)
                        .padding(.trailing, 8)
                        .environment(\.colorScheme, .dark)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityBody(attributes: context.attributes, state: context.state, isStale: context.isStale)
                        .padding(.top, 8)
                        .environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                Image("Mark").resizable().scaledToFit().frame(width: 18, height: 18)
            } compactTrailing: {
                if context.state.showsElapsed(isStale: context.isStale) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 52)
                        .foregroundStyle(context.state.tint)
                        .environment(\.colorScheme, .dark)
                } else {
                    Image(systemName: context.isStale ? "arrow.clockwise" : context.state.symbol)
                        .foregroundStyle(context.state.tint)
                        .environment(\.colorScheme, .dark)
                }
            } minimal: {
                Image(systemName: context.isStale ? "arrow.clockwise" : context.state.symbol)
                    .foregroundStyle(context.state.tint)
                    .environment(\.colorScheme, .dark)
            }
            .widgetURL(AppLink.open(path: context.attributes.path))
        }
    }
}

private extension ChatActivityAttributes.ContentState {
    var tint: Color {
        if needsAttention { return Color("AttentionInk") }
        switch phase {
        case "answered": return Color("PositiveInk")
        case "failed": return Color("NegativeInk")
        case "stopped": return Color("InkMuted")
        default: return Color("LiveInk")
        }
    }
}

private struct ActivityIdentity: View {
    let organization: String

    var body: some View {
        HStack(spacing: 7) {
            Image("Mark").resizable().scaledToFit().frame(width: 20, height: 20)
                .accessibilityLabel("Chat with Work")
            Text(organization)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color("InkMuted"))
                .lineLimit(1)
        }
    }
}

private struct ActivityElapsed: View {
    let startedAt: Date
    let state: ChatActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if state.showsElapsed(isStale: isStale) {
            Text(startedAt, style: .timer)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color("InkMuted"))
                .multilineTextAlignment(.trailing)
                .frame(width: 60, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityLabel("Elapsed time")
                .accessibilityValue(Text(startedAt, style: .timer))
        }
    }
}

private struct ActivityCard: View {
    let attributes: ChatActivityAttributes
    let state: ChatActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ActivityIdentity(organization: attributes.organization)
                Spacer(minLength: 8)
                ActivityElapsed(startedAt: attributes.startedAt, state: state, isStale: isStale)
            }
            ActivityBody(attributes: attributes, state: state, isStale: isStale)
        }
    }
}

private struct ActivityBody: View {
    let attributes: ChatActivityAttributes
    let state: ChatActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isStale ? "arrow.clockwise" : state.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(state.tint)
                    .frame(width: 38, height: 38)
                    .background(state.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(isStale ? String(localized: "Open chat for an update") : state.headline)
                    .font(.headline)
                    .foregroundStyle(Color("Ink"))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .center, spacing: 12) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color("InkMuted"))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Link(destination: AppLink.open(path: attributes.path)) {
                    HStack(spacing: 5) {
                        Text(isStale ? String(localized: "Open chat") : state.action)
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.tint)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(state.tint.opacity(0.12), in: Capsule())
                }
                .fixedSize()
            }
        }
    }

    private var detail: String {
        if isStale { return String(localized: "Last update may be out of date") }
        if state.isWorking { return state.stepsLine ?? String(localized: "Working in the background") }
        return state.line
    }
}
