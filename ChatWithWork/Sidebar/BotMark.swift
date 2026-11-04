import SwiftUI

/// The bots' mark, as the web draws it (`BotMark` in the Rails app): our
/// pixel chat bubble with two tall eyes, one 16-square drawing scaled
/// smoothly to any size, so it reads like an icon in a row and like pixel art
/// when large. It takes the foreground style, like an SF Symbol, and blinks
/// now and then: for a tenth of a second every 4 to 9 seconds it draws its
/// closed frame, the same drawing with each eye only its bottom row, never
/// with Reduce Motion on.
///
/// A face (the web's `bot_mark face:`) takes the blink's place: thinking and
/// writing move their eyes in two steps, the others hold still, as do both
/// under Reduce Motion. With a colour (a bot's, the web's `bot_mark colour:`)
/// it's a sticker: the whole bubble on that paper, with black lines and eyes,
/// the same in both themes.
struct BotMark: View {
    var size: CGFloat = 20
    var face: BotMarkShape.Face?
    var colour: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false
    @State private var frame = 0

    var body: some View {
        ZStack {
            if let colour {
                BotMarkShape(face: face, layer: .paper).fill(colour)
                BotMarkShape(eyesOpen: !blinking, face: face, frame: frame).fill(Color.black)
            } else {
                BotMarkShape(eyesOpen: !blinking, face: face, frame: frame)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: Motion(reduceMotion: reduceMotion, face: face)) {
            blinking = false
            frame = 0
            guard !reduceMotion else { return }
            if let face {
                guard let step = face.step, face.frames.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: step)
                    guard !Task.isCancelled else { return }
                    frame = (frame + 1) % face.frames.count
                }
            } else {
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

    private struct Motion: Equatable {
        let reduceMotion: Bool
        let face: BotMarkShape.Face?
    }
}

/// One frame of the drawing, as one path merged into a single outline, so
/// smooth edges leave no seams between squares: `#` the outline, `o` the
/// inside, `E` eye squares of the open frame only, `e` eye squares of both
/// frames. The same drawing as the web's.
nonisolated struct BotMarkShape: Shape {
    /// Other eyes for what it's doing (`BotMark::FACES`), frame by frame, as
    /// `x, y, width, height` squares of the grid: thinking looks up and
    /// about, writing reads along a line, waiting looks at you wide-eyed,
    /// happy smiles with them, for nothing left to do, and flat is a level
    /// line, for what didn't finish or was stopped.
    enum Face: String, Sendable, CaseIterable {
        case thinking, writing, waiting, happy, flat

        var frames: [[(Int, Int, Int, Int)]] {
            switch self {
            case .thinking: [[(5, 4, 2, 3), (11, 4, 2, 3)], [(3, 4, 2, 3), (9, 4, 2, 3)]]
            case .writing: [[(5, 7, 2, 2), (11, 7, 2, 2)], [(3, 7, 2, 2), (9, 7, 2, 2)]]
            case .waiting: [[(3, 4, 3, 1), (3, 5, 1, 1), (5, 5, 1, 1), (3, 6, 3, 2), (10, 4, 3, 1), (10, 5, 1, 1), (12, 5, 1, 1), (10, 6, 3, 2)]]
            case .happy: [[(3, 7, 1, 1), (4, 6, 2, 1), (6, 7, 1, 1), (9, 7, 1, 1), (10, 6, 2, 1), (12, 7, 1, 1)]]
            case .flat: [[(3, 7, 3, 1), (10, 7, 3, 1)]]
            }
        }

        /// How long each of a moving face's frames shows, as the web's CSS
        /// swaps them; nil for a still one.
        var step: Duration? {
            switch self {
            case .thinking: .milliseconds(1600)
            case .writing: .milliseconds(800)
            default: nil
            }
        }
    }

    /// The lines and eyes, or the paper under them: the whole bubble, so
    /// smooth scaling leaves no gap between the two.
    enum Layer: Sendable {
        case ink, paper
    }

    var eyesOpen = true
    var face: Face?
    var frame = 0
    var layer: Layer = .ink

    static let grid = [
        "................",
        "................",
        ".##############.",
        "#oooooooooooooo#",
        "#oooooooooooooo#",
        "#oooEEooooEEooo#",
        "#oooEEooooEEooo#",
        "#oooeeooooeeooo#",
        "#oooooooooooooo#",
        "#oooooooooooooo#",
        "#oooooooooooooo#",
        ".###ooo########.",
        "...#oo#.........",
        "...#o#..........",
        "...##...........",
        "................",
    ]

    func path(in rect: CGRect) -> Path {
        let cell = min(rect.width, rect.height) / CGFloat(Self.grid.count)
        var path = Path()
        for (y, row) in Self.grid.enumerated() {
            for (x, square) in row.enumerated() where drawn(square) {
                path.addRect(CGRect(x: rect.minX + CGFloat(x) * cell, y: rect.minY + CGFloat(y) * cell, width: cell, height: cell))
            }
        }
        if layer == .ink, let frames = face?.frames {
            for (x, y, width, height) in frames[frame % frames.count] {
                path.addRect(CGRect(x: rect.minX + CGFloat(x) * cell, y: rect.minY + CGFloat(y) * cell, width: CGFloat(width) * cell, height: CGFloat(height) * cell))
            }
        }
        return path.normalized()
    }

    private func drawn(_ square: Character) -> Bool {
        switch layer {
        case .paper: square != "."
        case .ink: square == "#" || (face == nil && (square == "e" || (eyesOpen && square == "E")))
        }
    }
}
