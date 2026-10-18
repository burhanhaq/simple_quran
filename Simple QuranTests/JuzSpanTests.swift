import Testing
@testable import Simple_Quran

struct JuzSpanTests {
    @Test func surahInsideOneJuzStartsItOnlyAtTheJuzStart() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let fatihah = try #require(catalog.surah(number: 1))
        let naba = try #require(catalog.surah(number: 78))
        let nas = try #require(catalog.surah(number: 114))

        #expect(JuzSpan.spans(of: fatihah.range, in: catalog.juzs) == [JuzSpan(juz: 1, fraction: 1, startsHere: true)])
        #expect(JuzSpan.spans(of: naba.range, in: catalog.juzs) == [JuzSpan(juz: 30, fraction: 1, startsHere: true)])
        #expect(JuzSpan.spans(of: nas.range, in: catalog.juzs) == [JuzSpan(juz: 30, fraction: 1, startsHere: false)])
    }

    @Test func surahAcrossJuzSplitsByAyahShare() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let baqarah = try #require(catalog.surah(number: 2))
        let spans = JuzSpan.spans(of: baqarah.range, in: catalog.juzs)

        // Juz 2 begins at 2:142 and juz 3 at 2:253.
        #expect(spans.map(\.juz) == [1, 2, 3])
        #expect(spans.map(\.startsHere) == [false, true, true])
        #expect(spans[0].fraction == 141.0 / 286)
        #expect(spans[1].fraction == 111.0 / 286)
        #expect(spans[2].fraction == 34.0 / 286)
    }
}
