import CoreGraphics
import Foundation
import Testing
@testable import Simple_Quran

struct MushafPageMetricsTests {
    private typealias Tuning = MushafPageMetrics.Tuning
    private let size = CGSize(width: 400, height: 800)
    private var fullWidth: CGFloat { size.width - Tuning.gutter * 2 }

    @Test func pageAsWideAsTheReferenceFillsTheWidth() {
        let metrics = MushafPageMetrics(size: size, widestLine: 2000, referenceWidth: 2000)
        #expect(abs(metrics.fontSize - fullWidth * 100 / 2000) < 0.001)
        #expect(metrics.textFrame.width == fullWidth)
    }

    @Test func pageWithShortLinesGrowsOnlyUpToTheCap() {
        let base = fullWidth * 100 / 2000
        let metrics = MushafPageMetrics(size: size, widestLine: 1000, referenceWidth: 2000)
        #expect(abs(metrics.fontSize - base * Tuning.maxPageGrowth) < 0.001)
        #expect(metrics.textFrame.width == fullWidth)
    }

    @Test func linesWiderThanTheReferenceDontShrinkThePage() {
        let wide = MushafPageMetrics(size: size, widestLine: 2400, referenceWidth: 2000)
        let reference = MushafPageMetrics(size: size, widestLine: 2000, referenceWidth: 2000)
        #expect(wide.fontSize == reference.fontSize)
    }

    @Test func shortSpaceShrinksThePageKeepingItsShape() {
        let short = CGSize(width: 400, height: 400)
        let metrics = MushafPageMetrics(size: short, widestLine: 2000, referenceWidth: 2000)
        let heightSize = (short.height - Tuning.footerHeight) / (15 * Tuning.minLineHeight)
        #expect(abs(metrics.fontSize - heightSize) < 0.001)
        #expect(abs(metrics.textFrame.width - fullWidth * heightSize / (fullWidth * 100 / 2000)) < 0.001)
        #expect(metrics.textFrame.height <= short.height - Tuning.footerHeight + 0.001)
    }

    @Test func overWideLinesNarrowTheirSpacesBeforeTheirFont() {
        let metrics = MushafPageMetrics(size: size, widestLine: 2000, referenceWidth: 2000)
        let width = metrics.textFrame.width

        let fits = metrics.fitting(naturalWidth: width - 10, spaceWidth: 10, spaceCount: 4)
        #expect(fits.spaceKern == 0 && fits.fontScale == 1)

        let squeezed = metrics.fitting(naturalWidth: width + 12, spaceWidth: 10, spaceCount: 4)
        #expect(abs(squeezed.spaceKern + 3) < 0.001)
        #expect(squeezed.fontScale == 1)

        let shrunk = metrics.fitting(naturalWidth: width + 30, spaceWidth: 10, spaceCount: 2)
        #expect(abs(shrunk.spaceKern + 10 * Tuning.maxSpaceSqueeze) < 0.001)
        #expect(abs(shrunk.fontScale - width / (width + 20)) < 0.001)
    }

    @Test func pageWithFewerLinesSitsInTheMiddle() {
        let metrics = MushafPageMetrics(size: size, widestLine: 2000, referenceWidth: 2000)
        #expect(abs(metrics.slot(0, of: 8).minY - (metrics.textFrame.minY + 3.5 * metrics.linePitch)) < 0.001)
        #expect(metrics.slot(14, of: 15).maxY <= metrics.textFrame.maxY + 0.001)
    }

    @Test func headerTextIsCenteredInItsFrame() {
        let glyphs = CGRect(x: 2, y: -5, width: 100, height: 30)
        let box = CGRect(x: 0, y: 0, width: 200, height: 50)
        let origin = MushafPageMetrics.centeredOrigin(glyphBounds: glyphs, in: box)
        // Glyphs run from origin.x + minX to origin.x + maxX, and from baseline - maxY down to baseline - minY.
        #expect(origin.x + glyphs.midX == box.midX)
        #expect(((origin.y - glyphs.maxY) + (origin.y - glyphs.minY)) / 2 == box.midY)
    }
}

struct MushafPageComposerTests {
    private static let catalog = try! BundledQuranCatalog.loadFromBundle()
    private static let layout = try! MushafLayout.loadFromBundle()

    @Test func composesTheBundledWordsOfALine() throws {
        let page = try #require(Self.layout.page(3))
        let line = MushafPageComposer.compose(try #require(page.lines.first), catalog: Self.catalog)
        let verse = try #require(Self.catalog.verse(globalAyah: 13))
        #expect(verse.reference == "2:6")
        #expect(line.kind == .text(justified: true))
        #expect(verse.text.hasPrefix(line.text))
        #expect(line.bodyRanges[13] == NSRange(location: 0, length: (line.text as NSString).length))
        #expect(line.numberRanges.isEmpty)
        #expect(line.ayah(at: 0) == 13)
    }

    @Test func numbersFollowTheirAyahWithANoBreakSpace() throws {
        let page = try #require(Self.layout.page(1))
        let line = MushafPageComposer.compose(page.lines[1], catalog: Self.catalog)
        let number = try #require(line.numberRanges[1])
        #expect((line.text as NSString).substring(with: number) == QuranScript.ayahNumber(1))
        #expect(line.ayah(at: number.location) == 1)
    }

    @Test func aNumberStartingALineHasNoLeadingSpace() throws {
        let line = try #require(Self.layout.pages.lazy.flatMap(\.lines).first { $0.segments.first.map { $0.words.isEmpty && $0.endsAyah } == true })
        let composed = MushafPageComposer.compose(line, catalog: Self.catalog)
        #expect(!composed.text.hasPrefix("\u{00A0}"))
        #expect(composed.numberRanges.values.contains { $0.location == 0 })
    }

    @Test func headersAndBasmalaUseTheBundledText() throws {
        let page = try #require(Self.layout.page(2))
        let lines = MushafPageComposer.compose(page, catalog: Self.catalog)
        #expect(lines[0] == MushafComposedLine(kind: .surahHeader, text: try #require(Self.catalog.surah(number: 2)).arabicName))
        #expect(lines[1] == MushafComposedLine(kind: .basmala, text: Self.catalog.basmala))
    }

    /// Each ayah's words, read across every line they fall on, give back its bundled text exactly.
    @Test func everyAyahIsRebuiltFromItsLines() throws {
        var pieces: [Int: [String]] = [:]
        for line in Self.layout.pages.flatMap(\.lines) {
            let composed = MushafPageComposer.compose(line, catalog: Self.catalog)
            let text = composed.text as NSString
            for (ayah, range) in composed.bodyRanges.sorted(by: { $0.value.location < $1.value.location }) {
                pieces[ayah, default: []].append(text.substring(with: range))
            }
        }
        #expect(pieces.count == QuranCatalogMetrics.ayahCount)
        for verse in Self.catalog.verses {
            #expect(pieces[verse.globalAyah]?.joined(separator: " ") == verse.text, "\(verse.reference)")
        }
    }

    @Test func wordRangesAreFoundInUTF16() {
        let text = "ab cd\u{00A0}ef gh"
        #expect(MushafPageComposer.utf16Range(ofWords: 0..<1, in: text) == NSRange(location: 0, length: 2))
        #expect(MushafPageComposer.utf16Range(ofWords: 1..<3, in: text) == NSRange(location: 3, length: 8))
        #expect(MushafPageComposer.utf16Range(ofWords: 2..<9, in: text) == NSRange(location: 9, length: 2))
        #expect(MushafPageComposer.utf16Range(ofWords: 1..<1, in: text) == nil)
        #expect(MushafPageComposer.utf16Range(ofWords: 5..<6, in: text) == nil)
    }
}

@MainActor
struct MushafPageLibraryTests {
    private static let catalog = try! BundledQuranCatalog.loadFromBundle()
    private static let layout = try! MushafLayout.loadFromBundle()

    @Test func composesEachPageOnceAsTheComposerWould() throws {
        let library = MushafPageLibrary(layout: Self.layout, catalog: Self.catalog)
        let pages = try [1, 2, 3, 255, 446, 604].map { try #require(Self.layout.page($0)) }
        for page in pages {
            #expect(library.lines(for: page) == MushafPageComposer.compose(page, catalog: Self.catalog))
        }
        for page in pages { _ = library.lines(for: page) }
        #expect(library.composedCount == pages.count)
    }

    @Test func referenceWidthIsTheTunedPercentile() {
        let library = MushafPageLibrary(layout: Self.layout, catalog: Self.catalog)
        #expect(library.referenceWidth == Self.layout.justifiedWidth(atPercentile: MushafPageMetrics.Tuning.referencePercentile))
    }
}

@MainActor
struct MushafHighlightTests {
    @Test func onlyHiddenAndDimmedAyahsRecolorTheText() {
        let base = MushafHighlightState(highlightedAyah: 1, dimmedAyahs: [2], markedAyahs: [3], hiddenAyahs: [4])
        var moved = base
        moved.highlightedAyah = 5
        moved.collectedAyahs = [6]
        moved.markedAyahs = [7]
        #expect(!moved.changesTextColors(from: base))

        var hidden = base
        hidden.hiddenAyahs = []
        #expect(hidden.changesTextColors(from: base))

        var dimmed = base
        dimmed.dimmedAyahs = [2, 8]
        #expect(dimmed.changesTextColors(from: base))
    }
}

struct MushafPageSettlingTests {
    private static let catalog = try! BundledQuranCatalog.loadFromBundle()

    /// The end of Al-Adiyat, all of Al-Qari'a, and the start of At-Takathur, as one page might hold them.
    private var sharedPage: (ayahs: [Int], adiyatTail: Int, takathurStart: Int) {
        let adiyat = Self.catalog.surah(number: 100)!
        let qaria = Self.catalog.surah(number: 101)!
        let takathur = Self.catalog.surah(number: 102)!
        let ayahs = Array((adiyat.endGlobalAyah - 2)...qaria.endGlobalAyah) + [takathur.startGlobalAyah, takathur.startGlobalAyah + 1]
        return (ayahs, adiyat.endGlobalAyah - 2, takathur.startGlobalAyah)
    }

    @Test func staysWhileThePageShowsTheSurah() {
        let page = sharedPage
        #expect(QuranDestination.surah(number: 101).settling(onPage: 600, holding: page.ayahs, toward: .next, in: Self.catalog) == nil)
        #expect(QuranDestination.surah(number: 100).settling(onPage: 600, holding: page.ayahs, toward: .next, in: Self.catalog) == nil)
    }

    @Test func goingForwardOpensTheFirstSurahOnThePage() {
        let page = sharedPage
        let next = QuranDestination.surah(number: 99).settling(onPage: 600, holding: page.ayahs, toward: .next, in: Self.catalog)
        #expect(next == .surah(number: 100, scrollToAyah: page.adiyatTail))
    }

    @Test func goingBackOpensTheLastSurahOnThePage() {
        let page = sharedPage
        let previous = QuranDestination.surah(number: 103).settling(onPage: 600, holding: page.ayahs, toward: .previous, in: Self.catalog)
        #expect(previous == .surah(number: 102, scrollToAyah: page.takathurStart))
    }

    @Test func juzAndPageKeepTheirKind() {
        let page = sharedPage
        #expect(QuranDestination.juz(29).settling(onPage: 600, holding: page.ayahs, toward: .next, in: Self.catalog) == .juz(30))
        #expect(QuranDestination.juz(30).settling(onPage: 600, holding: page.ayahs, toward: .next, in: Self.catalog) == nil)
        #expect(QuranDestination.page(599).settling(onPage: 600, holding: page.ayahs, toward: .next, in: Self.catalog) == .page(600))
        #expect(QuranDestination.page(600).settling(onPage: 600, holding: page.ayahs, toward: .next, in: Self.catalog) == nil)
    }
}
