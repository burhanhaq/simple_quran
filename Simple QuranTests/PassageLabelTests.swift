import Foundation
import Testing
@testable import Simple_Quran

struct PassageLabelTests {
    @Test func labelsFullSurahSingleAyahRangeJuzAndCollections() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let fatihaName = try #require(catalog.surah(number: 1)).englishName
        let baqaraName = try #require(catalog.surah(number: 2)).englishName

        let fatiha = try catalog.range(surah: 1, startAyah: 1, endAyah: 7)
        #expect(PassageLabel.passage(fatiha, catalog: catalog) == fatihaName)

        let kursi = try catalog.range(surah: 2, startAyah: 255, endAyah: 255)
        #expect(PassageLabel.passage(kursi, catalog: catalog) == "\(baqaraName) 255")

        let kahfOpening = try catalog.range(surah: 18, startAyah: 1, endAyah: 10)
        let kahfName = try #require(catalog.surah(number: 18)).englishName
        #expect(PassageLabel.passage(kahfOpening, catalog: catalog) == "\(kahfName) 1–10")

        let amma = try catalog.versesForJuz(30)
        #expect(PassageLabel.passage(amma, catalog: catalog) == "Juz 30 · Amma")

        let baqaraOpening = try catalog.range(surah: 2, startAyah: 1, endAyah: 7)
        #expect(PassageLabel.collection([baqaraOpening, kursi], catalog: catalog) == "\(baqaraName) 1–7, 255")
        #expect(PassageLabel.collection([fatiha, kursi], catalog: catalog) == "\(fatihaName), \(baqaraName) 255")
    }
}

struct SetDraftTitleTests {
    @Test @MainActor func generatedTitleTracksPassagesUntilTheUserEdits() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let fatihaName = try #require(catalog.surah(number: 1)).englishName
        let baqaraName = try #require(catalog.surah(number: 2)).englishName
        let fatiha = try catalog.range(surah: 1, startAyah: 1, endAyah: 7)
        let kursi = try catalog.range(surah: 2, startAyah: 255, endAyah: 255)

        let draft = SetDraft()
        draft.append(fatiha)
        #expect(draft.displayTitle(catalog: catalog) == fatihaName)
        #expect(draft.hasCustomTitle == false)

        draft.append(kursi)
        #expect(draft.displayTitle(catalog: catalog) == "\(fatihaName), \(baqaraName) 255")

        draft.setTitle("Morning review", catalog: catalog)
        #expect(draft.hasCustomTitle)
        draft.append(try catalog.range(surah: 112, startAyah: 1, endAyah: 4))
        #expect(draft.displayTitle(catalog: catalog) == "Morning review")
        #expect(draft.resolvedTitle(catalog: catalog) == "Morning review")

        draft.setTitle("", catalog: catalog)
        #expect(draft.hasCustomTitle == false)
        #expect(draft.displayTitle(catalog: catalog) == PassageLabel.collection(draft.passages.map(\.range), catalog: catalog))
    }
}
