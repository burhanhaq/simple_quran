import Testing
@testable import Simple_Quran

struct ProgressMapTests {
    @Test func juzHoldsTheSurahsItTouchesClippedToItsAyahs() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let baqarah = try #require(catalog.surah(number: 2))

        let first = ProgressMap.surahs(in: catalog.juzs[0], from: catalog.surahs)
        #expect(first.map(\.surah.number) == [1, 2])
        #expect(first.map(\.startsHere) == [true, true])
        // Juz 2 begins at 2:142.
        #expect(first[1].range == .clamped(start: baqarah.startGlobalAyah, end: baqarah.startGlobalAyah + 140))

        let second = ProgressMap.surahs(in: catalog.juzs[1], from: catalog.surahs)
        #expect(second.map(\.surah.number) == [2])
        #expect(second[0].startsHere == false)

        let amma = ProgressMap.surahs(in: catalog.juzs[29], from: catalog.surahs)
        #expect(amma.map(\.surah.number) == Array(78...114))
        #expect(amma.allSatisfy { $0.startsHere })
    }

    @Test func nothingFoldsBeforeAnythingIsStarted() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let rows = ProgressMap.rows(catalog.juzs, order: .fromAnNas, revealed: []) { _ in false }
        #expect(rows == catalog.juzs.reversed().map { .juz($0) })
    }

    @Test func juzNotStartedFoldIntoRunsInTheChosenOrder() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let started: Set = [1, 29, 30]
        let juz = { (number: Int) in ProgressMapRow.juz(catalog.juzs[number - 1]) }

        let fromAnNas = ProgressMap.rows(catalog.juzs, order: .fromAnNas, revealed: []) { started.contains($0.number) }
        #expect(fromAnNas == [juz(30), juz(29), .unstarted(2...28), juz(1)])

        let fromAlFatiha = ProgressMap.rows(catalog.juzs, order: .fromAlFatiha, revealed: []) { started.contains($0.number) }
        #expect(fromAlFatiha == [juz(1), .unstarted(2...28), juz(29), juz(30)])
    }

    @Test func revealedJuzSplitTheirRun() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let juz = { (number: Int) in ProgressMapRow.juz(catalog.juzs[number - 1]) }
        let rows = ProgressMap.rows(catalog.juzs, order: .fromAlFatiha, revealed: [10]) { $0.number == 1 || $0.number == 30 }
        #expect(rows == [juz(1), .unstarted(2...9), juz(10), .unstarted(11...29), juz(30)])
    }
}
