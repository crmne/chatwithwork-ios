import SwiftUI

/// The assistant's face on these surfaces: BotMark's 16 by 16 grid, the same
/// drawing the web app draws, so it stays square at any size. Faces change only
/// when content does, never on a timer.
nonisolated enum BotPixels {
    static let body = rects("M1 2h14v1h-14zM0 3h16v1h-16zM0 4h16v1h-16zM0 5h16v1h-16zM0 6h16v1h-16zM0 7h16v1h-16zM0 8h16v1h-16zM0 9h16v1h-16zM0 10h16v1h-16zM1 11h14v1h-14zM3 12h4v1h-4zM3 13h3v1h-3zM3 14h2v1h-2z")
    static let outline = rects("M1 2h14v1h-14zM0 3h1v1h-1zM15 3h1v1h-1zM0 4h1v1h-1zM15 4h1v1h-1zM0 5h1v1h-1zM15 5h1v1h-1zM0 6h1v1h-1zM15 6h1v1h-1zM0 7h1v1h-1zM15 7h1v1h-1zM0 8h1v1h-1zM15 8h1v1h-1zM0 9h1v1h-1zM15 9h1v1h-1zM0 10h1v1h-1zM15 10h1v1h-1zM1 11h3v1h-3zM7 11h8v1h-8zM3 12h1v1h-1zM6 12h1v1h-1zM3 13h1v1h-1zM5 13h1v1h-1zM3 14h2v1h-2z")

    static func face(_ face: OpenRoad.Face) -> [CGRect] {
        switch face {
        case .open: rects("M4 5h2v3h-2zM10 5h2v3h-2z")
        case .closed: rects("M4 7h2v1h-2zM10 7h2v1h-2z")
        case .right: rects("M6 5h2v3h-2zM12 5h2v3h-2z")
        case .left: rects("M2 5h2v3h-2zM8 5h2v3h-2z")
        case .down: rects("M5 7h2v2h-2zM11 7h2v2h-2z")
        case .up: rects("M5 4h2v2h-2zM11 4h2v2h-2z")
        case .focus: rects("M3 5h3v1h-3zM4 6h2v2h-2zM10 5h3v1h-3zM10 6h2v2h-2z")
        case .wide: rects("M3 4h1v1h-1zM4 4h1v1h-1zM5 4h1v1h-1zM3 5h1v1h-1zM5 5h1v1h-1zM3 6h1v1h-1zM4 6h1v1h-1zM5 6h1v1h-1zM3 7h1v1h-1zM4 7h1v1h-1zM5 7h1v1h-1zM10 4h1v1h-1zM11 4h1v1h-1zM12 4h1v1h-1zM10 5h1v1h-1zM12 5h1v1h-1zM10 6h1v1h-1zM11 6h1v1h-1zM12 6h1v1h-1zM10 7h1v1h-1zM11 7h1v1h-1zM12 7h1v1h-1z")
        case .brow: rects("M4 5h2v3h-2zM10 6h2v2h-2zM9 4h3v1h-3z")
        case .happy: rects("M3 7h1v1h-1zM4 6h1v1h-1zM5 6h1v1h-1zM6 7h1v1h-1zM9 7h1v1h-1zM10 6h1v1h-1zM11 6h1v1h-1zM12 7h1v1h-1z")
        case .flat: rects("M3 7h3v1h-3zM10 7h3v1h-3z")
        }
    }

    /// In its own box, with that box's size.
    static func tool(_ tool: OpenRoad.Tool) -> (rects: [CGRect], width: CGFloat, height: CGFloat) {
        switch tool {
        case .search: (rects("M1 0h1v1h-1zM2 0h1v1h-1zM3 0h1v1h-1zM0 1h1v1h-1zM4 1h1v1h-1zM0 2h1v1h-1zM4 2h1v1h-1zM0 3h1v1h-1zM4 3h1v1h-1zM1 4h1v1h-1zM2 4h1v1h-1zM3 4h1v1h-1zM4 5h1v1h-1zM5 6h1v1h-1z"), 7, 7)
        case .read: (rects("M0 0h1v1h-1zM1 0h1v1h-1zM2 0h1v1h-1zM3 0h1v1h-1zM4 0h1v1h-1zM5 0h1v1h-1zM0 1h1v1h-1zM5 1h1v1h-1zM0 2h1v1h-1zM2 2h1v1h-1zM3 2h1v1h-1zM5 2h1v1h-1zM0 3h1v1h-1zM5 3h1v1h-1zM0 4h1v1h-1zM2 4h1v1h-1zM3 4h1v1h-1zM5 4h1v1h-1zM0 5h1v1h-1zM5 5h1v1h-1zM0 6h1v1h-1zM1 6h1v1h-1zM2 6h1v1h-1zM3 6h1v1h-1zM4 6h1v1h-1zM5 6h1v1h-1z"), 6, 7)
        case .list: (rects("M0 0h1v1h-1zM1 0h1v1h-1zM2 0h1v1h-1zM0 1h1v1h-1zM1 1h1v1h-1zM2 1h1v1h-1zM3 1h1v1h-1zM4 1h1v1h-1zM5 1h1v1h-1zM6 1h1v1h-1zM0 2h1v1h-1zM6 2h1v1h-1zM0 3h1v1h-1zM6 3h1v1h-1zM0 4h1v1h-1zM6 4h1v1h-1zM0 5h1v1h-1zM1 5h1v1h-1zM2 5h1v1h-1zM3 5h1v1h-1zM4 5h1v1h-1zM5 5h1v1h-1zM6 5h1v1h-1z"), 7, 6)
        case .use: (rects("M2 0h1v1h-1zM4 0h1v1h-1zM2 1h1v1h-1zM4 1h1v1h-1zM1 2h1v1h-1zM2 2h1v1h-1zM3 2h1v1h-1zM4 2h1v1h-1zM5 2h1v1h-1zM1 3h1v1h-1zM2 3h1v1h-1zM3 3h1v1h-1zM4 3h1v1h-1zM5 3h1v1h-1zM2 4h1v1h-1zM3 4h1v1h-1zM4 4h1v1h-1zM3 5h1v1h-1zM3 6h1v1h-1z"), 7, 7)
        case .plan: (rects("M0 0h1v1h-1zM2 0h1v1h-1zM3 0h1v1h-1zM4 0h1v1h-1zM5 0h1v1h-1zM0 2h1v1h-1zM2 2h1v1h-1zM3 2h1v1h-1zM4 2h1v1h-1zM5 2h1v1h-1zM0 4h1v1h-1zM2 4h1v1h-1zM3 4h1v1h-1zM4 4h1v1h-1z"), 6, 5)
        case .run: (rects("M3 0h1v1h-1zM1 1h1v1h-1zM3 1h1v1h-1zM5 1h1v1h-1zM2 2h1v1h-1zM3 2h1v1h-1zM4 2h1v1h-1zM0 3h1v1h-1zM1 3h1v1h-1zM2 3h1v1h-1zM4 3h1v1h-1zM5 3h1v1h-1zM6 3h1v1h-1zM2 4h1v1h-1zM3 4h1v1h-1zM4 4h1v1h-1zM1 5h1v1h-1zM3 5h1v1h-1zM5 5h1v1h-1zM3 6h1v1h-1z"), 7, 7)
        case .write: (rects("M5 0h1v1h-1zM6 0h1v1h-1zM4 1h1v1h-1zM6 1h1v1h-1zM3 2h1v1h-1zM5 2h1v1h-1zM2 3h1v1h-1zM4 3h1v1h-1zM1 4h1v1h-1zM3 4h1v1h-1zM0 5h1v1h-1zM1 5h1v1h-1zM0 6h1v1h-1z"), 7, 7)
        case .ask: (rects("M1 0h1v1h-1zM2 0h1v1h-1zM3 0h1v1h-1zM0 1h1v1h-1zM4 1h1v1h-1zM3 2h1v1h-1zM2 3h1v1h-1zM2 5h1v1h-1z"), 5, 6)
        }
    }

    /// `M<x> <y>h<w>v<h>h-<w>z`, repeated: every shape here is a run of pixels.
    private static func rects(_ path: String) -> [CGRect] {
        path.split(separator: "z").map { shape in
            let numbers = shape.split { "Mhv ".contains($0) }.compactMap { Double($0) }
            return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }
    }
}

nonisolated struct PixelShape: Shape {
    let rects: [CGRect]
    /// Device-independent size of one square of the grid.
    let square: CGFloat
    var origin: CGPoint = .zero

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for pixel in rects {
            path.addRect(CGRect(
                x: origin.x + pixel.minX * square,
                y: origin.y + pixel.minY * square,
                width: pixel.width * square,
                height: pixel.height * square
            ))
        }
        return path
    }
}

/// Who's at work, on the card's dark ground or the Island's black: the bot,
/// whose `line` is the outline, for Always-On and for a card gone quiet, or in
/// a person's chat (`logo`) Chat with Work's logo in its place, in its own
/// white and black, with no faces, since the words say the state.
struct BotMark: View {
    enum Mode { case solid, line }

    var face: OpenRoad.Face
    var tool: OpenRoad.Tool? = nil
    var size: CGFloat
    var mode: Mode = .solid
    var color: Color = .white
    var eyes: Color = Road.canvas
    var logo = false
    @Environment(\.displayScale) private var scale

    /// Whole device pixels a square, so edges stay sharp: 8 at 42 2/3pt on @3x.
    static func square(for size: CGFloat, scale: CGFloat) -> CGFloat {
        max((size * scale / 16).rounded(), 1) / scale
    }

    private var square: CGFloat { Self.square(for: size, scale: scale) }

    var body: some View {
        let side = square * 16
        ZStack(alignment: .topLeading) {
            switch logo ? nil : mode {
            case nil:
                Image("Mark").resizable().scaledToFit().frame(width: side, height: side)
            case .solid?:
                PixelShape(rects: BotPixels.body, square: square).fill(color)
                PixelShape(rects: BotPixels.face(face), square: square).fill(eyes)
            case .line?:
                PixelShape(rects: BotPixels.outline + BotPixels.face(face), square: square).fill(color)
            }
            if let tool {
                let drawing = BotPixels.tool(tool)
                PixelShape(
                    rects: drawing.rects,
                    square: square,
                    origin: CGPoint(x: 16.6 * square, y: (drawing.height > 6 ? 2 : 3) * square)
                )
                .fill(color)
            }
        }
        .frame(width: side + (tool.map { (BotPixels.tool($0).width + 1.6) * square } ?? 0), height: side, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
