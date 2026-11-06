import ActivityKit
import SwiftUI
import WidgetKit

/// Open Road: a dark card with a small bot on a road it lays down as it works.
/// While it works the only colours are the rainbow and the services' logos.
/// Amber means you're needed, green that it finished, orange that it failed.
/// Content-free, and nothing here is a percentage or an estimate (`OpenRoad`).
struct ChatLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChatActivityAttributes.self) { context in
            ActivitySurface(road: context.openRoad, attributes: context.attributes)
                .widgetURL(AppLink.open(path: context.attributes.path))
        } dynamicIsland: { context in
            let road = context.openRoad
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading, priority: 1) {
                    OrganizationLine(organization: context.attributes.organization)
                        .padding(.leading, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StepsLine(road: road)
                        .fixedSize()
                        .padding(.trailing, 6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandBody(road: road, path: context.attributes.path)
                }
            } compactLeading: {
                CompactLeading(road: road)
            } compactTrailing: {
                CompactTrailing(road: road)
            } minimal: {
                MinimalBot(road: road)
            }
            .keylineTint(Road.tint(for: road.stage))
            .widgetURL(AppLink.open(path: context.attributes.path))
        }
        .supplementalActivityFamilies([.small])
    }
}

private extension ActivityViewContext<ChatActivityAttributes> {
    var openRoad: OpenRoad {
        OpenRoad(state: state, startedAt: attributes.startedAt, isStale: isStale)
    }
}

// MARK: - Lock Screen

/// The Lock Screen's card, the Watch's and CarPlay's small one, and the one
/// label VoiceOver reads for them.
private struct ActivitySurface: View {
    let road: OpenRoad
    let attributes: ChatActivityAttributes
    @Environment(\.activityFamily) private var family
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        Group {
            if family == .small {
                SmallCard(road: road)
            } else {
                ActivityCard(road: road, attributes: attributes)
            }
        }
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .activityBackgroundTint(dimmed ? .clear : Road.canvas)
        .activitySystemActionForegroundColor(Road.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(road.accessibilityLabel(organization: attributes.organization))
    }
}

private struct OrganizationLine: View {
    let organization: String

    var body: some View {
        HStack(spacing: 7) {
            Image("Mark").resizable().scaledToFit().frame(width: 15, height: 15)
            Text(organization)
                .font(Road.organization)
                .foregroundStyle(Road.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

private struct StepsLine: View {
    let road: OpenRoad

    var body: some View {
        if let steps = road.stepsLabel {
            Text(steps)
                .font(Road.stepsCount)
                .foregroundStyle(Road.inkMuted)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
    }
}

private struct ActivityCard: View {
    let road: OpenRoad
    let attributes: ChatActivityAttributes
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        if textSize.isAccessibilitySize {
            LargeTextCard(road: road, path: attributes.path)
        } else {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        OrganizationLine(organization: attributes.organization)
                        Spacer(minLength: 0)
                        StepsLine(road: road)
                    }
                    .frame(height: 16)
                    if road.hasBand {
                        RoadView(road: road, height: 48).padding(.top, 12).padding(.bottom, 10)
                    } else {
                        Headline(road: road).padding(.top, 10).padding(.bottom, 6)
                        RoadView(road: road, height: 52).padding(.bottom, 12)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)
                if road.hasBand {
                    Band(road: road, path: attributes.path)
                        .transition(.move(edge: .bottom))
                }
            }
        }
    }
}

/// The words and the clock, last baselines lined up.
private struct Headline: View {
    let road: OpenRoad

    private var colour: Color {
        switch road.stage {
        case .finished: Road.positive
        case .stale: Road.inkMuted
        case .stopped: Road.ink
        default: Road.ink
        }
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                ForEach(0..<3, id: \.self) { words(variant: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if road.stage == .stale {
                if road.heardAt != nil {
                    Text("Open to check")
                        .font(Road.organization)
                        .foregroundStyle(Road.inkMuted)
                        .lineLimit(1)
                }
            } else {
                ActivityClock(clock: road.clock, font: Road.clock, color: road.stage == .finished ? Road.positive : Road.ink)
            }
        }
    }

    /// Verb, logo and the service's word, then verb and logo, then the words alone.
    @ViewBuilder
    private func words(variant: Int) -> some View {
        let logo = showsLogo ? road.service : nil
        HStack(spacing: 6) {
            if let split = road.splitHeadline, showsLogo {
                line(split.verb)
                if variant < 2, let logo { ServiceLogo(key: logo, size: 20) }
                if variant == 0 { line(split.name) }
                if variant == 2 { line(split.name) }
            } else {
                line(road.headline)
                if variant < 2, let logo, road.hasOwnLogo { ServiceLogo(key: logo, size: 20) }
            }
        }
    }

    private var showsLogo: Bool { road.stage == .working }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(Road.headline)
            .tracking(-0.42)
            .foregroundStyle(colour)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .contentTransition(.numericText())
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension OpenRoad {
    var hasOwnLogo: Bool { service.map(OpenRoad.hasLogo) ?? false }
}

/// Amber when you're needed, orange when it failed. Its link only opens the
/// chat: decisions are made there, never here.
private struct Band: View {
    let road: OpenRoad
    let path: String
    var pill = false
    @Environment(\.isLuminanceReduced) private var dimmed

    private var isDecision: Bool { road.stage == .decision }
    private var ink: Color {
        if isDecision, !dimmed { return Road.canvas }
        return road.stage == .failed ? Road.negative : Road.attention
    }

    var body: some View {
        Link(destination: AppLink.open(path: path)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(road.headline)
                        .font(Road.bandTitle)
                        .tracking(-0.25)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if isDecision, let service = road.service, let name = road.serviceName {
                        HStack(spacing: 4) {
                            Text("in")
                            ServiceLogo(key: service, size: 14, color: ink)
                            Text(name).lineLimit(1)
                        }
                        .font(Road.bandSub)
                        .opacity(0.72)
                    }
                }
                Spacer(minLength: 0)
                if road.isWaiting {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Waiting").font(Road.bandWaiting).opacity(0.68)
                        ActivityClock(clock: road.clock, font: Road.bandClock, color: ink, tracking: -0.5)
                    }
                }
                action
            }
            .foregroundStyle(ink)
            .padding(.leading, pill ? 18 : 14)
            .padding(.trailing, pill ? 12 : 14)
            .padding(.vertical, pill ? 6 : 10)
            .frame(maxWidth: .infinity, minHeight: pill ? 50 : 58)
            .background { background }
            .clipShape(.rect(cornerRadius: pill ? 28 : 0))
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
    }

    @ViewBuilder
    private var background: some View {
        let colour = road.stage == .failed ? Road.negativeWash : Road.attention
        let wash = road.stage == .failed ? 0.14 : 0.13
        if isDecision, !dimmed {
            Road.attention
        } else {
            ZStack(alignment: .top) {
                if !dimmed { colour.opacity(wash) }
                colour.opacity(dimmed ? 0.55 : 0.35).frame(height: 1)
            }
        }
    }

    private var action: some View {
        HStack(spacing: 4) {
            Text(road.bandAction).font(Road.bandAction)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .heavy))
        }
        .foregroundStyle(actionInk)
        .padding(.leading, road.stage == .failed ? 13 : 13)
        .padding(.trailing, road.stage == .failed ? 2 : 11)
        .padding(.vertical, 10)
        .background {
            if dimmed, road.stage != .failed {
                Capsule().stroke(Road.attention, lineWidth: 1.5)
            } else if road.stage == .decision {
                Capsule().fill(Road.canvas)
            } else if road.stage == .input {
                Capsule().fill(Road.attention)
            }
        }
    }

    private var actionInk: Color {
        if dimmed { return road.stage == .failed ? Road.negative : Road.attention }
        switch road.stage {
        case .decision: return Road.attention
        case .input: return Road.canvas
        default: return Road.negative
        }
    }
}

/// At accessibility sizes the road goes; bot, clock and words stay, and a
/// band keeps its colour.
private struct LargeTextCard: View {
    let road: OpenRoad
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    BotMark(face: road.face, tool: road.tool, size: 42 + 2.0 / 3.0, mode: road.stage == .stale ? .line : .solid, logo: road.showsLogo)
                    Spacer(minLength: 0)
                    ActivityClock(clock: road.clock, font: Road.clock, color: road.isWaiting ? Road.attention : Road.ink)
                }
                if !road.hasBand {
                    Text(road.headline)
                        .font(Road.headline)
                        .foregroundStyle(road.stage == .finished ? Road.positive : Road.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if road.hasBand {
                Text(largeBandWords)
                    .font(Road.headline)
                    .foregroundStyle(road.stage == .decision ? Road.canvas : road.stage == .failed ? Road.negative : Road.attention)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(road.stage == .decision ? Road.attention : (road.stage == .failed ? Road.negativeWash.opacity(0.14) : Road.attention.opacity(0.13)))
            }
        }
    }

    private var largeBandWords: String {
        if road.stage == .decision, let name = road.serviceName {
            return String(localized: "Approve a change in \(name)")
        }
        return road.headline
    }
}

/// The Watch's Smart Stack and CarPlay: a decision reaches the wrist, and is
/// made on the phone.
private struct SmallCard: View {
    let road: OpenRoad

    var body: some View {
        HStack(spacing: 10) {
            BotMark(face: road.face, size: 32, mode: road.stage == .stale ? .line : .solid, logo: road.showsLogo)
            VStack(alignment: .leading, spacing: 2) {
                Text(road.headline)
                    .font(Road.bandAction)
                    .foregroundStyle(road.isWaiting ? Road.attention : Road.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if road.isWaiting {
                    Text("Open on your phone").font(Road.organization).foregroundStyle(Road.ink)
                } else {
                    ActivityClock(clock: road.clock, font: Road.organization, color: Road.inkMuted, tracking: 0, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }
}

// MARK: - Dynamic Island

private struct IslandBody: View {
    let road: OpenRoad
    let path: String

    var body: some View {
        VStack(spacing: 4) {
            if !road.hasBand { Headline(road: road).padding(.horizontal, 6) }
            // Clear of the Island's curve, which would cut the origin off.
            RoadView(road: road, height: road.hasBand ? 44 : 52, ground: .black)
                .padding(.horizontal, 6)
                .padding(.bottom, road.hasBand ? 0 : 6)
            if road.hasBand {
                Band(road: road, path: path, pill: true)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom))
            }
        }
        .environment(\.colorScheme, .dark)
        // The expanded Island has a fixed height, and the band needs all of it.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

private struct CompactLeading: View {
    let road: OpenRoad

    var body: some View {
        HStack(spacing: 4) {
            BotMark(face: road.stage == .agents ? .focus : road.face, size: 24, mode: road.stage == .stale ? .line : .solid, color: road.stage == .stale ? Road.inkMuted : .white, eyes: .black, logo: road.showsLogo)
            if road.stage == .agents, let count = road.compactAgents {
                Text(verbatim: count)
                    .font(Road.compactClock)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else if !road.isOver, !road.isWaiting, road.stage != .stale, let service = road.service, OpenRoad.hasLogo(service) {
                ServiceLogo(key: service, size: 15)
            }
        }
        .padding(.leading, 2)
        .accessibilityHidden(true)
    }
}

private struct CompactTrailing: View {
    let road: OpenRoad

    var body: some View {
        Group {
            #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                LimitedAwareTrailing(road: road)
            } else {
                CompactClock(road: road)
            }
            #else
            CompactClock(road: road)
            #endif
        }
    }
}

/// Landscape and other narrow system contexts leave only a 28pt circle, so the
/// bot says it alone. Needs the iOS 27 SDK, which CI's Xcode doesn't have yet.
#if compiler(>=6.4)
@available(iOS 27.0, *)
private struct LimitedAwareTrailing: View {
    let road: OpenRoad
    @Environment(\.isDynamicIslandLimitedInWidth) private var limited

    var body: some View {
        if !limited { CompactClock(road: road) }
    }
}
#endif

private struct CompactClock: View {
    let road: OpenRoad

    var body: some View {
        Group {
            switch road.stage {
            case .decision:
                clock(Road.canvas)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Road.attention))
            case .input:
                clock(Road.attention)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Road.attention.opacity(0.18)))
            case .failed:
                word(String(localized: "Failed"), Road.negative)
            case .stopped:
                word(String(localized: "Stopped"), Road.inkMuted)
            case .stale:
                word(road.heardAt.map(OpenRoad.time) ?? "", Road.inkMuted)
            default:
                clock(Road.tint(for: road.stage))
            }
        }
        .padding(.trailing, 2)
        .minimumScaleFactor(0.7)
    }

    private func clock(_ colour: Color) -> some View {
        ActivityClock(clock: road.clock, font: Road.compactClock, color: colour, tracking: -0.38)
    }

    private func word(_ text: String, _ colour: Color) -> some View {
        Text(text).font(Road.compactWord).foregroundStyle(colour).lineLimit(1)
    }
}

private struct MinimalBot: View {
    let road: OpenRoad

    var body: some View {
        Group {
            if road.stage == .decision || road.stage == .input {
                BotMark(face: road.face, size: 20, eyes: .black, logo: road.showsLogo)
                    .padding(1)
                    .background(Circle().stroke(Road.attention, lineWidth: 2).padding(-2))
            } else {
                BotMark(face: road.face, size: 22, mode: road.stage == .stale ? .line : .solid, color: road.stage == .stale ? Road.inkMuted : .white, eyes: .black, logo: road.showsLogo)
            }
        }
        .accessibilityLabel(road.headline)
    }
}
