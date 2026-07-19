import AppKit

let invader = [
    "..#..#..",
    "...##...",
    "..####..",
    ".######.",
    "##.##.##",
    "########",
    "#.#..#.#",
    ".#....#.",
]

let dotColors: [NSColor] = [
    NSColor(calibratedRed: 0.20, green: 0.82, blue: 0.35, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.00, alpha: 1),
    NSColor(calibratedRed: 0.95, green: 0.26, blue: 0.21, alpha: 1),
]

func draw(canvas: CGFloat) {
    let inset = canvas * 0.098
    let card = NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
    let radius = card.width * 0.225
    let path = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)

    NSColor(calibratedRed: 0.075, green: 0.075, blue: 0.09, alpha: 1).setFill()
    path.fill()

    let gradient = NSGradient(
        starting: NSColor(calibratedWhite: 1, alpha: 0),
        ending: NSColor(calibratedWhite: 1, alpha: 0.09)
    )
    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()
    gradient?.draw(in: card, angle: 90)
    NSGraphicsContext.current?.restoreGraphicsState()

    path.lineWidth = max(1, canvas * 0.006)
    NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
    path.stroke()

    let showDots = canvas >= 64
    let span = card.width * (showDots ? 0.60 : 0.68)
    let px = span / 8
    let originX = card.midX - px * 4
    let originY = card.midY - px * 4 + (showDots ? card.height * 0.055 : 0)

    NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.0, alpha: 1).setFill()
    for (y, row) in invader.enumerated() {
        for (x, ch) in row.enumerated() where ch == "#" {
            NSRect(
                x: originX + CGFloat(x) * px,
                y: originY + CGFloat(invader.count - 1 - y) * px,
                width: px * 0.90,
                height: px * 0.90
            ).fill()
        }
    }

    if showDots {
        let dot = card.width * 0.052
        let gap = dot * 1.9
        let totalWidth = gap * 2 + dot
        let startX = card.midX - totalWidth / 2
        let dotY = card.minY + card.height * 0.16
        for (i, color) in dotColors.enumerated() {
            color.setFill()
            NSRect(x: startX + CGFloat(i) * gap, y: dotY, width: dot, height: dot).fill()
        }
    }
}

func writePNG(pixels: Int, to url: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    draw(canvas: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (points, scale) in variants {
    let suffix = scale == 2 ? "@2x" : ""
    writePNG(pixels: points * scale, to: outDir.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}
print("iconset written to \(outDir.path)")
