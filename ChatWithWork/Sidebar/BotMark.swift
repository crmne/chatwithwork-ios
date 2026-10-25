import SwiftUI

/// The bots' mark, as the web draws it (`BotMark` in the Rails app): our
/// pixel chat bubble with two tall eyes, from the master placed pixel by
/// pixel for its size (16 or 20pt here), so every master pixel is two or
/// three whole device pixels and nothing is resampled. It takes the
/// foreground style, like an SF Symbol, and blinks now and then: for a tenth
/// of a second every 4 to 9 seconds it draws its closed frame, the same grid
/// with each eye only its bottom row, never with Reduce Motion on.
struct BotMark: View {
    /// 16 or 20, a size with a master.
    var size: Int = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false

    var body: some View {
        BotMarkShape(master: size, eyesOpen: !blinking)
            .frame(width: CGFloat(size), height: CGFloat(size))
            .accessibilityHidden(true)
            .task(id: reduceMotion) {
                blinking = false
                guard !reduceMotion else { return }
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

/// One frame of a master, drawn whole: `#` the outline, `E` eye pixels of the
/// open frame only, `e` eye pixels of both frames. The same masters as the
/// web's.
nonisolated struct BotMarkShape: Shape {
    var master = 20
    var eyesOpen = true

    static let masters: [Int: [String]] = [
        16: [
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
        ],
        20: [
            "....................",
            "....................",
            ".##################.",
            "#..................#",
            "#..................#",
            "#..................#",
            "#.....EE....EE.....#",
            "#.....EE....EE.....#",
            "#.....EE....EE.....#",
            "#.....ee....ee.....#",
            "#..................#",
            "#..................#",
            "#..................#",
            ".####....##########.",
            "....#...#...........",
            "....#..#............",
            "....#.#.............",
            "....##..............",
            "....................",
            "....................",
        ],
    ]

    func path(in rect: CGRect) -> Path {
        let grid = Self.masters[master] ?? Self.masters[20]!
        let cell = min(rect.width, rect.height) / CGFloat(grid.count)
        var path = Path()
        for (y, row) in grid.enumerated() {
            for (x, square) in row.enumerated() where square == "#" || square == "e" || (eyesOpen && square == "E") {
                path.addRect(CGRect(x: rect.minX + CGFloat(x) * cell, y: rect.minY + CGFloat(y) * cell, width: cell, height: cell))
            }
        }
        return path
    }
}
