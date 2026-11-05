import CoreGraphics

/// The 15-line layout with each page's text composed once, the first time the page is shown.
/// The pager reads a page's lines on every update while it turns, so this keeps that a lookup.
final class MushafPageLibrary {
    let layout: MushafLayout
    /// The line width every page is sized against, so the type size barely changes from page to page.
    let referenceWidth: CGFloat
    /// How many pages have been composed, for tests.
    private(set) var composedCount = 0

    private let catalog: BundledQuranCatalog
    private var composed: [Int: [MushafComposedLine]] = [:]

    init(layout: MushafLayout, catalog: BundledQuranCatalog) {
        self.layout = layout
        self.catalog = catalog
        referenceWidth = layout.justifiedWidth(atPercentile: MushafPageMetrics.Tuning.referencePercentile)
    }

    func lines(for page: MushafPage) -> [MushafComposedLine] {
        if let lines = composed[page.number] { return lines }
        let lines = MushafPageComposer.compose(page, catalog: catalog)
        composed[page.number] = lines
        composedCount += 1
        return lines
    }
}
