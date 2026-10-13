import Foundation
import Testing
@testable import Simple_Quran

struct LearningTargetTests {
    @Test func juzPracticeCrossesSurahBoundariesAndStopsAtJuzEnd() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        for juz in catalog.juzs {
            let target = LearningTarget(range: .clamped(start: juz.startGlobalAyah, end: juz.endGlobalAyah), juzNumber: juz.number)
            var start = target.range.startGlobalAyah
            var covered: [Int] = []
            while let passage = target.passage(from: start, catalog: catalog) {
                #expect(passage.startGlobalAyah == start)
                #expect(passage.endGlobalAyah <= target.range.endGlobalAyah)
                covered += passage.globalAyahs
                start = passage.endGlobalAyah + 1
            }
            #expect(covered == target.range.globalAyahs)
        }
    }

    @Test func customFocusClipsSuggestionsAndPagesToItsBoundaries() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let target = LearningTarget(range: try catalog.range(surah: 2, startAyah: 4, endAyah: 6))
        for byPage in [false, true] {
            let passage = try #require(target.passage(catalog: catalog, byPage: byPage))
            #expect(passage.startGlobalAyah == target.range.startGlobalAyah)
            #expect(passage.endGlobalAyah <= target.range.endGlobalAyah)
            #expect(target.passage(from: target.range.endGlobalAyah + 1, catalog: catalog, byPage: byPage) == nil)
        }
    }

    @Test @MainActor func targetsPersistIndependentPlacesAndDeduplicateSelections() throws {
        let suite = "FocusTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let first = LearningTarget(range: .clamped(start: 8, end: 293))
        let second = LearningTarget(range: .clamped(start: 1, end: 148), juzNumber: 1)
        settings.addTargets([first, second, first])
        let firstPlace = VerseRange.clamped(start: 25, end: 27)
        let secondPlace = VerseRange.clamped(start: 30, end: 35)
        settings.remember(firstPlace, targetID: first.id)
        settings.remember(secondPlace, targetID: second.id)
        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.learningTargets.count == 2)
        #expect(reopened.learningTargets[0].resumeRange == firstPlace)
        #expect(reopened.learningTargets[1].resumeRange == secondPlace)
        #expect(reopened.activeTargetID == second.id)
        reopened.learningTargets.removeFirst()
        #expect(AppSettings(defaults: defaults).learningTargets == [reopened.learningTargets[0]])
    }

    @Test func existingCustomPassageResumesExactlyAndInvalidResumeIsIgnored() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        var target = LearningTarget(range: .clamped(start: 8, end: 30), resumeRange: .clamped(start: 10, end: 20))
        #expect(target.passage(catalog: catalog) == target.resumeRange)
        target.range = .clamped(start: 8, end: 12)
        let passage = try #require(target.passage(catalog: catalog))
        #expect(passage.endGlobalAyah <= 12)
    }
}
