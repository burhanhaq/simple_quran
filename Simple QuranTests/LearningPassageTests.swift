import Foundation
import SwiftData
import Testing
@testable import Simple_Quran

struct LearningPassageTests {
    @Test func suggestionsCoverEverySurahWithoutGapsOrCrossingItsEnd() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        for surah in catalog.surahs {
            var start = surah.startGlobalAyah
            var covered: [Int] = []
            while start <= surah.endGlobalAyah {
                let range = try #require(LearningPassage.suggested(from: start, catalog: catalog))
                #expect(range.startGlobalAyah == start)
                #expect(range.endGlobalAyah <= surah.endGlobalAyah)
                #expect(range.count > 0)
                covered += range.globalAyahs
                start = range.endGlobalAyah + 1
            }
            #expect(covered == Array(surah.startGlobalAyah...surah.endGlobalAyah))
        }
    }

    @Test func shortSurahsAndLongAyahsGetAppropriateSuggestions() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let ikhlas = try #require(catalog.surah(number: 112))
        let short = try #require(LearningPassage.suggested(from: ikhlas.startGlobalAyah, catalog: catalog))
        #expect(short.count == 4)
        #expect(LearningPassage.next(after: short, catalog: catalog) == nil)
        let long = try catalog.range(surah: 2, startAyah: 282, endAyah: 282)
        #expect(LearningPassage.suggested(from: long.startGlobalAyah, catalog: catalog) == long)
    }

    @Test func nextPassageUsesAyahBoundariesAndPagePreference() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let range = try catalog.range(surah: 67, startAyah: 1, endAyah: 3)
        let next = try #require(LearningPassage.next(after: range, catalog: catalog))
        #expect(next.startGlobalAyah == range.endGlobalAyah + 1)
        let page = try #require(LearningPassage.next(after: range, catalog: catalog, byPage: true))
        let verse = try #require(catalog.verse(globalAyah: page.startGlobalAyah))
        #expect(page.endGlobalAyah == catalog.pages.first(where: { $0.number == verse.page })?.endGlobalAyah)
    }

    @Test @MainActor func finishingWithoutAnAnswerRecordsActivityButNotMemorization() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = PracticeStore(context: container.mainContext)
        let first = VerseRange.clamped(start: 8, end: 10)
        let set = try store.createSet(title: "Small passage", passages: [first], settings: .default)
        #expect(try store.allProgress().isEmpty)
        try store.completePractice(set, ayahs: first.globalAyahs, rating: nil, lastAyah: 10, seconds: 0, repetitions: 0)
        #expect(try store.progress(for: 8).exposureCount == 1)
        #expect(try store.progress(for: 8).lastRating == nil)
        #expect(try store.progress(for: 8).recallAttempts == 0)
        #expect(try store.progress(for: 8).status == .notStarted)
        let overlap = VerseRange.clamped(start: 10, end: 12)
        let other = try store.createSet(title: "Another passage", passages: [overlap], settings: .default)
        try store.completePractice(other, ayahs: overlap.globalAyahs, rating: .solid, lastAyah: 12, seconds: 0, repetitions: 0)
        #expect(try store.progress(for: 10).exposureCount == 2)
        #expect(try store.progress(for: 10).lastRating == .solid)
        #expect(try store.progress(for: 10).status == .memorized)
        #expect(try store.progress(for: 9).lastRating == nil)
        #expect(try store.progress(for: 12).nextReviewAt != nil)
        let sessions = try container.mainContext.fetch(FetchDescriptor<PracticeSession>())
        #expect(sessions.count == 2)
        #expect(sessions.allSatisfy { $0.completed })
    }

    @Test @MainActor func learningPlacePersistsIndependentlyOfReadingPlace() {
        let suite = "LearningTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.remember(.clamped(start: 25, end: 27))
        settings.readingAyah = 100
        settings.practiceByPage = true
        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.learningStart == 25)
        #expect(reopened.learningEnd == 27)
        #expect(reopened.readingAyah == 100)
        #expect(reopened.practiceByPage)
    }
}
