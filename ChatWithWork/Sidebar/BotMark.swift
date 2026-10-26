import SwiftUI

/// The bots' mark, as the web draws it (`BotMark` in the Rails app): our
/// pixel chat bubble with two tall eyes, one 16-square drawing scaled
/// smoothly to any size, so it reads like an icon in a row and like pixel art
/// when large. It takes the foreground style, like an SF Symbol, and blinks
/// now and then: for a tenth of a second every 4 to 9 seconds it draws its
/// closed frame, the same drawing with each eye only its bottom row, never
/// with Reduce Motion on.
struct BotMark: View {
    var size: CGFloat = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false

    var body: some View {
        BotMarkShape(eyesOpen: !blinking)
            .frame(width: size, height: size)
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

/// One frame of the drawing, as one path merged into a single outline, so
/// smooth edges leave no seams between squares: `#` the outline, `E` eye
/// squares of the open frame only, `e` eye squares of both frames. The same
/// drawing as the web's.
nonisolated struct BotMarkShape: Shape {
    var eyesOpen = true

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
            for (x, square) in row.enumerated() where square == "#" || square == "e" || (eyesOpen && square == "E") {
                path.addRect(CGRect(x: rect.minX + CGFloat(x) * cell, y: rect.minY + CGFloat(y) * cell, width: cell, height: cell))
            }
        }
        return path.normalized()
    }
}
