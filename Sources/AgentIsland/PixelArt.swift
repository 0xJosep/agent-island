import SwiftUI

struct Sprite {
    let frames: [[String]]
    let palette: [Character: Color]
    let frameDuration: Double

    static let invader = Sprite(
        frames: [
            [
                "..#..#..",
                "...##...",
                "..####..",
                ".######.",
                "##.##.##",
                "########",
                "#.#..#.#",
                ".#....#.",
            ],
            [
                "..#..#..",
                "...##...",
                "..####..",
                ".######.",
                "##.##.##",
                "########",
                ".#....#.",
                "#.#..#.#",
            ],
        ],
        palette: ["#": .orange],
        frameDuration: 0.45
    )

    static let check = Sprite(
        frames: [
            [
                "........",
                ".......#",
                "......##",
                ".....##.",
                "#...##..",
                "##.##...",
                ".###....",
                "..#.....",
            ],
            [
                "w.......",
                ".......#",
                "......##",
                ".....##.",
                "#...##..",
                "##.##...",
                ".###....",
                "..#....w",
            ],
        ],
        palette: ["#": .green, "w": .white],
        frameDuration: 0.5
    )

    static let alert = Sprite(
        frames: [
            [
                "...##...",
                "...##...",
                "...##...",
                "...##...",
                "...##...",
                "........",
                "...##...",
                "...##...",
            ],
            [
                "...dd...",
                "...dd...",
                "...dd...",
                "...dd...",
                "...dd...",
                "........",
                "...dd...",
                "...dd...",
            ],
        ],
        palette: ["#": .red, "d": .red.opacity(0.25)],
        frameDuration: 0.4
    )

    static let lock = Sprite(
        frames: [
            [
                "..####..",
                ".#....#.",
                ".#....#.",
                "########",
                "########",
                "###..###",
                "###..###",
                "########",
            ],
        ],
        palette: ["#": .orange],
        frameDuration: 1
    )

    static let zzz = Sprite(
        frames: [
            [
                ".####...",
                "....#...",
                "...#....",
                "..####..",
                "........",
                "....###.",
                ".....#..",
                "....###.",
            ],
        ],
        palette: ["#": .gray],
        frameDuration: 1
    )

    static func forStatus(_ status: AgentStatus) -> Sprite {
        switch status {
        case .working: return .invader
        case .finished: return .check
        case .needsInput: return .alert
        case .idle: return .zzz
        }
    }
}

struct PixelArt: View {
    let sprite: Sprite
    var size: CGFloat = 16

    var body: some View {
        TimelineView(.periodic(from: .now, by: sprite.frameDuration)) { context in
            let index = sprite.frames.count > 1
                ? Int(context.date.timeIntervalSinceReferenceDate / sprite.frameDuration) % sprite.frames.count
                : 0
            Canvas { ctx, canvasSize in
                let rows = sprite.frames[index]
                let height = rows.count
                let width = rows.map(\.count).max() ?? 1
                let px = min(canvasSize.width / CGFloat(width), canvasSize.height / CGFloat(height))
                for (y, row) in rows.enumerated() {
                    for (x, ch) in row.enumerated() {
                        guard let color = sprite.palette[ch] else { continue }
                        let rect = CGRect(
                            x: CGFloat(x) * px,
                            y: CGFloat(y) * px,
                            width: px * 0.92,
                            height: px * 0.92
                        )
                        ctx.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}
