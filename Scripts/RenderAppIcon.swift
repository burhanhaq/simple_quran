#!/usr/bin/env swift
import AppKit
import Foundation

private let canvasSize: CGFloat = 1024
private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

private enum Appearance {
    case fullColor
    case dark
    case tinted
}

/// Colors mirror the home hero gradient and the dark-mode GoldAccent mint.
private enum Palette {
    static let emeraldTop = color(0.15, 0.33, 0.26)
    static let emeraldBottom = color(0.07, 0.23, 0.18)
    static let nightTop = color(0.086, 0.141, 0.122)
    static let nightBottom = color(0.043, 0.075, 0.067)
    static let mintHighlight = color(0.71, 0.91, 0.81)
    static let mint = color(0.60, 0.86, 0.73)
    static let mintShadow = color(0.50, 0.79, 0.65)
    static let tintedMark = CGColor(gray: 1, alpha: 1)

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: p3, components: [red, green, blue, alpha])!
    }
}

private enum Geometry {
    static let center = CGPoint(x: canvasSize / 2, y: canvasSize / 2)
    static let starSquareSide: CGFloat = 472
    static let starCornerRadius: CGFloat = 30
    static let ringRadius: CGFloat = 176
    static let ringWidth: CGFloat = 10
    static let bookHalfWidth: CGFloat = 136
    static let bookTopY: CGFloat = 446
    static let bookPageHeight: CGFloat = 126
    static let bookGutter: CGFloat = 9
}

@discardableResult
func main() throws -> Int32 {
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    let iconSet = projectRoot
        .appendingPathComponent("Simple Quran")
        .appendingPathComponent("Assets.xcassets")
        .appendingPathComponent("AppIcon.appiconset")

    try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
    try writePNG(appearance: .fullColor, to: iconSet.appendingPathComponent("AppIcon.png"))
    try writePNG(appearance: .dark, to: iconSet.appendingPathComponent("AppIcon-Dark.png"))
    try writePNG(appearance: .tinted, to: iconSet.appendingPathComponent("AppIcon-Tinted.png"))
    fputs("Wrote AppIcon.png, AppIcon-Dark.png, and AppIcon-Tinted.png\n", stdout)
    return 0
}

private func writePNG(appearance: Appearance, to url: URL) throws {
    guard let png = renderPNG(appearance: appearance) else {
        throw NSError(domain: "RenderAppIcon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to encode \(url.lastPathComponent)"
        ])
    }
    try png.write(to: url, options: .atomic)
}

private func renderPNG(appearance: Appearance) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize),
        pixelsHigh: Int(canvasSize),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: NSColorSpaceName.deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: canvasSize, height: canvasSize)

    guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let ctx = graphics.cgContext
    ctx.translateBy(x: 0, y: canvasSize)
    ctx.scaleBy(x: 1, y: -1)
    drawIcon(in: ctx, appearance: appearance)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

private func drawIcon(in ctx: CGContext, appearance: Appearance) {
    let canvas = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    fillStar(in: ctx, appearance: appearance)

    // The book and ring are cut out of the star so the background shows through,
    // which keeps them legible in every appearance, including the system tint.
    ctx.saveGState()
    ctx.setBlendMode(.clear)
    ctx.addPath(bookPath())
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setBlendMode(.destinationOut)
    ctx.setAlpha(0.22)
    ctx.setLineWidth(Geometry.ringWidth)
    ctx.strokeEllipse(in: CGRect(
        x: Geometry.center.x - Geometry.ringRadius,
        y: Geometry.center.y - Geometry.ringRadius,
        width: Geometry.ringRadius * 2,
        height: Geometry.ringRadius * 2
    ))
    ctx.restoreGState()

    fillBackground(in: ctx, canvas: canvas, appearance: appearance, blendMode: .destinationOver)
}

private func fillBackground(
    in ctx: CGContext,
    canvas: CGRect,
    appearance: Appearance,
    blendMode: CGBlendMode = .normal
) {
    let top: CGColor
    let bottom: CGColor
    switch appearance {
    case .fullColor:
        top = Palette.emeraldTop
        bottom = Palette.emeraldBottom
    case .dark:
        top = Palette.nightTop
        bottom = Palette.nightBottom
    case .tinted:
        return
    }
    let gradient = CGGradient(colorsSpace: p3, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.setBlendMode(blendMode)
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: canvas.minX, y: canvas.minY),
        end: CGPoint(x: canvas.maxX, y: canvas.maxY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

private func fillStar(in ctx: CGContext, appearance: Appearance) {
    ctx.saveGState()
    ctx.addPath(starPath())
    ctx.clip()
    switch appearance {
    case .tinted:
        ctx.setFillColor(Palette.tintedMark)
        ctx.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    case .fullColor, .dark:
        let mint = CGGradient(
            colorsSpace: p3,
            colors: [Palette.mintHighlight, Palette.mint, Palette.mintShadow] as CFArray,
            locations: [0, 0.5, 1]
        )!
        let reach = Geometry.starSquareSide * 0.71
        ctx.drawLinearGradient(
            mint,
            start: CGPoint(x: Geometry.center.x - reach, y: Geometry.center.y - reach),
            end: CGPoint(x: Geometry.center.x + reach, y: Geometry.center.y + reach),
            options: []
        )
    }
    ctx.restoreGState()
}

/// Rub el hizb: two rounded squares, one turned 45°.
private func starPath() -> CGPath {
    let side = Geometry.starSquareSide
    let square = CGRect(
        x: Geometry.center.x - side / 2,
        y: Geometry.center.y - side / 2,
        width: side,
        height: side
    )
    let radius = Geometry.starCornerRadius
    let path = CGMutablePath()
    path.addRoundedRect(in: square, cornerWidth: radius, cornerHeight: radius)
    let rotation = CGAffineTransform(translationX: Geometry.center.x, y: Geometry.center.y)
        .rotated(by: .pi / 4)
        .translatedBy(x: -Geometry.center.x, y: -Geometry.center.y)
    path.addRoundedRect(in: square, cornerWidth: radius, cornerHeight: radius, transform: rotation)
    return path
}

/// An open book seen from the front: two gently curved pages meeting at the spine.
private func bookPath() -> CGPath {
    let path = CGMutablePath()
    for side in [-1.0, 1.0] as [CGFloat] {
        let spineX = Geometry.center.x + side * Geometry.bookGutter
        let outerX = Geometry.center.x + side * Geometry.bookHalfWidth
        let controlX = Geometry.center.x + side * Geometry.bookHalfWidth * 0.55
        let top = Geometry.bookTopY
        let height = Geometry.bookPageHeight

        path.move(to: CGPoint(x: spineX, y: top))
        path.addQuadCurve(to: CGPoint(x: outerX, y: top - 20), control: CGPoint(x: controlX, y: top - 30))
        path.addLine(to: CGPoint(x: outerX, y: top + height))
        path.addQuadCurve(to: CGPoint(x: spineX, y: top + height + 30), control: CGPoint(x: controlX, y: top + height - 10))
        path.closeSubpath()
    }
    return path
}

exit(try main())
