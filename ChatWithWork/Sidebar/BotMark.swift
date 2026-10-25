import SwiftUI

/// The bots' mark, as the web draws it (`BotMark` in the Rails app): a pixel
/// chat bubble with two eyes, on its 10 by 10 grid, so at 20pt every square
/// is two or three whole pixels. It takes the foreground style, like an SF
/// Symbol, and blinks now and then: the eyes close to their last row for a
/// tenth of a second every 4 to 9 seconds, never with Reduce Motion on.
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

/// The mark's squares: `#` the outline, `E` an eye that closes, `e` an eye's
/// last row, which stays. The same grid as the web's for 20 and 40px.
nonisolated struct BotMarkShape: Shape {
    var eyesOpen = true

    static let grid = [
        ".########.",
        "#oooooooo#",
        "#oooooooo#",
        "#oEEooEEo#",
        "#oeeooeeo#",
        "#oooooooo#",
        "#oooooooo#",
        ".##oo####.",
        "..#o#.....",
        "..##......",
    ]

    func path(in rect: CGRect) -> Path {
        let cell = min(rect.width, rect.height) / CGFloat(Self.grid.count)
        var path = Path()
        for (y, row) in Self.grid.enumerated() {
            for (x, square) in row.enumerated() where square == "#" || square == "e" || (eyesOpen && square == "E") {
                path.addRect(CGRect(x: rect.minX + CGFloat(x) * cell, y: rect.minY + CGFloat(y) * cell, width: cell, height: cell))
            }
        }
        return path
    }
}
