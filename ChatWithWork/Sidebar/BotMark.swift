import SwiftUI

/// The bots' mark, as the web draws it (`BotMark` in the Rails app): our
/// pixel chat bubble with two tall eyes, one 16-square drawing scaled
/// smoothly to any size, so it reads like an icon in a row and like pixel art
/// when large. It takes the foreground style, like an SF Symbol, and blinks
/// now and then: for a tenth of a second every 4 to 9 seconds it draws its
/// closed frame, the same drawing with each eye only its bottom row, never
/// with Reduce Motion on. A face (the web's `bot_mark face:`) holds still.
struct BotMark: View {
    var size: CGFloat = 20
    var face: BotMarkShape.Face?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false

    var body: some View {
        BotMarkShape(eyesOpen: !blinking, face: face)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .task(id: reduceMotion) {
                blinking = false
                guard !reduceMotion, face == nil else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Double.random(in: 4...9)))
                    guard !Task.isCancelled else { return }
                    blinking = true
                    try? await Task.sleep(for: .milliseconds(120))
                    blinking = false
                }
            }
    }
}

/// One frame of the drawing, as one path merged into a single outline, so
/// smooth edges leave no seams between squares: `#` the outline, `E` eye
/// squares of the open frame only, `e` eye squares of both frames. The same
/// drawing as the web's.
nonisolated struct BotMarkShape: Shape {
    /// Other eyes for what it's doing: `happy` smiles with them, for nothing
    /// left to do. As `x, y, width, height` squares of the grid.
    enum Face: Sendable {
        case happy

        var eyes: [(Int, Int, Int, Int)] {
            switch self {
            case .happy: [(3, 7, 1, 1), (4, 6, 2, 1), (6, 7, 1, 1), (9, 7, 1, 1), (10, 6, 2, 1), (12, 7, 1, 1)]
            }
        }
    }

    var eyesOpen = true
    var face: Face?

    static let grid = [
        "................",
        "................",
        ".##############.",
        "#..............#",
        "#..............#",
        "#...EE....EE...#",
        "#...EE....EE...#",
        "#...ee....ee...#",
        "#..............#",
        "#..............#",
        "#..............#",
        ".###...########.",
        "...#..#.........",
        "...#.#..........",
        "...##...........",
        "................",
    ]

    func path(in rect: CGRect) -> Path {
        let cell = min(rect.width, rect.height) / CGFloat(Self.grid.count)
        var path = Path()
        for (y, row) in Self.grid.enumerated() {
            for (x, square) in row.enumerated() where square == "#" || (face == nil && (square == "e" || (eyesOpen && square == "E"))) {
                path.addRect(CGRect(x: rect.minX + CGFloat(x) * cell, y: rect.minY + CGFloat(y) * cell, width: cell, height: cell))
            }
        }
        for (x, y, width, height) in face?.eyes ?? [] {
            path.addRect(CGRect(x: rect.minX + CGFloat(x) * cell, y: rect.minY + CGFloat(y) * cell, width: CGFloat(width) * cell, height: CGFloat(height) * cell))
        }
        return path.normalized()
    }
}
