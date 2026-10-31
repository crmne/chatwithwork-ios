import SwiftUI

/// The road: what the answer did so far, the bot where it stands, and dots that
/// fade to nothing ahead of it. The bot's place never follows progress, and the
/// road has no end mark until the answer has one.
struct RoadView: View {
    let road: OpenRoad
    var height: CGFloat = 52
    var ground: Color = Road.canvas
    var bot: CGFloat = 42 + 2.0 / 3.0
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            content(width: proxy.size.width)
        }
        .frame(height: height)
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.6), value: road.ticks.count)
        .accessibilityHidden(true)
    }

    private var base: CGFloat { height - 2 }

    private func botTop(_ size: CGFloat) -> CGFloat { base - size * 15 / 16 }

    private func toolWidth(_ tool: OpenRoad.Tool?) -> CGFloat {
        tool.map { (BotPixels.tool($0).width + 1.6) * bot / 16 } ?? 0
    }

    private var botMode: BotMark.Mode { dimmed || road.stage == .stale ? .line : .solid }
    private var botColor: Color { road.stage == .stale ? Color(red: 0x80 / 255, green: 0x88 / 255, blue: 0x9D / 255) : .white }

    private func placedBot(x: CGFloat) -> some View {
        BotMark(face: road.face, tool: road.tool, size: bot, mode: botMode, color: botColor, eyes: ground)
            .id(road.face.rawValue + (road.tool?.rawValue ?? ""))
            .transition(.opacity)
            .offset(x: x, y: botTop(bot))
    }

    @ViewBuilder
    private func content(width w: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            switch road.stage {
            case .starting: starting(w)
            case .working: working(w)
            case .agents: agents(w)
            case .writing: writing(w)
            case .decision, .input: yourTurn(w)
            case .finished: finished(w)
            case .failed: broken(w)
            case .stopped: halted(w)
            case .stale: quiet(w)
            }
        }
        .frame(width: w, height: height, alignment: .topLeading)
    }

    // MARK: Parts

    private func span(_ x1: CGFloat) -> CGFloat {
        max(min(x1 - 8, CGFloat(road.ticks.count) * 13 + CGFloat(road.stops.count) * 30), 0)
    }

    private func stopCentres(_ x1: CGFloat) -> [CGFloat] {
        let width = span(x1)
        let gap = width / (CGFloat(road.stops.count) + 0.4)
        return road.stops.indices.map { x1 - width + 12 + gap * CGFloat($0) }
    }

    /// Ticks, with those under a stop left out.
    private func ticks(_ x1: CGFloat, only: (Int, OpenRoad.Tick) -> Bool = { _, _ in true }) -> [CGRect] {
        guard !road.ticks.isEmpty else { return [] }
        let width = span(x1)
        let pitch = width / CGFloat(road.ticks.count)
        let tick = min(max(pitch * 0.58, 2), 3.5)
        let stops = stopCentres(x1)
        return road.ticks.enumerated().compactMap { index, item in
            let x = x1 - width + CGFloat(index) * pitch + (pitch - tick) / 2
            guard only(index, item), !stops.contains(where: { x + tick > $0 - 14 && x < $0 + 14 }) else { return nil }
            return CGRect(x: x, y: base - 2 - item.height, width: tick, height: item.height)
        }
    }

    private func line(to x: CGFloat, thickness: CGFloat = 1.5) -> some Shape {
        Bars(rects: [CGRect(x: 0, y: base - thickness / 2, width: max(x, 0), height: thickness)])
    }

    private func rainbow(from x0: CGFloat, to x1: CGFloat, width w: CGFloat, fade: Double = 1) -> AnyShapeStyle {
        if dimmed { return AnyShapeStyle(Road.dim) }
        let colours = Road.rainbow.enumerated().map { index, colour in index == 0 ? colour.opacity(fade) : colour }
        return AnyShapeStyle(LinearGradient(
            colors: colours,
            startPoint: UnitPoint(x: x0 / w, y: 0.5),
            endPoint: UnitPoint(x: max(x1, x0 + 1) / w, y: 0.5)
        ))
    }

    private func origin(_ colour: Color) -> some View {
        Circle()
            .fill(ground)
            .overlay(Circle().stroke(colour, lineWidth: 1.5))
            .frame(width: 5, height: 5)
            .offset(x: 0.5, y: base - 2.5)
    }

    private func stops(_ x1: CGFloat) -> some View {
        ForEach(Array(zip(road.stops, stopCentres(x1))), id: \.0) { key, centre in
            stop(key, size: 23, logo: 15)
                .offset(x: centre - 13.5, y: base - 11 - 13.5)
                .transition(.push(from: .trailing))
        }
    }

    private func stop(_ key: String, size: CGFloat, logo: CGFloat) -> some View {
        ServiceLogo(key: key, size: logo)
            .frame(width: size, height: size)
            .background(Circle().fill(dimmed ? .clear : Road.plinth))
            .padding(2)
            .background(Circle().fill(dimmed ? .clear : ground))
            .opacity(dimmed ? 0.6 : road.stage == .stale ? 0.5 : 1)
    }

    private func dots(from x: CGFloat, to w: CGFloat, y: CGFloat, colour: Color = .white) -> some View {
        let count = Int(max((w - 1 - x) / 9, 0).rounded(.up))
        let total = max(Int((w - x) / 9), 1)
        return ForEach(0..<max(count, 0), id: \.self) { index in
            Circle()
                .fill(colour)
                .opacity(0.7 * pow(max(1 - Double(index) / Double(total), 0), 1.6) + 0.03)
                .frame(width: 3, height: 3)
                .offset(x: x + CGFloat(index) * 9 - 1.5, y: y - 2)
        }
    }

    // MARK: Roads

    private func starting(_ w: CGFloat) -> some View {
        Group {
            line(to: bot + 8, thickness: 2).fill(rainbow(from: 0, to: bot + 8, width: w))
            placedBot(x: 3)
            dots(from: bot + 18, to: w, y: base)
        }
    }

    private func working(_ w: CGFloat) -> some View {
        let head = 0.6 * w
        let x0 = head - span(head)
        let fill = rainbow(from: x0, to: head, width: w, fade: road.isDeep ? 0.12 : 1)
        return Group {
            line(to: head + 8).fill(fill)
            if !road.isDeep { origin(dimmed ? Road.dim : Road.rainbow[0]) }
            Bars(rects: ticks(head) { _, tick in !tick.refused }).fill(fill)
            Bars(rects: ticks(head) { _, tick in tick.refused }).fill(fill).opacity(0.35)
            stops(head)
            placedBot(x: head + 3)
            dots(from: head + bot + toolWidth(road.tool) + 12, to: w, y: base)
        }
    }

    private func agents(_ w: CGFloat) -> some View {
        let fork = 0.42 * w
        let trailEnd = fork - 6
        let fill = rainbow(from: trailEnd - span(trailEnd), to: 0.72 * w, width: w)
        let end = 0.66 * w
        let lanes = [base - 35, base - 17.5, base - 0.5]
        let faces: [OpenRoad.Face] = [.right, .down, .focus]
        let small: CGFloat = 18
        let more = (road.agents ?? 0) - OpenRoad.maxAgentBots
        return Group {
            line(to: fork).fill(fill)
            origin(dimmed ? Road.dim : Road.rainbow[0])
            Bars(rects: ticks(trailEnd)).fill(fill)
            ForEach(lanes.indices, id: \.self) { index in
                Fork(from: CGPoint(x: fork - 2, y: base - 0.5), lane: lanes[index], end: end)
                    .stroke(fill, lineWidth: 1.5)
            }
            stops(trailEnd)
            ForEach(lanes.indices, id: \.self) { index in
                BotMark(face: faces[index], size: small, mode: botMode, eyes: ground)
                    .offset(x: end + 2, y: lanes[index] - small * 15 / 16 + 0.5)
                dots(from: end + small + 12, to: w, y: lanes[index] + 0.5)
            }
            if more > 0 {
                Text(verbatim: "+\(more)")
                    .font(Road.more)
                    .foregroundStyle(Road.dim)
                    .frame(width: w, alignment: .trailing)
                    .offset(y: lanes[1] - 9)
            }
        }
    }

    private func writing(_ w: CGFloat) -> some View {
        let trailEnd = 0.3 * w
        let fill = rainbow(from: trailEnd - span(trailEnd), to: trailEnd, width: w)
        let pen = 0.7 * w
        // Decoration, never a word count.
        let rows: [(y: CGFloat, widths: [CGFloat], opacity: Double)] = [
            (base - 24, [26, 14, 30, 18, 24, 38, 16], 0.45),
            (base - 12, [20, 34, 12, 26, 22, 40], 0.7),
            (base, [34, 16, 24, 30, 40, 18], 0.95)
        ]
        return Group {
            line(to: trailEnd).fill(fill)
            origin(dimmed ? Road.dim : Road.rainbow[0])
            Bars(rects: ticks(trailEnd)).fill(fill)
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                Bars(rects: wordBars(y: row.y, widths: row.widths, from: trailEnd + 12, to: pen + 2), corner: 2)
                    .fill(Road.ink)
                    .opacity(row.opacity)
            }
            stops(trailEnd)
            placedBot(x: pen + 4)
        }
    }

    private func wordBars(y: CGFloat, widths: [CGFloat], from: CGFloat, to: CGFloat) -> [CGRect] {
        var x = from
        var bars: [CGRect] = []
        for width in widths where x + width <= to {
            bars.append(CGRect(x: x, y: y - 2.5, width: width, height: 4))
            x += width + 5
        }
        return bars
    }

    /// A decision or a question: the bot turns to you and holds up a card with
    /// what it's about, and the road ahead waits.
    private func yourTurn(_ w: CGFloat) -> some View {
        let head = 0.34 * w
        let right = head + 4 + bot
        let card = right + 4
        return Group {
            line(to: head + 8).fill(Road.line)
            origin(Road.grey)
            Bars(rects: ticks(head)).fill(Road.grey)
            stops(head)
            aheadDashes(from: card + 46, to: w)
            placedBot(x: head + 4)
            ZStack(alignment: .topLeading) {
                Bars(rects: [CGRect(x: right - 2, y: base - 16, width: 10, height: 3)], corner: 0).fill(botColor)
                HeldCard(road: road).rotationEffect(.degrees(-5)).offset(x: card, y: base - 40)
            }
            .frame(width: w, height: height, alignment: .topLeading)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.6, anchor: UnitPoint(x: right / w, y: 1)).combined(with: .opacity))
        }
    }

    private func aheadDashes(from x: CGFloat, to w: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: x, y: base))
            path.addLine(to: CGPoint(x: w, y: base))
        }
        .stroke(Road.dimmedAhead, style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
    }

    private func finished(_ w: CGFloat) -> some View {
        let destination = w - 36
        let head = destination - bot - 8
        return Group {
            line(to: destination + 2).fill(dimmed ? Road.dim : Road.positive).opacity(0.6)
            origin(dimmed ? Road.dim : Road.positive)
            Bars(rects: ticks(head - 4)).fill(dimmed ? Road.dim : Road.positive)
            stops(head - 4)
            placedBot(x: head)
            Image("Mark")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .offset(x: destination, y: base - 35)
                .transition(.opacity)
        }
    }

    private func broken(_ w: CGFloat) -> some View {
        let head = 0.46 * w
        let last = road.ticks.count - 3
        let crack = head + 3
        return Group {
            line(to: head).fill(Road.line)
            origin(Road.grey)
            Bars(rects: ticks(head) { index, _ in index < last }).fill(Road.grey)
            Bars(rects: ticks(head) { index, _ in index >= last }).fill(Road.negative)
            stops(head)
            Crack(start: CGPoint(x: crack, y: base + 1)).stroke(Road.negative, lineWidth: 2.2)
            placedBot(x: crack + 18)
        }
    }

    private func halted(_ w: CGFloat) -> some View {
        let head = 0.46 * w
        let cap = head + bot + 14
        return Group {
            line(to: head + 8).fill(Road.line)
            origin(Road.grey)
            Bars(rects: ticks(head)).fill(Road.grey)
            stops(head)
            placedBot(x: head + 4)
            Bars(rects: [CGRect(x: cap, y: base - 30, width: 4, height: 31)]).fill(Road.ink)
        }
    }

    private func quiet(_ w: CGFloat) -> some View {
        let head = 0.6 * w
        return Group {
            Bars(rects: ticks(head)).fill(Road.quiet)
            Path { path in
                path.move(to: CGPoint(x: 0, y: base))
                path.addLine(to: CGPoint(x: head + 8, y: base))
            }
            .stroke(Road.line, style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
            stops(head)
            placedBot(x: head + 3)
        }
    }
}

/// A run of round-capped bars, all one fill so a gradient spans the road.
private nonisolated struct Bars: Shape {
    let rects: [CGRect]
    var corner: CGFloat?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for bar in rects {
            let radius = corner ?? min(bar.width, bar.height) / 2
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: radius, height: radius))
        }
        return path
    }
}

private nonisolated struct Fork: Shape {
    let from: CGPoint
    let lane: CGFloat
    let end: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addCurve(
            to: CGPoint(x: from.x + 30, y: lane),
            control1: CGPoint(x: from.x + 20, y: from.y),
            control2: CGPoint(x: from.x + 10, y: lane)
        )
        path.addLine(to: CGPoint(x: end, y: lane))
        return path
    }
}

private nonisolated struct Crack: Shape {
    let start: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x + 6, y: start.y - 8))
        path.addLine(to: CGPoint(x: start.x + 1, y: start.y - 13))
        path.addLine(to: CGPoint(x: start.x + 9, y: start.y - 24))
        return path
    }
}

/// The small amber card the bot holds up: the service's logo, or generic glyph,
/// on a white plate. A question or a change with no service draws its own mark.
private struct HeldCard: View {
    let road: OpenRoad
    @Environment(\.isLuminanceReduced) private var dimmed

    private var mark: OpenRoad.Tool { road.stage == .input ? .ask : .write }

    var body: some View {
        content
            .frame(width: 34, height: 27)
            .background {
                if dimmed {
                    RoundedRectangle(cornerRadius: 4).stroke(Road.attention, lineWidth: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Road.attention)
                        .shadow(color: Road.attention.opacity(0.35), radius: 7)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let service = road.service {
            ServiceLogo(key: service, size: 14, color: dimmed ? Road.dim : Road.canvas)
                .frame(width: 18, height: 18)
                .background { if !dimmed { RoundedRectangle(cornerRadius: 3).fill(.white) } }
                .opacity(dimmed ? 0.6 : 1)
        } else {
            let drawing = BotPixels.tool(mark)
            PixelShape(rects: drawing.rects, square: 2)
                .fill(dimmed ? Road.attention : Road.canvas)
                .frame(width: drawing.width * 2, height: drawing.height * 2)
        }
    }
}
