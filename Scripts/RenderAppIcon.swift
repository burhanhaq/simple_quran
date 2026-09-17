#!/usr/bin/env swift
import AppKit
import Foundation

private let canvasSize: CGFloat = 1024
private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

private enum Appearance {
    case fullColor
    case tinted
}

struct ArchMetrics {
    var left: CGFloat
    var right: CGFloat
    var footY: CGFloat
    var springY: CGFloat
    var peakY: CGFloat
    var lobeOutset: CGFloat

    var midX: CGFloat { (left + right) / 2 }

    func inset(_ distance: CGFloat) -> ArchMetrics {
        ArchMetrics(
            left: left + distance,
            right: right - distance,
            footY: footY - distance * 0.15,
            springY: springY,
            peakY: peakY + distance,
            lobeOutset: max(lobeOutset - distance * 0.25, 0)
        )
    }
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
    try writePNG(appearance: .tinted, to: iconSet.appendingPathComponent("AppIcon-Tinted.png"))
    fputs("Wrote AppIcon.png and AppIcon-Tinted.png\n", stdout)
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
    if appearance == .fullColor {
        fillBackground(in: ctx, canvas: canvas)
    }

    let outer = ArchMetrics(
        left: 278,
        right: 746,
        footY: 808,
        springY: 530,
        peakY: 188,
        lobeOutset: 36
    )
    let inner = outer.inset(42)
    let vault = inner.inset(34)

    let strokes: [(CGPath, CGFloat)] = [
        (archPath(outer), 14),
        (archPath(inner, includeFeet: false), 8),
        (archPath(vault, includeFeet: false), 6),
        (lozengePath(center: CGPoint(x: vault.midX, y: vault.peakY + 52), radiusX: 18, radiusY: 28), 5.5),
        (bookPath(center: CGPoint(x: outer.midX, y: 612), width: 268), 8)
    ]

    for (path, width) in strokes {
        strokePath(path, width: width, appearance: appearance, in: ctx, canvas: canvas)
    }
}

private func fillBackground(in ctx: CGContext, canvas: CGRect) {
    let center = CGColor(colorSpace: p3, components: [0.165, 0.094, 0.047, 1])!
    let edge = CGColor(colorSpace: p3, components: [0.110, 0.063, 0.031, 1])!
    let gradient = CGGradient(colorsSpace: p3, colors: [center, edge] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(
        gradient,
        startCenter: CGPoint(x: canvas.midX, y: canvas.midY - 40),
        startRadius: 0,
        endCenter: CGPoint(x: canvas.midX, y: canvas.midY),
        endRadius: canvas.width * 0.72,
        options: [.drawsAfterEndLocation]
    )
}

private func archPath(_ metrics: ArchMetrics, includeFeet: Bool = true) -> CGPath {
    let path = CGMutablePath()
    let midX = metrics.midX
    let lobeY = metrics.springY - (metrics.springY - metrics.peakY) * 0.28
    let leftLobe = CGPoint(x: metrics.left - metrics.lobeOutset, y: lobeY)
    let rightLobe = CGPoint(x: metrics.right + metrics.lobeOutset, y: lobeY)
    let peak = CGPoint(x: midX, y: metrics.peakY)

    if includeFeet {
        path.move(to: CGPoint(x: metrics.left, y: metrics.footY))
        path.addLine(to: CGPoint(x: metrics.left, y: metrics.springY))
    } else {
        path.move(to: CGPoint(x: metrics.left, y: metrics.springY))
    }

    path.addCurve(
        to: leftLobe,
        control1: CGPoint(x: metrics.left, y: metrics.springY - 70),
        control2: CGPoint(x: leftLobe.x, y: metrics.springY - 36)
    )
    path.addCurve(
        to: peak,
        control1: CGPoint(x: leftLobe.x + 12, y: metrics.peakY + 96),
        control2: CGPoint(x: midX - 92, y: metrics.peakY + 8)
    )
    path.addCurve(
        to: rightLobe,
        control1: CGPoint(x: midX + 92, y: metrics.peakY + 8),
        control2: CGPoint(x: rightLobe.x - 12, y: metrics.peakY + 96)
    )
    path.addCurve(
        to: CGPoint(x: metrics.right, y: metrics.springY),
        control1: CGPoint(x: rightLobe.x, y: metrics.springY - 36),
        control2: CGPoint(x: metrics.right, y: metrics.springY - 70)
    )

    if includeFeet {
        path.addLine(to: CGPoint(x: metrics.right, y: metrics.footY))
    }
    return path
}

private func lozengePath(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: center.x, y: center.y - radiusY))
    path.addLine(to: CGPoint(x: center.x + radiusX, y: center.y))
    path.addLine(to: CGPoint(x: center.x, y: center.y + radiusY))
    path.addLine(to: CGPoint(x: center.x - radiusX, y: center.y))
    path.closeSubpath()
    return path
}

private func bookPath(center: CGPoint, width: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let height = width * 0.46
    let gutter: CGFloat = 7
    let pageLift: CGFloat = 22
    let drop: CGFloat = 14

    let spineTop = CGPoint(x: center.x, y: center.y - height / 2)
    let spineBottom = CGPoint(x: center.x, y: center.y + height / 2 - 6)
    let leftTop = CGPoint(x: center.x - width / 2, y: spineTop.y + pageLift)
    let leftBottom = CGPoint(x: center.x - width / 2 + 6, y: spineBottom.y + drop)
    let rightTop = CGPoint(x: center.x + width / 2, y: spineTop.y + pageLift)
    let rightBottom = CGPoint(x: center.x + width / 2 - 6, y: spineBottom.y + drop)

    path.move(to: CGPoint(x: spineTop.x - gutter, y: spineTop.y + 4))
    path.addLine(to: leftTop)
    path.addLine(to: leftBottom)
    path.addLine(to: CGPoint(x: spineBottom.x - gutter, y: spineBottom.y))
    path.closeSubpath()

    path.move(to: CGPoint(x: spineTop.x + gutter, y: spineTop.y + 4))
    path.addLine(to: rightTop)
    path.addLine(to: rightBottom)
    path.addLine(to: CGPoint(x: spineBottom.x + gutter, y: spineBottom.y))
    path.closeSubpath()

    path.move(to: spineTop)
    path.addLine(to: spineBottom)

    addPageLines(path, topInner: CGPoint(x: spineTop.x - gutter, y: spineTop.y + 28), topOuter: leftTop, bottomInner: CGPoint(x: spineBottom.x - gutter, y: spineBottom.y - 18), bottomOuter: leftBottom)
    addPageLines(path, topInner: CGPoint(x: spineTop.x + gutter, y: spineTop.y + 28), topOuter: rightTop, bottomInner: CGPoint(x: spineBottom.x + gutter, y: spineBottom.y - 18), bottomOuter: rightBottom)

    let standTop = spineBottom.y + 18
    let standWidth = width * 0.42
    path.move(to: CGPoint(x: center.x - standWidth / 2, y: standTop))
    path.addLine(to: CGPoint(x: center.x + standWidth / 2, y: standTop))
    path.addLine(to: CGPoint(x: center.x + standWidth / 2 + 16, y: standTop + 22))
    path.addLine(to: CGPoint(x: center.x - standWidth / 2 - 16, y: standTop + 22))
    path.closeSubpath()
    path.move(to: CGPoint(x: center.x - standWidth / 2 - 28, y: standTop + 34))
    path.addLine(to: CGPoint(x: center.x + standWidth / 2 + 28, y: standTop + 34))
    return path
}

private func addPageLines(
    _ path: CGMutablePath,
    topInner: CGPoint,
    topOuter: CGPoint,
    bottomInner: CGPoint,
    bottomOuter: CGPoint
) {
    for index in 1...3 {
        let t = CGFloat(index) / 4
        let inner = lerp(topInner, bottomInner, t)
        let outer = lerp(topOuter, bottomOuter, t)
        let shortened = lerp(inner, outer, 0.78)
        path.move(to: lerp(inner, outer, 0.12))
        path.addLine(to: shortened)
    }
}

private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

private func strokePath(
    _ path: CGPath,
    width: CGFloat,
    appearance: Appearance,
    in ctx: CGContext,
    canvas: CGRect
) {
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setMiterLimit(2)

    switch appearance {
    case .tinted:
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.setLineWidth(width)
        ctx.addPath(path)
        ctx.strokePath()
    case .fullColor:
        strokeGold(path, width: width, in: ctx, canvas: canvas)
    }
    ctx.restoreGState()
}

private func strokeGold(_ path: CGPath, width: CGFloat, in ctx: CGContext, canvas: CGRect) {
    let highlight = CGColor(colorSpace: p3, components: [1.00, 0.95, 0.72, 1])!
    let mid = CGColor(colorSpace: p3, components: [0.83, 0.65, 0.16, 1])!
    let bronze = CGColor(colorSpace: p3, components: [0.52, 0.36, 0.06, 1])!
    let gold = CGGradient(
        colorsSpace: p3,
        colors: [highlight, mid, bronze] as CFArray,
        locations: [0, 0.45, 1]
    )!

    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gold,
        start: CGPoint(x: canvas.minX + 180, y: canvas.minY + 140),
        end: CGPoint(x: canvas.maxX - 140, y: canvas.maxY - 120),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    let sheen = CGGradient(
        colorsSpace: p3,
        colors: [
            CGColor(colorSpace: p3, components: [1, 0.98, 0.86, 0.85])!,
            CGColor(colorSpace: p3, components: [1, 0.94, 0.72, 0])!
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        sheen,
        start: CGPoint(x: canvas.minX + 160, y: canvas.minY + 120),
        end: CGPoint(x: canvas.midX + 40, y: canvas.midY - 40),
        options: []
    )
    ctx.restoreGState()
}

exit(try main())
