import Foundation
import Testing
@testable import Simple_Quran

struct PassageSelectionTests {
    @Test func firstTapStartsARangeAndSecondTapCompletesIt() throws {
        var selection = PassageSelection()
        #expect(selection.tap(1) == nil)
        #expect(selection.isSelecting)
        #expect(selection.contains(1))
        #expect(selection.highlights(1, collected: []))
        #expect(selection.highlights(2, collected: []) == false)

        let range = try #require(selection.tap(7))
        #expect(range.startGlobalAyah == 1)
        #expect(range.endGlobalAyah == 7)
        #expect(selection.isSelecting == false)
        #expect(selection.contains(1) == false)
        #expect(selection.highlights(4, collected: [range]))
    }

    @Test func reversedTapsStillProduceAnOrderedRange() throws {
        var selection = PassageSelection()
        #expect(selection.tap(7) == nil)
        let range = try #require(selection.tap(1))
        #expect(range.startGlobalAyah == 1)
        #expect(range.endGlobalAyah == 7)
    }

    @Test func tappingTheStartAyahAgainCollectsASingleAyah() throws {
        var selection = PassageSelection()
        #expect(selection.tap(5) == nil)
        let range = try #require(selection.tap(5))
        #expect(range.startGlobalAyah == 5)
        #expect(range.endGlobalAyah == 5)
        #expect(range.count == 1)
    }

    @Test func resetClearsAnInProgressStart() {
        var selection = PassageSelection()
        #expect(selection.tap(2) == nil)
        selection.reset()
        #expect(selection.isSelecting == false)
        #expect(selection.contains(2) == false)
        #expect(selection.tap(4) == nil)
        #expect(selection.contains(4))
    }
}

struct QuranDestinationTests {
    @Test func surahJuzAndPageOpenAsReadableRanges() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let fatiha = try #require(QuranDestination.surah(number: 1).range(in: catalog))
        #expect(fatiha.count == 7)
        #expect(QuranDestination.surah(number: 1).title(in: catalog) == "Al-Faatiha")

        let amma = try #require(QuranDestination.juz(30).range(in: catalog))
        #expect(amma.endGlobalAyah == 6236)

        let page = try #require(QuranDestination.page(1).range(in: catalog))
        #expect(page.contains(1))
        #expect(QuranDestination.page(1).scrollToAyah == nil)
        #expect(QuranDestination.surah(number: 18, scrollToAyah: 10).scrollToAyah == 10)
    }
}
