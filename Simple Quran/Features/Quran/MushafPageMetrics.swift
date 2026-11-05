import CoreGraphics

/// How big a mushaf page's text is and where its lines sit, for a given space.
///
/// The bundled font is narrower than the fonts the printed layout was made for, so lines come up
/// short and justifying them opens wide gaps between words. Two things close them: each page is
/// sized to its own widest line (capped, so the size barely shifts as pages turn), and the size
/// ignores the widest 1% of lines, which instead narrow their spaces or, failing that, their font.
nonisolated struct MushafPageMetrics: Equatable, Sendable {
    enum Tuning {
        /// Lines wider than this share of all justified lines are squeezed rather than shrink every page.
        static let referencePercentile = 0.99
        /// How much bigger than the reference size a page with short lines may get.
        static let maxPageGrowth: CGFloat = 1.12
        /// How much of a space's width an over-wide line may give up.
        static let maxSpaceSqueeze: CGFloat = 0.5
        /// Line pitch as a multiple of the font size: at least room for stacked marks, at most airy.
        static let minLineHeight: CGFloat = 1.75
        static let maxLineHeight: CGFloat = 2.2
        static let gutter: CGFloat = 16
        static let footerHeight: CGFloat = 24
        /// The surah name sits a little smaller than the text in its frame.
        static let headerScale: CGFloat = 0.9
    }

    /// The body font size.
    var fontSize: CGFloat
    var linePitch: CGFloat
    /// Where the 15 line slots sit; justified lines fill its width.
    var textFrame: CGRect
    /// Where the page number sits.
    var footerFrame: CGRect

    /// - Parameters:
    ///   - widestLine: the page's widest justified line at `MushafLayout.measuringSize`.
    ///   - referenceWidth: the line width at `Tuning.referencePercentile` across the whole layout.
    init(size: CGSize, widestLine: CGFloat, referenceWidth: CGFloat) {
        let fullWidth = max(size.width - Tuning.gutter * 2, 1)
        let available = max(size.height - Tuning.footerHeight, 1)
        let lines = CGFloat(MushafLayout.linesPerPage)
        let reference = max(referenceWidth, 1)
        let base = fullWidth * MushafLayout.measuringSize / reference
        let pageWidest = widestLine > 0 ? min(widestLine, reference) : reference

        let widthSize = min(fullWidth * MushafLayout.measuringSize / pageWidest, base * Tuning.maxPageGrowth)
        let heightSize = available / (lines * Tuning.minLineHeight)
        fontSize = min(widthSize, heightSize)
        // A short screen shrinks the whole page, keeping its shape, rather than widen the gaps.
        let width = heightSize < widthSize ? fullWidth * heightSize / widthSize : fullWidth
        linePitch = min(available / lines, fontSize * Tuning.maxLineHeight)

        let height = linePitch * lines
        let top = max((available - height) / 2, 0)
        textFrame = CGRect(x: (size.width - width) / 2, y: top, width: width, height: height)
        footerFrame = CGRect(x: 0, y: textFrame.maxY, width: size.width, height: Tuning.footerHeight)
    }

    /// The slot a line sits in. A page with fewer lines, like the first two, sits in the middle.
    func slot(_ index: Int, of count: Int) -> CGRect {
        let offset = CGFloat(max(MushafLayout.linesPerPage - count, 0)) / 2
        return CGRect(
            x: textFrame.minX,
            y: textFrame.minY + (CGFloat(index) + offset) * linePitch,
            width: textFrame.width,
            height: linePitch
        )
    }

    /// How an over-wide line fits: first by narrowing its spaces, then by shrinking its font.
    /// - Returns: the kern to add to each space (zero or negative) and the font scale for the line.
    func fitting(naturalWidth: CGFloat, spaceWidth: CGFloat, spaceCount: Int) -> (spaceKern: CGFloat, fontScale: CGFloat) {
        let excess = naturalWidth - textFrame.width
        guard excess > 0 else { return (0, 1) }
        let perSpace = spaceCount > 0 ? min(excess / CGFloat(spaceCount), spaceWidth * Tuning.maxSpaceSqueeze) : 0
        let squeezed = naturalWidth - perSpace * CGFloat(spaceCount)
        let scale = squeezed > textFrame.width ? textFrame.width / squeezed : 1
        return (-perSpace, scale)
    }

    /// Where a header's text starts so its glyphs sit in the middle of its frame both ways.
    /// - Parameter glyphBounds: the text's glyph bounds relative to its origin, y up from the baseline.
    /// - Returns: the text origin, with y the baseline in y-down coordinates.
    static func centeredOrigin(glyphBounds: CGRect, in box: CGRect) -> CGPoint {
        CGPoint(x: box.midX - glyphBounds.midX, y: box.midY + glyphBounds.midY)
    }
}
