import UIKit

/// A surah's header band on a mushaf page: the Today card's deep green with its nested arches
/// coming in from both ends, and a pointed cartouche around the name between two eight-pointed
/// stars, after the ornamented headers of a printed mushaf. The same in light and dark, like the card.
enum MushafHeaderOrnament {
    /// Lengths are shares of the band's height, so the ornament scales with the page.
    private enum Style {
        static let cornerRadius: CGFloat = 6
        static let lineWidth: CGFloat = 1
        static let hairline: CGFloat = 0.75

        static let archCount = 4
        static let archStep: CGFloat = 0.34
        static let archOpacity: CGFloat = 0.13

        static let innerFrameInset: CGFloat = 3
        static let innerFrameOpacity: CGFloat = 0.16

        static let cartoucheHeight: CGFloat = 0.68
        /// Room each side of the name, inside the cartouche.
        static let cartouchePadding: CGFloat = 0.75
        /// How far each pointed end reaches in.
        static let cartoucheTip: CGFloat = 0.42
        static let cartoucheFillOpacity: CGFloat = 0.08
        static let cartoucheStrokeOpacity: CGFloat = 0.55

        static let starRadius: CGFloat = 0.25
        static let starOpacity: CGFloat = 0.6
        static let dotRadius: CGFloat = 0.04
        static let ruleOpacity: CGFloat = 0.3
        /// Gap between a rule and what it runs to.
        static let ruleGap: CGFloat = 0.14
    }

    /// Draws the band; the name is drawn on top of it afterwards. `nameWidth` sizes the cartouche.
    static func draw(in band: CGRect, nameWidth: CGFloat, alpha: CGFloat, in context: CGContext) {
        let height = band.height
        context.saveGState()
        context.setAlpha(alpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(UIBezierPath(roundedRect: band, cornerRadius: Style.cornerRadius).cgPath)
        context.clip()

        fillGradient(band, in: context)
        strokeArches(band, in: context)

        let inner = band.insetBy(dx: Style.innerFrameInset, dy: Style.innerFrameInset)
        context.setLineWidth(Style.hairline)
        context.setStrokeColor(UIColor.white.withAlphaComponent(Style.innerFrameOpacity).cgColor)
        context.addPath(UIBezierPath(roundedRect: inner, cornerRadius: Style.cornerRadius - Style.innerFrameInset / 2).cgPath)
        context.strokePath()

        let cartoucheWidth = min(nameWidth + height * Style.cartouchePadding * 2, band.width * 0.6)
        let cartouche = CGRect(x: band.midX - cartoucheWidth / 2, y: band.midY - height * Style.cartoucheHeight / 2,
                               width: cartoucheWidth, height: height * Style.cartoucheHeight)
        drawCartouche(cartouche, tip: height * Style.cartoucheTip, in: context)

        // A star each side, halfway between the cartouche and the arches, joined to the cartouche by a rule.
        let archReach = height * Style.archStep * CGFloat(Style.archCount)
        let starRadius = height * Style.starRadius
        let gap = height * Style.ruleGap
        for side in [-1.0, 1.0] as [CGFloat] {
            let cartoucheEdge = side < 0 ? cartouche.minX : cartouche.maxX
            let archEdge = side < 0 ? band.minX + archReach : band.maxX - archReach
            let center = CGPoint(x: (cartoucheEdge + archEdge) / 2, y: band.midY)
            drawStar(at: center, radius: starRadius, in: context)
            context.setLineWidth(Style.hairline)
            context.setStrokeColor(DeepGreen.accent.withAlphaComponent(Style.ruleOpacity).cgColor)
            context.move(to: CGPoint(x: center.x - side * (starRadius + gap), y: band.midY))
            context.addLine(to: CGPoint(x: cartoucheEdge + side * gap, y: band.midY))
            context.move(to: CGPoint(x: center.x + side * (starRadius + gap), y: band.midY))
            context.addLine(to: CGPoint(x: archEdge - side * gap, y: band.midY))
            context.strokePath()
        }

        context.endTransparencyLayer()
        context.restoreGState()
    }

    private static func fillGradient(_ band: CGRect, in context: CGContext) {
        let colors = [DeepGreen.top.cgColor, DeepGreen.bottom.cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: band.minX, y: band.minY),
                                   end: CGPoint(x: band.maxX, y: band.maxY), options: [])
    }

    /// Rings centred on each end, which the band cuts down to arches.
    private static func strokeArches(_ band: CGRect, in context: CGContext) {
        context.setLineWidth(Style.lineWidth)
        context.setStrokeColor(UIColor.white.withAlphaComponent(Style.archOpacity).cgColor)
        for end in [band.minX, band.maxX] {
            for ring in 1...Style.archCount {
                let radius = band.height * Style.archStep * CGFloat(ring)
                context.addEllipse(in: CGRect(x: end - radius, y: band.midY - radius, width: radius * 2, height: radius * 2))
            }
        }
        context.strokePath()
    }

    /// A long frame with pointed, gently curved ends.
    private static func drawCartouche(_ rect: CGRect, tip: CGFloat, in context: CGContext) {
        let path = CGMutablePath()
        let mid = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: mid))
        path.addCurve(to: CGPoint(x: rect.minX + tip, y: rect.minY),
                      control1: CGPoint(x: rect.minX + tip * 0.35, y: mid),
                      control2: CGPoint(x: rect.minX + tip * 0.45, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tip, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: mid),
                      control1: CGPoint(x: rect.maxX - tip * 0.45, y: rect.minY),
                      control2: CGPoint(x: rect.maxX - tip * 0.35, y: mid))
        path.addCurve(to: CGPoint(x: rect.maxX - tip, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX - tip * 0.35, y: mid),
                      control2: CGPoint(x: rect.maxX - tip * 0.45, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + tip, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: mid),
                      control1: CGPoint(x: rect.minX + tip * 0.45, y: rect.maxY),
                      control2: CGPoint(x: rect.minX + tip * 0.35, y: mid))
        path.closeSubpath()

        context.addPath(path)
        context.setFillColor(UIColor.white.withAlphaComponent(Style.cartoucheFillOpacity).cgColor)
        context.fillPath()
        context.addPath(path)
        context.setLineWidth(Style.lineWidth)
        context.setStrokeColor(DeepGreen.accent.withAlphaComponent(Style.cartoucheStrokeOpacity).cgColor)
        context.strokePath()
    }

    /// Two squares, one turned an eighth, with a dot in the middle.
    private static func drawStar(at center: CGPoint, radius: CGFloat, in context: CGContext) {
        let side = radius * sqrt(2)
        let square = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
        context.setLineWidth(Style.lineWidth)
        context.setStrokeColor(DeepGreen.accent.withAlphaComponent(Style.starOpacity).cgColor)
        for turn in [0, CGFloat.pi / 4] {
            let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: turn)
            context.addPath(CGPath(rect: square, transform: [transform]))
        }
        context.strokePath()
        let dot = radius * Style.dotRadius / Style.starRadius
        context.setFillColor(DeepGreen.accent.withAlphaComponent(Style.starOpacity).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))
    }
}
