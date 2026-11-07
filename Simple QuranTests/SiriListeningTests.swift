import Foundation
import Testing
@testable import Simple_Quran

struct SiriListeningTests {
    private let catalog: BundledQuranCatalog

    init() throws {
        catalog = try BundledQuranCatalog.loadFromBundle()
    }

    private func surah(_ number: Int) throws -> Surah {
        try #require(catalog.surah(number: number))
    }

    // MARK: - Ayah ranges

    @Test func countedAyahsStartAtTheAskedAyah() throws {
        let baqara = try surah(2)
        let range = try SiriListening.ayahs(of: baqara, from: 255, count: 3)
        #expect(range.startGlobalAyah == baqara.startGlobalAyah + 254)
        #expect(range.count == 3)
        #expect(PassageLabel.passage(range, catalog: catalog) == "Al-Baqara 255–257")
    }

    @Test func askingForMoreAyahsThanAreLeftStopsAtTheSurahsEnd() throws {
        let mulk = try surah(67)
        let range = try SiriListening.ayahs(of: mulk, from: 25, count: 10)
        #expect(range.startGlobalAyah == mulk.startGlobalAyah + 24)
        #expect(range.endGlobalAyah == mulk.endGlobalAyah)
    }

    @Test func anAyahPastTheSurahIsRefused() throws {
        let kawthar = try surah(108)
        #expect(throws: SiriListening.Problem.ayahOutOfRange(surah: 108, ayahCount: 3, asked: 4)) {
            try SiriListening.ayahs(of: kawthar, from: 4, count: 1)
        }
        #expect(throws: SiriListening.Problem.ayahOutOfRange(surah: 108, ayahCount: 3, asked: 0)) {
            try SiriListening.globalAyah(of: kawthar, ayah: 0)
        }
    }

    @Test func zeroAyahsIsRefused() throws {
        #expect(throws: SiriListening.Problem.countNotPositive) {
            try SiriListening.ayahs(of: try surah(1), from: 1, count: 0)
        }
    }

    // MARK: - Spoken names

    @Test func surahsAnswerToTheirNameWithoutTheArticle() throws {
        let names = SpokenNames.surah(try surah(67))
        #expect(names.contains("Mulk"))
        #expect(names.contains("Al Mulk"))
        #expect(names.contains("Tabarak"))
        #expect(names.contains("The Sovereignty"))
        #expect(!names.contains("Al-Mulk"), "The catalog name is the title, not a synonym")
    }

    @Test func longVowelsAreAlsoSpelledOnce() throws {
        let names = SpokenNames.surah(try surah(1))
        #expect(names.contains("Fatiha"))
        #expect(names.contains("Al Fatiha"))
        #expect(names.contains("Faatiha"))
    }

    @Test func spokenNamesNeverRepeat() throws {
        for surah in catalog.surahs {
            let names = SpokenNames.surah(surah).map { $0.lowercased() }
            #expect(Set(names).count == names.count, "\(surah.englishName) repeats a spoken name")
        }
    }

    @Test func juzAnswerToNumbersInWordsAndPara() {
        let names = SpokenNames.juz(18)
        #expect(names.contains("Juz eighteen"))
        #expect(names.contains("Para 18"))
        #expect(names.contains("18"))
        #expect(!names.contains("Juz 18"), "The title is not repeated as a synonym")
        #expect(SpokenNames.juz(30).contains { $0.localizedCaseInsensitiveContains("Amma") })
    }
}
