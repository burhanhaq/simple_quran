import CoreText
import Foundation
import Testing
@testable import Simple_Quran

struct MushafLayoutTests {
    private static let catalog = try! BundledQuranCatalog.loadFromBundle()
    private static let layout = try! MushafLayout.loadFromBundle()

    @Test func hasEveryPageWithAtMostFifteenLines() {
        #expect(Self.layout.edition == "1405H")
        #expect(Self.layout.pages.count == MushafLayout.pageCount)
        #expect(Self.layout.pages.allSatisfy { $0.lines.count <= MushafLayout.linesPerPage })
    }

    @Test func openingPagesAreCenteredEightLines() throws {
        for number in 1...2 {
            let page = try #require(Self.layout.page(number))
            #expect(page.lines.count == 8)
            #expect(page.lines.filter(\.isJustified).isEmpty)
        }
    }

    @Test func everyWordAndNumberAppearsOnceInOrder() throws {
        var expectedAyah = 1
        var expectedWord = 0
        var numbers = 0
        for line in Self.layout.pages.flatMap(\.lines) {
            for segment in line.segments {
                if segment.globalAyah != expectedAyah {
                    #expect(segment.globalAyah == expectedAyah + 1)
                    expectedAyah = segment.globalAyah
                    expectedWord = 0
                }
                #expect(segment.words.lowerBound == expectedWord)
                expectedWord = segment.words.upperBound
                if segment.endsAyah {
                    let verse = try #require(Self.catalog.verse(globalAyah: segment.globalAyah))
                    #expect(expectedWord == verse.text.split(separator: " ", omittingEmptySubsequences: false).count)
                    numbers += 1
                }
            }
        }
        #expect(expectedAyah == QuranCatalogMetrics.ayahCount)
        #expect(numbers == QuranCatalogMetrics.ayahCount)
    }

    @Test func ayahsStartOnTheirBundledPage() {
        let mismatches = Self.catalog.verses.filter { Self.layout.page(containing: $0.globalAyah) != $0.page }
        #expect(mismatches.isEmpty)
    }

    @Test func surahHeadersRunInOrder() {
        let headers = Self.layout.pages.flatMap(\.lines).compactMap { line -> Int? in
            if case .surahHeader(let surah) = line.kind { return surah }
            return nil
        }
        #expect(headers == Array(1...114))
    }

    @Test func pagesTouchingARangeIncludeAnAyahRunningOver() throws {
        let baqarah = try #require(Self.catalog.surah(number: 2))
        let pages = Self.layout.pages(touching: baqarah.range)
        #expect(pages.lowerBound == 2)
        #expect(pages.upperBound >= 49)
    }

    @Test func pagesKnowTheirAyahsInReadingOrder() throws {
        for page in Self.layout.pages {
            let segmentAyahs = page.lines.flatMap(\.segments).map(\.globalAyah)
            #expect(page.ayahs == Set(segmentAyahs))
            #expect(page.orderedAyahs == page.orderedAyahs.sorted())
            #expect(page.orderedAyahs.count == page.ayahs.count)
            #expect(page.widestJustifiedWidth == (page.lines.filter(\.isJustified).compactMap(\.naturalWidth).max() ?? 0))
        }
        let first = try #require(Self.layout.page(1))
        #expect(first.orderedAyahs == Array(1...7))
    }

    @Test func pagesInARangeAreClampedToTheMushaf() {
        #expect(Self.layout.pages(in: 1...3).map(\.number) == [1, 2, 3])
        #expect(Self.layout.pages(in: 602...700).map(\.number) == [602, 603, 604])
        #expect(Self.layout.pages(in: -2...0).isEmpty)
        #expect(Self.layout.pages(in: 1...MushafLayout.pageCount).count == MushafLayout.pageCount)
    }

    /// So a page's first ayah is always where reading it begins, never one carried over.
    @Test func everyPageOpensOnANewAyah() throws {
        for page in Self.layout.pages {
            let first = try #require(page.lines.flatMap(\.segments).first)
            #expect(first.words.lowerBound == 0 && !first.words.isEmpty, "page \(page.number)")
        }
    }

    @Test @MainActor func storedWidthsMatchTheBundledFont() throws {
        let font = CTFontCreateWithName(QuranScript.postScriptName as CFString, MushafLayout.measuringSize, nil)
        let page = try #require(Self.layout.page(3))
        let line = try #require(page.lines.first)
        let words = line.segments.flatMap { segment -> [String] in
            let text = Self.catalog.verse(globalAyah: segment.globalAyah)?.text ?? ""
            return Array(text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)[segment.words])
        }
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: words.joined(separator: " "), attributes: attributes))
        let measured = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        #expect(abs(measured - (line.naturalWidth ?? 0)) < 0.5)
    }
}
