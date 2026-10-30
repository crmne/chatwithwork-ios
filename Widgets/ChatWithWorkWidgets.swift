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

/// Content-free, current work first. The system controls the Island's black
/// background and the activity's lifetime; no progress or ETA is inferred.
struct ChatLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChatActivityAttributes.self) { context in
            ActivityCard(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .activityBackgroundTint(Color("Canvas"))
                .widgetURL(AppLink.open(path: context.attributes.path))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityMark(size: 14)
                        .environment(\.colorScheme, .dark)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.organization)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color("InkMuted"))
                        .lineLimit(1)
                        .frame(maxWidth: 130, alignment: .trailing)
                        .padding(.trailing, 8)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .environment(\.colorScheme, .dark)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityBody(attributes: context.attributes, state: context.state, isStale: context.isStale)
                        .padding(.top, 6)
                        .environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                ActivityCompact(attributes: context.attributes, state: context.state, isStale: context.isStale, position: .leading)
            } compactTrailing: {
                ActivityCompact(attributes: context.attributes, state: context.state, isStale: context.isStale, position: .trailing)
            } minimal: {
                ActivityCompact(attributes: context.attributes, state: context.state, isStale: context.isStale, position: .minimal)
            }
            .keylineTint(context.state.tint(isStale: context.isStale))
            .widgetURL(AppLink.open(path: context.attributes.path))
        }
    }
}

private extension ChatActivityAttributes.ContentState {
    func tint(isStale: Bool) -> Color {
        if isStale { return Color("InkMuted") }
        if needsAttention { return Color("AttentionInk") }
        switch phase {
        case "answering": return Color("LiveInk")
        case "answered": return Color("PositiveInk")
        case "failed": return Color("NegativeInk")
        default: return Color("InkMuted")
        }
    }
}

private struct ActivityMark: View {
    var size: CGFloat = 14

    var body: some View {
        Image("Mark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Chat with Work")
    }
}

private struct ActivityElapsed: View {
    let startedAt: Date
    var compact = false

    var body: some View {
        // Timer text otherwise expands into all available space. Reserve a
        // monospaced time shape, not a wide invisible gap before the step count.
        Text(startedAt.timeIntervalSinceNow <= -3600 ? "0:00:00" : "00:00")
            .hidden()
            .font(compact ? .caption.weight(.semibold).monospacedDigit() : .subheadline.weight(.semibold).monospacedDigit())
            .overlay(alignment: .leading) {
                Text(startedAt, style: .timer)
                    .font(compact ? .caption.weight(.semibold).monospacedDigit() : .subheadline.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Elapsed time")
            .accessibilityValue(Text(startedAt, style: .timer))
    }
}

private enum ActivityCompactPosition { case leading, trailing, minimal }

private struct ActivityCompact: View {
    let attributes: ChatActivityAttributes
    let state: ChatActivityAttributes.ContentState
    let isStale: Bool
    let position: ActivityCompactPosition

    var body: some View {
        Group {
            if #available(iOS 27.0, *) {
                LimitedActivityCompact(attributes: attributes, state: state, isStale: isStale, position: position)
            } else {
                ActivityCompactContent(attributes: attributes, state: state, isStale: isStale, position: position, limited: false)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Landscape and other narrow system contexts allow only a 28pt circle.
/// One meaningful state icon replaces the split brand/timer presentation.
@available(iOS 27.0, *)
private struct LimitedActivityCompact: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var limited
    let attributes: ChatActivityAttributes
    let state: ChatActivityAttributes.ContentState
    let isStale: Bool
    let position: ActivityCompactPosition

    var body: some View {
        ActivityCompactContent(attributes: attributes, state: state, isStale: isStale, position: position, limited: limited)
    }
}

private struct ActivityCompactContent: View {
    let attributes: ChatActivityAttributes
    let state: ChatActivityAttributes.ContentState
    let isStale: Bool
    let position: ActivityCompactPosition
    let limited: Bool

    var body: some View {
        Group {
            if position == .leading && !limited {
                ActivityMark(size: 16)
            } else if position == .trailing && limited {
                EmptyView()
            } else if position == .trailing && state.showsElapsed(isStale: isStale) {
                ActivityElapsed(startedAt: attributes.startedAt, compact: true)
                    .foregroundStyle(state.tint(isStale: isStale))
            } else {
                Image(systemName: state.displaySymbol(isStale: isStale))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(state.tint(isStale: isStale))
                    .frame(width: limited ? 28 : 20, height: limited ? 28 : 20)
                    .accessibilityLabel(state.displayHeadline(isStale: isStale))
            }
        }
    }
}

private struct ActivityCard: View {
    let attributes: ChatActivityAttributes
    let state: ChatActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ActivityMark()
                Text(attributes.organization)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color("InkMuted"))
                    .lineLimit(1)
            }
            ActivityBody(attributes: attributes, state: state, isStale: isStale)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

private struct ActivityBody: View {
    let attributes: ChatActivityAttributes
    let state: ChatActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: state.displaySymbol(isStale: isStale))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(state.tint(isStale: isStale))
                    .frame(width: 22)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(state.displayHeadline(isStale: isStale))
                    .font(.headline)
                    .foregroundStyle(Color("Ink"))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    if state.showsElapsed(isStale: isStale) { metrics }
                    Spacer(minLength: 6)
                    action
                }
                HStack(spacing: 8) {
                    if state.showsElapsed(isStale: isStale) { metrics }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color("InkMuted"))
                        .accessibilityHidden(true)
                }
            }
        }
        // Live Activities are bounded system surfaces (maximum 160pt).
        // Keep the current action readable at accessibility sizes without
        // letting optional identity/actions push it out of the presentation.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var metrics: some View {
        HStack(spacing: 6) {
            ActivityElapsed(startedAt: attributes.startedAt)
                .foregroundStyle(Color("Ink"))
            if let steps = state.stepsLine {
                Text("·").accessibilityHidden(true)
                Text(steps).lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(Color("InkMuted"))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var action: some View {
        Link(destination: AppLink.open(path: attributes.path)) {
            HStack(spacing: 4) {
                Text(isStale ? String(localized: "Open chat") : state.action)
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.tint(isStale: isStale))
            .padding(.vertical, 2)
        }
        .fixedSize()
    }
}
