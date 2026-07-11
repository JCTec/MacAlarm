import AppKit

struct BrandAsset {
    let title: String
    let subtitle: String
    let input: String
    let output: String
    let accent: NSColor
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = root.appendingPathComponent("DesignAssets/Branding", isDirectory: true)

let assets = [
    BrandAsset(
        title: "MacAlarm",
        subtitle: "A live security timeline for your Mac.",
        input: "/Users/jc/Desktop/Screenshot 2026-06-30 at 7.50.00\u{202f}a.m..png",
        output: "macalarm-hero.png",
        accent: NSColor(calibratedRed: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 1)
    ),
    BrandAsset(
        title: "Investigate what happened",
        subtitle: "Filter, zoom, and inspect local events without leaving your machine.",
        input: "/Users/jc/Desktop/Screenshot 2026-06-30 at 7.50.09\u{202f}a.m..png",
        output: "macalarm-timeline-detail.png",
        accent: NSColor(calibratedRed: 10 / 255, green: 132 / 255, blue: 255 / 255, alpha: 1)
    ),
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawText(
    _ text: String,
    in rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph,
    ]
    text.draw(in: rect, withAttributes: attributes)
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

func drawScreenshot(_ screenshot: NSImage, in rect: NSRect) {
    NSGraphicsContext.current?.saveGraphicsState()

    NSShadow().then {
        $0.shadowColor = NSColor.black.withAlphaComponent(0.45)
        $0.shadowBlurRadius = 34
        $0.shadowOffset = NSSize(width: 0, height: -18)
    }.set()

    drawRoundedRect(rect, radius: 26, fill: color(20, 24, 25), stroke: color(255, 255, 255, 0.12))
    NSGraphicsContext.current?.restoreGraphicsState()

    let clipPath = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 25, yRadius: 25)
    NSGraphicsContext.current?.saveGraphicsState()
    clipPath.addClip()
    let sourceRect = NSRect(
        x: 0,
        y: 180,
        width: screenshot.size.width,
        height: screenshot.size.height - 180
    )
    screenshot.draw(in: rect, from: sourceRect, operation: .copy, fraction: 1)
    NSGraphicsContext.current?.restoreGraphicsState()
}

func drawBackground(size: NSSize, accent: NSColor) {
    let canvas = NSRect(origin: .zero, size: size)
    NSGradient(colors: [
        color(13, 18, 20),
        color(27, 35, 35),
        color(18, 20, 23),
    ])?.draw(in: canvas, angle: -24)

    for x in stride(from: CGFloat(0), through: size.width, by: 64) {
        color(255, 255, 255, 0.035).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: 0))
        path.line(to: NSPoint(x: x, y: size.height))
        path.lineWidth = 1
        path.stroke()
    }

    let glow = NSBezierPath(ovalIn: NSRect(x: -180, y: size.height - 360, width: 560, height: 560))
    accent.withAlphaComponent(0.20).setFill()
    glow.fill()

    let secondGlow = NSBezierPath(ovalIn: NSRect(x: size.width - 360, y: -220, width: 520, height: 520))
    color(10, 132, 255, 0.16).setFill()
    secondGlow.fill()
}

func render(_ asset: BrandAsset) throws {
    guard let screenshot = NSImage(contentsOfFile: asset.input) else {
        throw NSError(domain: "MacAlarmBranding", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing screenshot: \(asset.input)"])
    }

    let size = NSSize(width: 1800, height: 1120)
    let image = NSImage(size: size)

    image.lockFocus()
    drawBackground(size: size, accent: asset.accent)

    let screenshotRect = NSRect(x: 150, y: 238, width: 1500, height: 786)
    drawScreenshot(screenshot, in: screenshotRect)

    drawRoundedRect(
        NSRect(x: 148, y: 68, width: 1504, height: 76),
        radius: 28,
        fill: color(255, 255, 255, 0.065),
        stroke: color(255, 255, 255, 0.10)
    )

    asset.accent.setFill()
    NSBezierPath(ovalIn: NSRect(x: 190, y: 94, width: 24, height: 24)).fill()
    drawText(asset.title, in: NSRect(x: 232, y: 89, width: 460, height: 38), size: 30, weight: .bold, color: color(245, 248, 249))
    drawText(asset.subtitle, in: NSRect(x: 720, y: 92, width: 770, height: 34), size: 22, weight: .medium, color: color(181, 191, 195))
    drawText("Local-first Mac ledger", in: NSRect(x: 1310, y: 92, width: 280, height: 34), size: 18, weight: .semibold, color: color(245, 248, 249, 0.70), alignment: .right)

    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "MacAlarmBranding", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }

    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try png.write(to: outputDirectory.appendingPathComponent(asset.output))
}

extension NSObject {
    func then(_ configure: (Self) -> Void) -> Self {
        configure(self)
        return self
    }
}

for asset in assets {
    try render(asset)
    print(outputDirectory.appendingPathComponent(asset.output).path)
}
