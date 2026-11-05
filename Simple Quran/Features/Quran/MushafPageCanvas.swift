import CoreText
import UIKit

/// One 15-line mushaf page, drawn line by line with CoreText so each line breaks where the printed
/// page does. Justified lines stretch edge to edge; highlights, dimming and slip marks only recolor,
/// so a page never reflows while it's read or recited.
final class MushafPageCanvas: UIView, MushafAyahContentView {
    var onRebuild: (() -> Void)?
    var onHidingChange: ((_ revealed: Set<Int>, _ covered: Set<Int>) -> Void)?
    var onSelect: ((Int) -> Void)?
    var selectionEnabled = true
    private(set) var hiddenAyahs: Set<Int> = []

    private var content = Content()
    private var lines: [MushafComposedLine] = []
    private var highlight = MushafHighlightState.empty
    private var metrics: MushafPageMetrics?
    private var laidOutSize: CGSize?
    private var placed: [PlacedLine] = []

    /// What decides where the lines go. Anything else only recolors. A page number always means
    /// the same lines, so they're never compared: comparing Arabic strings is slow.
    private struct Content: Equatable {
        var page = 0
        var widestLine: CGFloat = 0
        var referenceWidth: CGFloat = 0
    }

    private struct PlacedLine {
        var composed: MushafComposedLine
        var line: CTLine
        /// Where the text starts; y is the baseline.
        var origin: CGPoint
        /// The band the line's words fill, for highlights, bars and slip marks.
        var band: CGRect
        /// The frame a surah's name sits in.
        var frame: CGRect?
    }

    private enum Style {
        /// The band a line's highlight fills, as a share of its slot.
        static let bandHeight: CGFloat = 0.8
        static let frameInset: CGFloat = 0.08
        static let frameCornerRadius: CGFloat = 6
        static let frameLineWidth: CGFloat = 1.2
        static let underlineWidth: CGFloat = 2
        static let highlightCornerRadius: CGFloat = 4
        static let footerFont = UIFont.systemFont(ofSize: 13, weight: .medium)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.placeLines()
            self.setNeedsDisplay()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        page: Int,
        lines: [MushafComposedLine],
        widestLine: CGFloat,
        referenceWidth: CGFloat,
        highlight next: MushafHighlightState
    ) {
        let nextContent = Content(page: page, widestLine: widestLine, referenceWidth: referenceWidth)
        if nextContent != content {
            content = nextContent
            self.lines = lines
            highlight = next
            hiddenAyahs = next.hiddenAyahs
            laidOutSize = nil
            setNeedsLayout()
            return
        }
        guard next != highlight else { return }
        let previous = highlight
        highlight = next
        hiddenAyahs = next.hiddenAyahs
        // A moved highlight or a slip mark only needs drawing again; the lines stay as they are.
        if next.changesTextColors(from: previous) { placeLines() }
        setNeedsDisplay()
        let revealed = previous.hiddenAyahs.subtracting(next.hiddenAyahs)
        let covered = next.hiddenAyahs.subtracting(previous.hiddenAyahs)
        if !revealed.isEmpty || !covered.isEmpty { onHidingChange?(revealed, covered) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, laidOutSize != bounds.size else { return }
        laidOutSize = bounds.size
        metrics = MushafPageMetrics(size: bounds.size, widestLine: content.widestLine, referenceWidth: content.referenceWidth)
        placeLines()
        setNeedsDisplay()
        onRebuild?()
    }

    // MARK: Layout

    /// Builds each line in its colors and places it in its slot.
    private func placeLines() {
        guard let metrics else { placed = []; return }
        let body = CTFontCreateWithName(QuranScript.postScriptName as CFString, metrics.fontSize, nil)
        placed = lines.enumerated().map { index, composed in
            let slot = metrics.slot(index, of: lines.count)
            let band = slot.insetBy(dx: 0, dy: slot.height * (1 - Style.bandHeight) / 2)
            switch composed.kind {
            case .surahHeader:
                let font = CTFontCreateCopyWithAttributes(body, metrics.fontSize * MushafPageMetrics.Tuning.headerScale, nil, nil)
                let line = CTLineCreateWithAttributedString(attributed(composed, font: font))
                let frame = slot.insetBy(dx: 0, dy: slot.height * Style.frameInset)
                let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                let origin = MushafPageMetrics.centeredOrigin(glyphBounds: glyphs, in: frame)
                return PlacedLine(composed: composed, line: line, origin: origin, band: band, frame: frame)
            case .basmala, .text(justified: false):
                let line = CTLineCreateWithAttributedString(attributed(composed, font: body))
                let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                return PlacedLine(composed: composed, line: line, origin: origin(in: slot, x: slot.midX - width / 2, font: body), band: band)
            case .text(justified: true):
                let natural = (composed.naturalWidth ?? 0) * metrics.fontSize / MushafLayout.measuringSize
                let spaces = composed.spaceOffsets
                let fit = metrics.fitting(naturalWidth: natural, spaceWidth: spaceWidth(body), spaceCount: spaces.count)
                let font = fit.fontScale < 1 ? CTFontCreateCopyWithAttributes(body, metrics.fontSize * fit.fontScale, nil, nil) : body
                let string = attributed(composed, font: font)
                if fit.spaceKern < 0 {
                    for offset in spaces {
                        string.addAttribute(NSAttributedString.Key(kCTKernAttributeName as String), value: fit.spaceKern, range: NSRange(location: offset, length: 1))
                    }
                }
                let unjustified = CTLineCreateWithAttributedString(string)
                let line = CTLineCreateJustifiedLine(unjustified, 1, Double(slot.width)) ?? unjustified
                return PlacedLine(composed: composed, line: line, origin: origin(in: slot, x: slot.minX, font: body), band: band)
            }
        }
    }

    /// Text centered in its slot by the font's ascent and descent.
    private func origin(in slot: CGRect, x: CGFloat, font: CTFont) -> CGPoint {
        CGPoint(x: x, y: slot.midY + (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2)
    }

    private func spaceWidth(_ font: CTFont) -> CGFloat {
        let space = CTLineCreateWithAttributedString(NSAttributedString(string: " ", attributes: [.init(kCTFontAttributeName as String): font]))
        return CTLineGetTypographicBounds(space, nil, nil, nil)
    }

    /// The line's text in its colors: dimmed outside the piece, words undrawn while hidden.
    private func attributed(_ composed: MushafComposedLine, font: CTFont) -> NSMutableAttributedString {
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let body = resolved(MushafPalette.body)
        let string = NSMutableAttributedString(string: composed.text, attributes: [fontKey: font, colorKey: body.cgColor])
        for (ayah, range) in composed.bodyRanges {
            let color: UIColor = highlight.hiddenAyahs.contains(ayah) ? .clear
                : highlight.dimmedAyahs.contains(ayah) ? body.withAlphaComponent(MushafPalette.dimmedAlpha) : body
            string.addAttribute(colorKey, value: color.cgColor, range: range)
        }
        let number = resolved(MushafPalette.number)
        for (ayah, range) in composed.numberRanges {
            let color = highlight.dimmedAyahs.contains(ayah) ? number.withAlphaComponent(MushafPalette.dimmedAlpha) : number
            string.addAttribute(colorKey, value: color.cgColor, range: range)
        }
        return string
    }

    private func resolved(_ color: UIColor) -> UIColor { color.resolvedColor(with: traitCollection) }

    // MARK: Geometry

    func bodyRects(for globalAyah: Int) -> [CGRect] {
        placed.compactMap { placedLine in
            placedLine.composed.bodyRanges[globalAyah].flatMap { span(of: $0, in: placedLine) }
        }
    }

    /// The ayah's words and number, one rect per line.
    private func ayahRects(for globalAyah: Int) -> [CGRect] {
        placed.compactMap { placedLine in
            placedLine.composed.range(of: globalAyah).flatMap { span(of: $0, in: placedLine) }
        }
    }

    /// Where a range of the line's characters is drawn, from its glyphs, so it's right however the
    /// line was justified or ran right to left.
    private func span(of range: NSRange, in placedLine: PlacedLine) -> CGRect? {
        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        for run in CTLineGetGlyphRuns(placedLine.line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var indices = [CFIndex](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            CTRunGetAdvances(run, CFRange(location: 0, length: count), &advances)
            for glyph in 0..<count where NSLocationInRange(indices[glyph], range) {
                minX = min(minX, positions[glyph].x)
                maxX = max(maxX, positions[glyph].x + advances[glyph].width)
            }
        }
        guard minX < maxX else { return nil }
        let band = placedLine.band
        return CGRect(x: placedLine.origin.x + minX, y: band.minY, width: maxX - minX, height: band.height)
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        drawHighlights(in: context)
        drawFrames(in: context)

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        for placedLine in placed {
            context.textPosition = CGPoint(x: placedLine.origin.x, y: bounds.height - placedLine.origin.y)
            CTLineDraw(placedLine.line, context)
        }
        context.restoreGState()

        drawSlipMarks(in: context)
        drawPageNumber()
    }

    private func drawHighlights(in context: CGContext) {
        var fills: [(Int, UIColor)] = highlight.collectedAyahs.map { ($0, MushafPalette.collected) }
        if let ayah = highlight.highlightedAyah { fills.append((ayah, MushafPalette.highlight)) }
        for (ayah, color) in fills {
            context.setFillColor(resolved(color).cgColor)
            for line in ayahRects(for: ayah) {
                context.addPath(UIBezierPath(roundedRect: line, cornerRadius: Style.highlightCornerRadius).cgPath)
            }
            context.fillPath()
        }
    }

    private func drawFrames(in context: CGContext) {
        context.setStrokeColor(resolved(MushafPalette.frame).cgColor)
        context.setLineWidth(Style.frameLineWidth)
        for frame in placed.compactMap(\.frame) {
            let inset = frame.insetBy(dx: Style.frameLineWidth / 2, dy: Style.frameLineWidth / 2)
            context.addPath(UIBezierPath(roundedRect: inset, cornerRadius: Style.frameCornerRadius).cgPath)
        }
        context.strokePath()
    }

    private func drawSlipMarks(in context: CGContext) {
        guard !highlight.markedAyahs.isEmpty else { return }
        context.setStrokeColor(resolved(MushafPalette.marked).cgColor)
        context.setLineWidth(Style.underlineWidth)
        for ayah in highlight.markedAyahs {
            for line in bodyRects(for: ayah) {
                context.move(to: CGPoint(x: line.minX, y: line.maxY))
                context.addLine(to: CGPoint(x: line.maxX, y: line.maxY))
            }
        }
        context.strokePath()
    }

    private func drawPageNumber() {
        guard let footer = metrics?.footerFrame, content.page > 0 else { return }
        let text = NSAttributedString(string: QuranScript.arabicIndic(content.page), attributes: [
            .font: Style.footerFont,
            .foregroundColor: resolved(MushafPalette.number)
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: footer.midX - size.width / 2, y: footer.midY - size.height / 2))
    }

    // MARK: Touch

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard selectionEnabled, let ayah = ayah(at: recognizer.location(in: self)) else { return }
        onSelect?(ayah)
    }

    private func ayah(at point: CGPoint) -> Int? {
        guard let placedLine = placed.first(where: { $0.band.insetBy(dx: 0, dy: -$0.band.height * 0.15).contains(point) }),
              case .text = placedLine.composed.kind
        else { return nil }
        let index = CTLineGetStringIndexForPosition(placedLine.line, CGPoint(x: point.x - placedLine.origin.x, y: 0))
        guard index != kCFNotFound else { return nil }
        return placedLine.composed.ayah(at: index) ?? placedLine.composed.ayah(at: index - 1)
    }

    // MARK: Accessibility

    override var accessibilityLabel: String? {
        get { String(localized: "Page \(content.page)") }
        set { super.accessibilityLabel = newValue }
    }

    /// The page read in an Arabic voice, saying a hidden ayah is hidden instead of reading it.
    override var accessibilityAttributedValue: NSAttributedString? {
        get {
            let spokenLines = lines.filter { $0.kind != .surahHeader }.map { line -> String in
                let spoken = NSMutableString(string: line.text)
                let hidden = line.bodyRanges.filter { highlight.hiddenAyahs.contains($0.key) }.values.sorted { $0.location > $1.location }
                for range in hidden { spoken.replaceCharacters(in: range, with: String(localized: "Arabic hidden for recall")) }
                return spoken as String
            }
            return NSAttributedString(string: spokenLines.joined(separator: "\n"), attributes: [.accessibilitySpeechLanguage: QuranScript.speechLanguage])
        }
        set { super.accessibilityAttributedValue = newValue }
    }
}
