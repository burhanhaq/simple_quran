import Foundation
import Testing
@testable import Simple_Quran

struct QuranPiecesTests {
    @Test func everySizeCoversEachSurahInOrderWithoutCrossingIt() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        for size in PieceSize.allCases {
            for surah in catalog.surahs {
                var cursor = surah.startGlobalAyah
                while cursor <= surah.endGlobalAyah {
                    let piece = try #require(catalog.piece(containing: cursor, size: size))
                    #expect(piece.startGlobalAyah == cursor, "\(size) piece in surah \(surah.number) starts at \(piece.startGlobalAyah), not \(cursor)")
                    #expect(piece.endGlobalAyah <= surah.endGlobalAyah)
                    for ayah in piece.globalAyahs { #expect(catalog.piece(containing: ayah, size: size) == piece) }
                    cursor = piece.endGlobalAyah + 1
                }
                #expect(cursor == surah.endGlobalAyah + 1)
            }
        }
    }

    @Test func shortSurahsStayWholeAndLongAyahsStandAlone() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        for number in [1, 103, 108, 110, 112, 113, 114] {
            let surah = try #require(catalog.surah(number: number))
            #expect(catalog.piece(containing: surah.startGlobalAyah, size: .halfPage) == surah.range, "surah \(number)")
        }
        let debt = try catalog.range(surah: 2, startAyah: 282, endAyah: 282)
        for size in PieceSize.allCases {
            #expect(catalog.piece(containing: debt.startGlobalAyah, size: size) == debt)
        }
    }

    @Test func fullPagesMatchTheMushafPage() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        // Pages 3 to 48 hold nothing but Al-Baqarah.
        for page in catalog.pages where (3...48).contains(page.number) {
            let range = VerseRange.clamped(start: page.startGlobalAyah, end: page.endGlobalAyah)
            #expect(catalog.piece(containing: page.startGlobalAyah, size: .fullPage) == range, "page \(page.number)")
        }
    }

    @Test func halfPagesSplitLongSurahsAboutTwicePerPage() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let baqarah = try #require(catalog.surah(number: 2))
        func pieces(_ size: PieceSize) throws -> [VerseRange] {
            var result: [VerseRange] = []
            var cursor = baqarah.startGlobalAyah
            while cursor <= baqarah.endGlobalAyah {
                let piece = try #require(catalog.piece(containing: cursor, size: size))
                result.append(piece)
                cursor = piece.endGlobalAyah + 1
            }
            return result
        }
        let pageCount = Set(catalog.verses(in: baqarah.range).map(\.page)).count
        let halves = try pieces(.halfPage)
        #expect(Double(halves.count) >= Double(pageCount) * 1.5)
        #expect(Double(halves.count) <= Double(pageCount) * 2.2)
        let onOnePage = halves.filter { piece in
            catalog.verse(globalAyah: piece.startGlobalAyah)?.page == catalog.verse(globalAyah: piece.endGlobalAyah)?.page
        }
        #expect(Double(onOnePage.count) >= Double(halves.count) * 0.9)
        #expect(try pieces(.quarterPage).count > halves.count)
        #expect(halves.count > (try pieces(.fullPage)).count)
    }

    @Test func startingPartwayRunsToThePieceEndAndAvoidsSlivers() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let mulk = try #require(catalog.surah(number: 67))
        let first = try #require(catalog.piece(containing: mulk.startGlobalAyah, size: .halfPage))
        #expect(first.count > 2)
        #expect(LearningPassage.piece(from: first.startGlobalAyah, size: .halfPage, catalog: catalog) == first)

        let second = try #require(catalog.piece(containing: first.endGlobalAyah + 1, size: .halfPage))
        let nearEnd = first.endGlobalAyah
        #expect(LearningPassage.piece(from: nearEnd, size: .halfPage, catalog: catalog) == .clamped(start: nearEnd, end: second.endGlobalAyah))
        let early = first.startGlobalAyah + 1
        #expect(LearningPassage.piece(from: early, size: .halfPage, catalog: catalog) == .clamped(start: early, end: first.endGlobalAyah))

        // The last ayah of a surah never runs into the next one.
        let lastPiece = try #require(LearningPassage.piece(from: mulk.endGlobalAyah, size: .halfPage, catalog: catalog))
        #expect(lastPiece == .clamped(start: mulk.endGlobalAyah, end: mulk.endGlobalAyah))
    }
}
