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
                    ActivityBody(attributes: context.attributes, state: context.state, isStale: context.isStale, island: true)
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
    var metric = false

    private var timerFont: Font {
        (compact ? Font.caption : metric ? Font.title2 : Font.subheadline).weight(.semibold).monospacedDigit()
    }

    var body: some View {
        // Timer text otherwise expands into all available space. Reserve a
        // monospaced time shape, not a wide invisible gap before the step count.
        Text(startedAt.timeIntervalSinceNow <= -3600 ? "0:00:00" : "00:00")
            .hidden()
            .font(timerFont)
            .overlay(alignment: .leading) {
                Text(startedAt, style: .timer)
                    .font(timerFont)
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
            if position == .trailing && limited {
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                ActivityMark()
                Text(attributes.organization)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color("InkMuted"))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .dynamicTypeSize(...DynamicTypeSize.large)
            ActivityBody(attributes: attributes, state: state, isStale: isStale)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

private struct ActivityBody: View {
    let attributes: ChatActivityAttributes
    let state: ChatActivityAttributes.ContentState
    let isStale: Bool
    var island = false
    @Environment(\.dynamicTypeSize) private var textSize

    private var working: Bool { state.showsElapsed(isStale: isStale) }
    private var color: Color { state.tint(isStale: isStale) }
    private var emphatic: Bool { !isStale && (working || state.needsAttention || state.phase == "answered") }

    var body: some View {
        ViewThatFits(in: .vertical) {
            composition(condensed: false)
            composition(condensed: true)
        }
        .frame(maxHeight: island ? 116 : 124)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func composition(condensed: Bool) -> some View {
        VStack(alignment: .leading, spacing: condensed ? 8 : 10) {
            if working {
                workBoard(condensed: condensed)
                    .padding(.horizontal, island ? 0 : 16)
            } else {
                result
                    .padding(.horizontal, island ? 0 : 16)
            }
            actionBand
        }
    }

    @ViewBuilder
    private func workBoard(condensed: Bool) -> some View {
        if textSize.isAccessibilitySize {
            HStack(spacing: 9) {
                Image(systemName: state.symbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                if let steps = state.stepsLine {
                    Text(steps)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color("Ink"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                ActivityElapsed(startedAt: attributes.startedAt, compact: true)
                    .foregroundStyle(color)
            }
            .frame(minHeight: 32)
        } else {
            regularWorkBoard(condensed: condensed)
        }
    }

    private func regularWorkBoard(condensed: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            if let steps = state.steps, steps >= 0 {
                VStack(alignment: .leading, spacing: 0) {
                    Text(steps, format: .number)
                        .font((condensed ? Font.title : Font.largeTitle).weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color("Ink"))
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(steps == 1 ? String(localized: "step so far") : String(localized: "steps so far"))
                        .font(.caption2)
                        .foregroundStyle(Color("InkMuted"))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            ActivityTrail(kinds: state.recentActivityKinds, color: color, compact: textSize.isAccessibilitySize, condensed: condensed)
                .frame(maxWidth: .infinity)
            VStack(alignment: .trailing, spacing: 3) {
                ActivityElapsed(startedAt: attributes.startedAt, metric: true)
                    .foregroundStyle(color)
                Text("elapsed")
                    .font(.caption2)
                    .foregroundStyle(Color("InkMuted"))
            }
        }
        .frame(minHeight: condensed ? 44 : 52)
    }

    private var result: some View {
        HStack(spacing: 13) {
            Image(systemName: state.displaySymbol(isStale: isStale))
                .font(.system(size: state.needsAttention ? 36 : 40, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 52, height: 56)
                .background {
                    if !isStale && state.phase == "answered" {
                        RoundedRectangle(cornerRadius: 16).fill(color.opacity(0.12))
                    }
                }
                .accessibilityHidden(true)
            Text(state.displayHeadline(isStale: isStale))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color("Ink"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionBand: some View {
        Link(destination: AppLink.open(path: attributes.path)) {
            HStack(spacing: 9) {
                if working {
                    Text(state.displayHeadline(isStale: false))
                        .font(textSize.isAccessibilitySize ? .subheadline.weight(.semibold) : .headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                } else {
                    Text(isStale ? String(localized: "Open chat") : state.action)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(emphatic ? Color("Canvas") : color)
            .padding(.horizontal, 15)
            .padding(.vertical, textSize.isAccessibilitySize ? 6 : 10)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(emphatic ? color : color.opacity(0.10))
            .clipShape(.rect(cornerRadius: island ? 13 : 0))
        }
        .accessibilityHint(working ? String(localized: "Open chat") : "")
    }
}

/// A trail of actual observed kinds, never planned stages or successful results.
private struct ActivityTrail: View {
    let kinds: [String]
    let color: Color
    var compact = false
    var condensed = false

    var body: some View {
        if kinds.count < 2 || compact {
            Image(systemName: ChatActivityAttributes.ContentState.activitySymbol(for: kinds.last ?? "answer"))
                .font(.system(size: 35, weight: .light))
                .foregroundStyle(color)
                .frame(height: 48)
                .accessibilityLabel(ChatActivityAttributes.ContentState.activityLabel(for: kinds.last ?? "answer"))
        } else {
            VStack(spacing: 4) {
                Text("Recent activity")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color("InkMuted"))
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(kinds.enumerated()), id: \.offset) { index, kind in
                        let current = index == kinds.count - 1
                        VStack(spacing: 2) {
                            Image(systemName: ChatActivityAttributes.ContentState.activitySymbol(for: kind))
                                .font(.system(size: current ? 19 : 16, weight: current ? .semibold : .regular))
                                .frame(width: 28, height: 28)
                                .background(current ? color.opacity(0.14) : .clear, in: Circle())
                            if !condensed {
                                Text(ChatActivityAttributes.ContentState.activityLabel(for: kind))
                                    .font(.caption2.weight(current ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(current ? color : Color("InkMuted"))
                        .accessibilityLabel(ChatActivityAttributes.ContentState.activityLabel(for: kind) + (current ? String(localized: ", current") : ""))
                        if !current {
                            Rectangle()
                                .fill(Color("InkMuted").opacity(0.35))
                                .frame(minWidth: 5, maxWidth: 18)
                                .frame(height: 1)
                                .padding(.top, 14)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .dynamicTypeSize(...DynamicTypeSize.large)
        }
    }
}
