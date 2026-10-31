import SwiftUI

/// The card's tokens: fixed, with no light variant. The card is always dark,
/// on purpose, whatever the device's appearance.
enum Road {
    static let canvas = Color("RoadCanvas")
    static let ink = Color("RoadInk")
    static let inkMuted = Color("RoadInkMuted")
    static let grey = Color("RoadGrey")
    static let line = Color("RoadLine")
    static let quiet = Color(red: 0x2A / 255, green: 0x30 / 255, blue: 0x40 / 255)
    static let plinth = Color("RoadPlinth")
    static let attention = Color("RoadAttention")
    static let positive = Color("RoadPositive")
    static let negative = Color("RoadNegative")
    static let negativeWash = Color(red: 0xFF / 255, green: 0x66 / 255, blue: 0x44 / 255)
    static let dim = Color(red: 0xAE / 255, green: 0xB6 / 255, blue: 0xC8 / 255)
    static let rainbow: [Color] = [
        Color(red: 0x44 / 255, green: 0xFF / 255, blue: 0x9A / 255),
        Color(red: 0x44 / 255, green: 0xB0 / 255, blue: 0xFF / 255),
        Color(red: 0x8B / 255, green: 0x44 / 255, blue: 0xFF / 255),
        Color(red: 0xFF / 255, green: 0x66 / 255, blue: 0x44 / 255),
        Color(red: 0xEB / 255, green: 0xFF / 255, blue: 0x70 / 255)
    ]

    static let headline = Font.custom("Geist-SemiBold", size: 21, relativeTo: .title3)
    static let clock = Font.custom("Unbounded-Medium", size: 20, relativeTo: .title3)
    static let organization = Font.custom("Geist-Medium", size: 12.5, relativeTo: .caption)
    static let stepsCount = Font.custom("GeistMono-Medium", size: 11.5, relativeTo: .caption2)
    static let bandTitle = Font.custom("Geist-SemiBold", size: 17, relativeTo: .headline)
    static let bandSub = Font.custom("Geist-Medium", size: 12.5, relativeTo: .caption)
    static let bandWaiting = Font.custom("GeistMono-Medium", size: 10.5, relativeTo: .caption2)
    static let bandClock = Font.custom("Unbounded-SemiBold", size: 17, relativeTo: .headline)
    static let bandAction = Font.custom("Geist-SemiBold", size: 13.5, relativeTo: .subheadline)
    static let compactClock = Font.custom("Unbounded-Medium", fixedSize: 12.5)
    static let compactWord = Font.custom("Geist-SemiBold", fixedSize: 12.5)
    static let more = Font.custom("GeistMono-Medium", fixedSize: 11)

    static func tint(for stage: OpenRoad.Stage) -> Color {
        switch stage {
        case .decision, .input: attention
        case .finished: positive
        case .failed: negative
        case .stopped, .stale: inkMuted
        default: .white
        }
    }
}

/// A service's own logo, a generic glyph for people's servers and computers,
/// or a neutral dot for a key this build doesn't know.
struct ServiceLogo: View {
    let key: String
    let size: CGFloat
    var color: Color = Road.ink

    var body: some View {
        Group {
            if OpenRoad.hasLogo(key) {
                if OpenRoad.monochromeServices.contains(key) {
                    Image("Logo-\(key)").resizable().renderingMode(.template).scaledToFit().foregroundStyle(color)
                } else {
                    Image("Logo-\(key)").resizable().scaledToFit()
                }
            } else {
                Circle().fill(Road.inkMuted).padding(size / 3.2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The elapsed time, by the system's own timer so it counts between pushes
/// (`Text(timerInterval:)`). A hidden template gives the timer its width, which
/// it would otherwise grow to fill.
struct ActivityClock: View {
    let clock: OpenRoad.Clock
    let font: Font
    var color: Color = Road.ink
    var tracking: CGFloat = -0.6
    var alignment: Alignment = .trailing

    var body: some View {
        switch clock {
        case .hidden:
            EmptyView()
        case .fixed(let seconds):
            Text(OpenRoad.clockText(seconds)).font(font).tracking(tracking).foregroundStyle(color).lineLimit(1)
        case .running(let since):
            Text(since.timeIntervalSinceNow <= -3600 ? "0:00:00" : since.timeIntervalSinceNow <= -600 ? "00:00" : "0:00")
                .font(font)
                .tracking(tracking)
                .hidden()
                .overlay(alignment: alignment) {
                    Text(timerInterval: since...since.addingTimeInterval(24 * 60 * 60), countsDown: false)
                        .font(font)
                        .tracking(tracking)
                        .foregroundStyle(color)
                        .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                        .lineLimit(1)
                }
                .fixedSize()
        }
    }
}
